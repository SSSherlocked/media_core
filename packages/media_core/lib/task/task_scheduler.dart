import 'package:media_core/task/library.dart' show TaskCancelToken, TaskManager, TaskState;
import 'package:media_core/task/player_task.dart';
import 'package:media_core/task/task_id.dart';
import 'package:media_core/task/task_priority.dart';
import 'package:media_core/task/task_queue.dart';

/// Schedules [PlayerTask] instances for execution.
///
/// [TaskScheduler] is responsible only for scheduling and execution-slot
/// bookkeeping.
///
/// Responsibilities:
///
/// - maintaining the task queue
/// - queue ordering through [TaskQueue]
/// - enforcing [maxConcurrentTasks]
/// - admitting queued tasks into the running set
/// - tracking running execution slots
/// - releasing running execution slots
///
/// [TaskScheduler] does NOT own:
///
/// - task cancellation
/// - [TaskCancelToken]
/// - task completion
/// - task failure
/// - task retry
/// - business execution
/// - task registry
///
/// Those responsibilities belong to [TaskManager].
///
/// The scheduler is therefore intentionally lifecycle-neutral except for the
/// scheduling transition from `queued` to `running`.
final class TaskScheduler {
  /// Creates a scheduler over an optional [queue] with at most
  /// [maxConcurrentTasks] running tasks.
  TaskScheduler({TaskQueue? queue, this.maxConcurrentTasks = 1}) : _queue = queue ?? TaskQueue() {
    if (maxConcurrentTasks <= 0) {
      throw ArgumentError.value(maxConcurrentTasks, 'maxConcurrentTasks', 'Must be greater than zero.');
    }
  }

  /// Queue containing tasks waiting for an execution slot.
  TaskQueue _queue;

  /// Maximum number of tasks that may occupy execution slots concurrently.
  final int maxConcurrentTasks;

  /// Tasks that have acquired an execution slot.
  ///
  /// A task remains here until [release] is called.
  final Map<TaskId, PlayerTask> _runningTasks = <TaskId, PlayerTask>{};

  bool _isDisposed = false;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// Whether this scheduler has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether this scheduler can accept new tasks.
  bool get canSchedule => !_isDisposed;

  /// Number of queued tasks.
  int get queuedCount => _queue.length;

  /// Number of running tasks.
  int get runningCount => _runningTasks.length;

  /// Whether at least one task is waiting in the queue.
  bool get hasQueuedTasks => _queue.isNotEmpty;

  /// Whether at least one task currently occupies an execution slot.
  bool get hasRunningTasks => _runningTasks.isNotEmpty;

  /// Whether another task can acquire an execution slot.
  bool get hasCapacity {
    return runningCount < maxConcurrentTasks;
  }

  /// Number of currently available execution slots.
  int get availableCapacity {
    final available = maxConcurrentTasks - runningCount;

    return available < 0 ? 0 : available;
  }

  /// Returns queued tasks in scheduler order.
  List<PlayerTask> get queuedTasks {
    _checkNotDisposed();

    return _queue.tasks;
  }

  /// Returns currently running tasks.
  List<PlayerTask> get runningTasks {
    _checkNotDisposed();

    return List<PlayerTask>.unmodifiable(_runningTasks.values);
  }

  /// Returns IDs of currently running tasks.
  Set<TaskId> get runningTaskIds {
    _checkNotDisposed();

    return Set<TaskId>.unmodifiable(_runningTasks.keys);
  }

  /// Returns all tasks currently owned by the scheduler.
  ///
  /// Queued tasks are returned before running tasks.
  List<PlayerTask> get allTasks {
    _checkNotDisposed();

    return List<PlayerTask>.unmodifiable(<PlayerTask>[..._queue.tasks, ..._runningTasks.values]);
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  /// Schedules a task that is already in the queued state.
  ///
  /// [TaskManager] is responsible for changing a created task into the
  /// queued state. The scheduler itself does not perform that transition
  /// when accepting a task.
  ///
  /// Returns `false` when a task with the same ID is already queued or
  /// running.
  bool schedule(PlayerTask task) {
    _checkNotDisposed();

    if (!task.isQueued) {
      throw StateError(
        'Only queued tasks can be scheduled. '
        'Task ${task.id} is in state ${task.state}.',
      );
    }

    if (_queue.contains(task.id) || _runningTasks.containsKey(task.id)) {
      return false;
    }

    _queue = _queue.add(task);

    return true;
  }

  /// Schedules a queued task, replacing an existing queued task with the
  /// same ID.
  ///
  /// Running tasks cannot be replaced.
  ///
  /// The supplied task must already be in the queued state.
  bool scheduleOrReplace(PlayerTask task) {
    _checkNotDisposed();

    if (!task.isQueued) {
      throw StateError(
        'Only queued tasks can be scheduled. '
        'Task ${task.id} is in state ${task.state}.',
      );
    }

    if (_runningTasks.containsKey(task.id)) {
      return false;
    }

    _queue = _queue.add(task);

    return true;
  }

  /// Schedules all tasks that can be accepted.
  ///
  /// Returns the number of tasks successfully scheduled.
  int scheduleAll(Iterable<PlayerTask> tasks) {
    _checkNotDisposed();

    var count = 0;

    for (final task in tasks) {
      if (schedule(task)) {
        count++;
      }
    }

    return count;
  }

  /// Schedules all tasks, replacing existing queued tasks with matching IDs.
  ///
  /// Running tasks are never replaced.
  ///
  /// Returns the number of tasks successfully scheduled.
  int scheduleOrReplaceAll(Iterable<PlayerTask> tasks) {
    _checkNotDisposed();

    var count = 0;

    for (final task in tasks) {
      if (scheduleOrReplace(task)) {
        count++;
      }
    }

    return count;
  }

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  /// Returns a queued task by [id].
  PlayerTask? find(TaskId id) {
    _checkNotDisposed();

    return _queue.find(id);
  }

  /// Returns a running task by [id].
  PlayerTask? findRunning(TaskId id) {
    _checkNotDisposed();

    return _runningTasks[id];
  }

  /// Returns a task from either the running set or queue.
  PlayerTask? findAny(TaskId id) {
    _checkNotDisposed();

    return _runningTasks[id] ?? _queue.find(id);
  }

  /// Whether [id] is currently queued.
  bool isQueued(TaskId id) {
    _checkNotDisposed();

    return _queue.contains(id);
  }

  /// Whether [id] currently occupies an execution slot.
  bool isRunning(TaskId id) {
    _checkNotDisposed();

    return _runningTasks.containsKey(id);
  }

  // ---------------------------------------------------------------------------
  // Execution slot acquisition
  // ---------------------------------------------------------------------------

  /// Takes the next queued task when execution capacity is available.
  ///
  /// The operation performs the scheduling transition:
  ///
  /// ```text
  /// queued
  ///   ↓
  /// running
  /// ```
  ///
  /// Internally it:
  ///
  /// 1. takes the highest-priority task from the queue;
  /// 2. transitions it to [TaskState.running];
  /// 3. records it in the running set;
  /// 4. reserves one execution slot.
  ///
  /// The scheduler does not execute any business logic.
  ///
  /// Returns `null` when:
  ///
  /// - no execution slot is available; or
  /// - the queue is empty.
  PlayerTask? takeNext() {
    _checkNotDisposed();

    if (!hasCapacity || !hasQueuedTasks) {
      return null;
    }

    final result = _queue.take();

    _queue = result.queue;

    final task = result.task;

    if (task == null) {
      return null;
    }

    final runningTask = task.start();

    _runningTasks[runningTask.id] = runningTask;

    return runningTask;
  }

  // ---------------------------------------------------------------------------
  // Execution slot release
  // ---------------------------------------------------------------------------

  /// Releases the execution slot occupied by [id].
  ///
  /// This method only changes scheduler bookkeeping.
  ///
  /// It does NOT change the [PlayerTask] lifecycle state.
  ///
  /// The task lifecycle is managed by [TaskManager].
  ///
  /// This method intentionally remains safe after [dispose], because an
  /// asynchronous execution may finish after the scheduler has been
  /// disposed.
  bool release(TaskId id) {
    return _runningTasks.remove(id) != null;
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  /// Removes a task from the queue.
  ///
  /// This only changes scheduler membership.
  ///
  /// It does not change the lifecycle state of the returned task.
  PlayerTask? unschedule(TaskId id) {
    _checkNotDisposed();

    final result = _queue.remove(id);

    _queue = result.queue;

    return result.task;
  }

  /// Removes all queued tasks.
  ///
  /// Running tasks are not affected.
  ///
  /// Task lifecycle state is not modified.
  void clearQueue() {
    _checkNotDisposed();

    _queue = _queue.clear();
  }

  /// Removes queued tasks matching [test].
  ///
  /// Running tasks are not affected.
  ///
  /// Returns the number of removed queued tasks.
  int removeWhere(bool Function(PlayerTask task) test) {
    _checkNotDisposed();

    final before = _queue.length;

    _queue = _queue.removeWhere(test);

    return before - _queue.length;
  }

  /// Returns queued tasks having exactly [priority].
  List<PlayerTask> byPriority(TaskPriority priority) {
    _checkNotDisposed();

    return _queue.byPriority(priority);
  }

  /// Returns queued tasks having [priority] or higher.
  List<PlayerTask> byMinimumPriority(TaskPriority priority) {
    _checkNotDisposed();

    return _queue.byMinimumPriority(priority);
  }

  /// Whether at least one queued task has [priority] or higher.
  bool hasMinimumPriority(TaskPriority priority) {
    _checkNotDisposed();

    return _queue.hasMinimumPriority(priority);
  }

  /// Reorders the queue using its canonical ordering rules.
  void reorderQueue() {
    _checkNotDisposed();

    _queue = _queue.reorder();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Resets queued scheduling state.
  ///
  /// Running tasks are intentionally preserved.
  ///
  /// Clearing [_runningTasks] here would release scheduler bookkeeping while
  /// the actual asynchronous work could still be running, which could cause
  /// the effective concurrency limit to be exceeded.
  void reset() {
    _checkNotDisposed();

    _queue = _queue.clear();
  }

  /// Disposes the scheduler.
  ///
  /// Queued tasks are discarded.
  ///
  /// Running bookkeeping is cleared because the scheduler is no longer
  /// accepting or coordinating new work.
  ///
  /// This method does not and cannot forcibly interrupt actual asynchronous
  /// handlers. Running execution is owned by [TaskManager].
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _queue = _queue.clear();
    _runningTasks.clear();

    _isDisposed = true;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('TaskScheduler has already been disposed.');
    }
  }

  @override
  String toString() {
    return 'TaskScheduler('
        'queued: $queuedCount, '
        'running: $runningCount, '
        'maxConcurrentTasks: $maxConcurrentTasks, '
        'disposed: $isDisposed'
        ')';
  }
}
