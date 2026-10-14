import 'dart:async';

import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/operation/operation_context.dart';
import 'package:media_core/task/player_task.dart';
import 'package:media_core/task/task_cancel_token.dart';
import 'package:media_core/task/task_context.dart';
import 'package:media_core/task/task_errors.dart';
import 'package:media_core/task/task_id.dart';
import 'package:media_core/task/task_priority.dart';
import 'package:media_core/task/task_scheduler.dart';
import 'package:media_core/task/task_state.dart';
import 'package:media_core/task/task_type.dart';

part 'task_manager_cancellation.dart';
// The implementation of [TaskManager] is split by concern across `part`
// files next to this one:
//
// - `task_manager_execution.dart`     queueing, execution, completion, update
// - `task_manager_cancellation.dart`  cancellation, removal, cancel tokens
// - `task_errors.dart`                execution failure / disposed errors
//
// Fields, the constructor, state getters, lookup, creation, registration,
// queries and disposal stay in this file. Extensions are public so the
// callable surface of [TaskManager] is unchanged.

part 'task_manager_execution.dart';

/// Manages the complete lifecycle of [PlayerTask] instances.
///
/// [TaskManager] is the authoritative owner of task lifecycle state.
///
/// Responsibilities:
///
/// - task creation
/// - task registration
/// - task lookup
/// - queue management
/// - task execution
/// - cancellation
/// - cancellation token management
/// - completion
/// - failure
/// - task state bookkeeping
/// - task filtering
///
/// [TaskScheduler] is responsible only for:
///
/// - queue ordering
/// - concurrency limits
/// - admitting queued tasks into running execution slots
/// - releasing execution slots
///
/// [TaskManager] owns the actual task lifecycle.
///
/// The scheduler never owns [TaskCancelToken] and never decides whether a
/// task completed, failed, or was cancelled.
final class TaskManager {
  /// Creates a manager with an optional [scheduler] and a concurrency limit.
  TaskManager({TaskScheduler? scheduler, this.maxConcurrentTasks = 1})
    : _scheduler = scheduler ?? TaskScheduler(maxConcurrentTasks: maxConcurrentTasks) {
    if (maxConcurrentTasks <= 0) {
      throw ArgumentError.value(maxConcurrentTasks, 'maxConcurrentTasks', 'Must be greater than zero.');
    }

    if (_scheduler.maxConcurrentTasks != maxConcurrentTasks) {
      throw ArgumentError.value(
        maxConcurrentTasks,
        'maxConcurrentTasks',
        'Must match the scheduler maxConcurrentTasks.',
      );
    }
  }

  /// Scheduler responsible for queue ordering and execution-slot
  /// bookkeeping.
  final TaskScheduler _scheduler;

  /// Maximum number of tasks allowed to execute concurrently.
  final int maxConcurrentTasks;

  /// Authoritative registry of tasks.
  ///
  /// The scheduler does not own this registry.
  final Map<TaskId, PlayerTask> _tasks = <TaskId, PlayerTask>{};

  /// Cancellation token for tasks that have executable work.
  ///
  /// Token ownership belongs exclusively to [TaskManager].
  final Map<TaskId, TaskCancelToken> _cancelTokens = <TaskId, TaskCancelToken>{};

  bool _isDisposed = false;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// Whether this manager has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether the manager can accept new tasks.
  bool get canSchedule => !_isDisposed;

  /// Number of registered tasks.
  int get length => _tasks.length;

  /// Whether no tasks are registered.
  bool get isEmpty => _tasks.isEmpty;

  /// Whether at least one task is registered.
  bool get isNotEmpty => _tasks.isNotEmpty;

  /// Number of queued tasks.
  int get queuedCount => _scheduler.queuedCount;

  /// Number of running tasks.
  int get runningCount => _scheduler.runningCount;

  /// Number of completed tasks.
  int get completedCount {
    return _countByState((task) => task.isCompleted);
  }

  /// Number of failed tasks.
  int get failedCount {
    return _countByState((task) => task.isFailed);
  }

  /// Number of cancelled tasks.
  int get cancelledCount {
    return _countByState((task) => task.isCancelled);
  }

  /// Whether at least one task is queued.
  bool get hasQueuedTasks => _scheduler.hasQueuedTasks;

  /// Whether at least one task is running.
  bool get hasRunningTasks => _scheduler.hasRunningTasks;

  /// Whether another task can acquire an execution slot.
  bool get hasCapacity => _scheduler.hasCapacity;

  /// Snapshot of all registered tasks.
  List<PlayerTask> get snapshot {
    return List<PlayerTask>.unmodifiable(_tasks.values);
  }

  /// All queued tasks in scheduler order.
  List<PlayerTask> get queuedTasks {
    return _scheduler.queuedTasks;
  }

  /// All currently running tasks.
  ///
  /// A running task remains in the scheduler until its actual asynchronous
  /// execution finishes.
  List<PlayerTask> get runningTasks {
    return _scheduler.runningTasks;
  }

  /// IDs of currently running tasks.
  Set<TaskId> get runningTaskIds {
    return _scheduler.runningTaskIds;
  }

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  /// Returns the authoritative task with [id].
  PlayerTask? get(TaskId id) {
    return _tasks[id];
  }

  /// Whether a task with [id] is registered.
  bool contains(TaskId id) {
    return _tasks.containsKey(id);
  }

  /// Returns a queued task.
  PlayerTask? findQueued(TaskId id) {
    _checkNotDisposed();

    return _scheduler.find(id);
  }

  /// Returns a running task.
  PlayerTask? findRunning(TaskId id) {
    _checkNotDisposed();

    return _scheduler.findRunning(id);
  }

  // ---------------------------------------------------------------------------
  // Creation
  // ---------------------------------------------------------------------------

  /// Creates and registers a task in the [TaskState.created] state.
  PlayerTask create({
    required TaskId id,
    required TaskType type,
    TaskPriority priority = TaskPriority.normal,
    TaskContext? context,
    OperationContext? operationContext,
    PlayerId? playerId,
    RequestId? requestId,
    GenerationId? generationId,
  }) {
    _checkNotDisposed();

    if (_tasks.containsKey(id)) {
      throw StateError('A task with ID "$id" already exists.');
    }

    final task = PlayerTask.created(
      id: id,
      type: type,
      priority: priority,
      context: context,
      operationContext: operationContext,
      playerId: playerId,
      requestId: requestId,
      generationId: generationId,
    );

    _tasks[id] = task;

    return task;
  }

  /// Creates, registers, and queues a task.
  PlayerTask createAndQueue({
    required TaskId id,
    required TaskType type,
    TaskPriority priority = TaskPriority.normal,
    TaskContext? context,
    OperationContext? operationContext,
    PlayerId? playerId,
    RequestId? requestId,
    GenerationId? generationId,
  }) {
    final task = create(
      id: id,
      type: type,
      priority: priority,
      context: context,
      operationContext: operationContext,
      playerId: playerId,
      requestId: requestId,
      generationId: generationId,
    );

    queue(task.id);

    return _tasks[task.id]!;
  }

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Registers an existing task.
  ///
  /// The task must not be running.
  ///
  /// Queued tasks are inserted into the scheduler.
  ///
  /// Created and terminal tasks are registered only in the manager.
  bool register(PlayerTask task) {
    _checkNotDisposed();

    if (_tasks.containsKey(task.id)) {
      return false;
    }

    if (task.isRunning || _scheduler.isRunning(task.id)) {
      throw StateError(
        'A running task cannot be registered directly. '
        'A running task must first acquire a scheduler execution slot.',
      );
    }

    if (task.isQueued) {
      final scheduled = _scheduler.schedule(task);

      if (!scheduled) {
        return false;
      }
    }

    _tasks[task.id] = task;

    return true;
  }

  /// Registers [task], replacing an existing non-running task.
  ///
  /// Running tasks cannot be replaced.
  ///
  /// Returns the previous task when one existed.
  PlayerTask? registerOrReplace(PlayerTask task) {
    _checkNotDisposed();

    final previous = _tasks[task.id];

    if (previous?.isRunning == true || _scheduler.isRunning(task.id)) {
      throw StateError('A running task cannot be replaced.');
    }

    if (task.isQueued) {
      final scheduled = _scheduler.scheduleOrReplace(task);

      if (!scheduled) {
        throw StateError('Unable to schedule task "${task.id}" for replacement.');
      }
    } else {
      _scheduler.unschedule(task.id);
    }

    _tasks[task.id] = task;

    return previous;
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Returns tasks matching [test].
  List<PlayerTask> where(bool Function(PlayerTask task) test) {
    return List<PlayerTask>.unmodifiable(_tasks.values.where(test));
  }

  /// Returns tasks of [type].
  List<PlayerTask> byType(TaskType type) {
    return where((task) => task.type == type);
  }

  /// Returns tasks with [priority].
  List<PlayerTask> byPriority(TaskPriority priority) {
    return where((task) => task.priority == priority);
  }

  /// Returns tasks currently in [state].
  List<PlayerTask> byState(TaskState state) {
    return where((task) => task.state == state);
  }

  /// Returns tasks belonging to [playerId].
  List<PlayerTask> byPlayerId(PlayerId playerId) {
    return where((task) => task.playerId == playerId);
  }

  /// Returns tasks belonging to [requestId].
  List<PlayerTask> byRequestId(RequestId requestId) {
    return where((task) => task.requestId == requestId);
  }

  /// Returns tasks belonging to [generationId].
  List<PlayerTask> byGenerationId(GenerationId generationId) {
    return where((task) => task.generationId == generationId);
  }

  /// Returns queued or running tasks.
  List<PlayerTask> get activeTasks {
    return where((task) => task.isQueued || task.isRunning);
  }

  /// Returns terminal tasks.
  List<PlayerTask> get terminalTasks {
    return where((task) => task.isTerminal);
  }

  /// Returns pending tasks.
  List<PlayerTask> get pendingTasks {
    return where((task) => task.isPending);
  }
  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Resets the manager.
  ///
  /// Queued tasks are removed.
  ///
  /// Running tasks receive cancellation requests but continue to occupy their
  /// scheduler slots until execution actually finishes.
  ///
  /// Registered terminal tasks are removed.
  void reset() {
    _checkNotDisposed();

    // Slot ownership — not lifecycle state — decides what is still running.
    // A cancelled task reports `isRunning == false` while its handler keeps
    // executing, and that handler registers its final state when it finishes;
    // dropping it here would resurrect it into a reset manager.
    final executingIds = _scheduler.runningTaskIds..forEach(cancel);

    _scheduler.reset();

    final removableIds = _tasks.keys.where((id) => !executingIds.contains(id)).toList(growable: false);

    for (final id in removableIds) {
      _disposeToken(id);
      _tasks.remove(id);
    }

    _disposeCompletedTokens();
  }

  /// Disposes the manager.
  ///
  /// Cancellation is requested for all token-backed work.
  ///
  /// Running handlers are not forcibly interrupted.
  ///
  /// After disposal:
  ///
  /// - no new task can be registered;
  /// - no new execution can start;
  /// - scheduler queue/bookkeeping is discarded;
  /// - cancellation tokens are cancelled and disposed;
  /// - registered task state is cleared.
  ///
  /// Existing asynchronous handlers may still finish in the background.
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel(const TaskManagerDisposedError());
      }
    }

    _scheduler.dispose();

    for (final token in _cancelTokens.values) {
      token.dispose();
    }

    _cancelTokens.clear();
    _tasks.clear();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  /// Converts an execution task to the cancelled terminal state.
  PlayerTask _cancelTaskAfterExecution(PlayerTask task, Object? reason) {
    final cancelledTask = task.cancel(error: reason);

    if (!_isDisposed) {
      _tasks[task.id] = cancelledTask;
    }

    return cancelledTask;
  }

  /// Removes and disposes the token associated with [id].
  void _disposeToken(TaskId id) {
    final token = _cancelTokens.remove(id);

    token?.dispose();
  }

  /// Disposes tokens that no longer belong to a still-executing task.
  ///
  /// Execution slots are the authority: a cancelled task is terminal, but its
  /// handler may still be running and still observing its token.
  void _disposeCompletedTokens() {
    final executingIds = _scheduler.runningTaskIds;

    _cancelTokens.keys.where((id) => !executingIds.contains(id)).toList(growable: false).forEach(_disposeToken);
  }

  /// Returns a registered task or throws.
  PlayerTask _requireTask(TaskId id) {
    final task = _tasks[id];

    if (task == null) {
      throw StateError('Task "$id" is not registered.');
    }

    return task;
  }

  /// Counts tasks matching [test].
  int _countByState(bool Function(PlayerTask task) test) {
    return _tasks.values.where(test).length;
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('TaskManager has already been disposed.');
    }
  }

  @override
  String toString() {
    return 'TaskManager('
        'tasks: $length, '
        'queued: $queuedCount, '
        'running: $runningCount, '
        'completed: $completedCount, '
        'failed: $failedCount, '
        'cancelled: $cancelledCount, '
        'maxConcurrentTasks: $maxConcurrentTasks, '
        'disposed: $isDisposed'
        ')';
  }
}
