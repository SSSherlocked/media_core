import 'package:equatable/equatable.dart';
import 'package:media_core/task/player_task.dart';
import 'package:media_core/task/task_id.dart';
import 'package:media_core/task/task_priority.dart';
import 'package:media_core/task/task_state.dart';

/// A priority-aware immutable queue for [PlayerTask].
///
/// Tasks are ordered by:
///
/// 1. Higher priority first.
/// 2. Earlier queued time first.
/// 3. Earlier created time first.
/// 4. Smaller task id as the final deterministic tie-breaker.
///
/// The queue itself does not execute tasks. It only manages queued work.
///
/// [TaskQueue] is immutable. All mutating operations return a new queue.
final class TaskQueue extends Equatable {
  /// Creates a queue holding the queued tasks among [tasks], in scheduling
  /// order.
  TaskQueue({Iterable<PlayerTask> tasks = const <PlayerTask>[]})
    : _tasks = List<PlayerTask>.unmodifiable(_sortTasks(tasks.where((task) => task.isQueued)));

  /// Internal ordered task list.
  final List<PlayerTask> _tasks;

  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------

  /// Number of queued tasks.
  int get length => _tasks.length;

  /// Whether the queue contains no tasks.
  bool get isEmpty => _tasks.isEmpty;

  /// Whether the queue contains at least one task.
  bool get isNotEmpty => _tasks.isNotEmpty;

  /// All queued tasks in execution order.
  ///
  /// The returned list is immutable.
  List<PlayerTask> get tasks => _tasks;

  /// The next task without removing it.
  PlayerTask? get first => isEmpty ? null : _tasks.first;

  /// The last task in the current ordering.
  PlayerTask? get last => isEmpty ? null : _tasks.last;

  /// Whether this queue contains exactly one task.
  bool get isSingle => length == 1;

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  /// Whether the queue contains [id].
  bool contains(TaskId id) {
    return _tasks.any((task) => task.id == id);
  }

  /// Finds a queued task by id.
  PlayerTask? find(TaskId id) {
    for (final task in _tasks) {
      if (task.id == id) {
        return task;
      }
    }

    return null;
  }

  /// Finds the index of a task by id.
  ///
  /// Returns `-1` when the task does not exist.
  int indexOf(TaskId id) {
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].id == id) {
        return i;
      }
    }

    return -1;
  }

  /// Returns whether a task matching [predicate] exists.
  bool any(bool Function(PlayerTask task) predicate) {
    return _tasks.any(predicate);
  }

  /// Returns whether every queued task matches [predicate].
  bool every(bool Function(PlayerTask task) predicate) {
    return _tasks.every(predicate);
  }

  // ---------------------------------------------------------------------------
  // Add
  // ---------------------------------------------------------------------------

  /// Adds a task to the queue.
  ///
  /// The task must be in the queued state.
  ///
  /// If another task with the same id exists, it is replaced.
  TaskQueue add(PlayerTask task) {
    _validateQueuedTask(task);

    final updated = <PlayerTask>[..._tasks.where((item) => item.id != task.id), task];

    return TaskQueue(tasks: updated);
  }

  /// Adds multiple tasks to the queue.
  ///
  /// Existing tasks with the same ids are replaced.
  TaskQueue addAll(Iterable<PlayerTask> tasks) {
    var result = this;

    for (final task in tasks) {
      result = result.add(task);
    }

    return result;
  }

  /// Replaces an existing task or inserts it if it does not exist.
  TaskQueue replace(PlayerTask task) {
    return add(task);
  }

  /// Replaces multiple tasks.
  TaskQueue replaceAll(Iterable<PlayerTask> tasks) {
    return addAll(tasks);
  }

  // ---------------------------------------------------------------------------
  // Remove
  // ---------------------------------------------------------------------------

  /// Removes the next task from the queue.
  ///
  /// Returns both the removed task and the remaining queue.
  TaskQueueResult take() {
    if (isEmpty) {
      return TaskQueueResult.empty(this);
    }

    final task = _tasks.first;

    return TaskQueueResult(
      queue: TaskQueue(tasks: _tasks.skip(1)),
      task: task,
    );
  }

  /// Removes a task by id.
  ///
  /// If the task does not exist, the original queue is returned.
  TaskQueueResult remove(TaskId id) {
    final task = find(id);

    if (task == null) {
      return TaskQueueResult.empty(this);
    }

    final remaining = _tasks.where((item) => item.id != id);

    return TaskQueueResult(
      queue: TaskQueue(tasks: remaining),
      task: task,
    );
  }

  /// Removes all tasks.
  TaskQueue clear() {
    if (isEmpty) {
      return this;
    }

    return TaskQueue();
  }

  /// Returns the queue without the task identified by [id].
  TaskQueue without(TaskId id) {
    return remove(id).queue;
  }

  /// Removes all tasks matching [predicate].
  TaskQueue removeWhere(bool Function(PlayerTask task) predicate) {
    if (!_tasks.any(predicate)) {
      return this;
    }

    return TaskQueue(tasks: _tasks.where((task) => !predicate(task)));
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Returns tasks matching [predicate].
  List<PlayerTask> where(bool Function(PlayerTask task) predicate) {
    return List<PlayerTask>.unmodifiable(_tasks.where(predicate));
  }

  /// Returns tasks of the given priority.
  List<PlayerTask> byPriority(TaskPriority priority) {
    return where((task) => task.priority == priority);
  }

  /// Returns tasks with priority greater than or equal to [priority].
  List<PlayerTask> byMinimumPriority(TaskPriority priority) {
    return where((task) => task.priority >= priority);
  }

  /// Returns tasks of the given state.
  ///
  /// Normally every task in this queue is [TaskState.queued], but this method
  /// is intentionally generic for future queue implementations.
  List<PlayerTask> byState(TaskState state) {
    return where((task) => task.state == state);
  }

  /// Returns whether any queued task has [priority].
  bool hasPriority(TaskPriority priority) {
    return _tasks.any((task) => task.priority == priority);
  }

  /// Returns the number of tasks with [priority].
  int countPriority(TaskPriority priority) {
    return _tasks.where((task) => task.priority == priority).length;
  }

  /// Returns the number of tasks matching [predicate].
  int countWhere(bool Function(PlayerTask task) predicate) {
    return _tasks.where(predicate).length;
  }

  /// Returns a queue containing only tasks matching [predicate].
  TaskQueue filter(bool Function(PlayerTask task) predicate) {
    return TaskQueue(tasks: _tasks.where(predicate));
  }

  /// Returns a queue containing tasks with [priority] or higher.
  TaskQueue withMinimumPriority(TaskPriority priority) {
    return TaskQueue(tasks: _tasks.where((task) => task.priority >= priority));
  }

  /// Returns whether at least one task is at [priority] or higher.
  bool hasMinimumPriority(TaskPriority priority) {
    return _tasks.any((task) => task.priority >= priority);
  }

  // ---------------------------------------------------------------------------
  // Ordering
  // ---------------------------------------------------------------------------

  /// Returns a reordered copy of the queue.
  ///
  /// This is mainly useful when task metadata such as priority or queued time
  /// has changed.
  TaskQueue reorder() {
    if (length <= 1) {
      return this;
    }

    return TaskQueue(tasks: _tasks);
  }

  /// Returns the tasks as an immutable ordered list.
  List<PlayerTask> toList() {
    return _tasks;
  }

  /// Returns the task at [index].
  PlayerTask operator [](int index) {
    return _tasks[index];
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  static void _validateQueuedTask(PlayerTask task) {
    if (!task.isQueued) {
      throw StateError(
        'Only queued tasks can be added to TaskQueue. '
        'Task ${task.id} is in state ${task.state}.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Sorting
  // ---------------------------------------------------------------------------

  static List<PlayerTask> _sortTasks(Iterable<PlayerTask> tasks) {
    final result = List<PlayerTask>.from(tasks)..sort(_compareTasks);

    return result;
  }

  static int _compareTasks(PlayerTask a, PlayerTask b) {
    // Higher priority comes first.
    final priorityComparison = b.priority.compareTo(a.priority);

    if (priorityComparison != 0) {
      return priorityComparison;
    }

    // Earlier queued tasks come first.
    final queuedAtComparison = _compareNullableDateTime(a.queuedAt, b.queuedAt);

    if (queuedAtComparison != 0) {
      return queuedAtComparison;
    }

    // Earlier created tasks come first.
    final createdAtComparison = _compareNullableDateTime(a.createdAt, b.createdAt);

    if (createdAtComparison != 0) {
      return createdAtComparison;
    }

    // Deterministic final ordering.
    return a.id.compareTo(b.id);
  }

  static int _compareNullableDateTime(DateTime? a, DateTime? b) {
    if (identical(a, b)) {
      return 0;
    }

    if (a == null) {
      return 1;
    }

    if (b == null) {
      return -1;
    }

    return a.compareTo(b);
  }

  // ---------------------------------------------------------------------------
  // Equatable
  // ---------------------------------------------------------------------------

  @override
  List<Object?> get props => <Object?>[_tasks];

  // ---------------------------------------------------------------------------
  // Debugging
  // ---------------------------------------------------------------------------

  @override
  String toString() {
    return 'TaskQueue('
        'length: $length, '
        'tasks: $_tasks'
        ')';
  }
}

/// Result returned by queue operations that may remove a task.
///
/// This is intentionally a small immutable value object rather than a
/// Freezed DTO because it is only a runtime result of queue manipulation.
final class TaskQueueResult extends Equatable {
  /// Pairs the resulting [queue] with the [task] it removed, if any.
  const TaskQueueResult({required this.queue, this.task});

  /// Pairs the resulting [queue] with no removed task.
  const TaskQueueResult.empty(this.queue) : task = null;

  /// Queue after the operation.
  final TaskQueue queue;

  /// Removed task, or null when no task was removed.
  final PlayerTask? task;

  /// Whether a task was removed.
  bool get hasTask => task != null;

  /// Whether no task was removed.
  bool get isEmpty => task == null;

  @override
  List<Object?> get props => <Object?>[queue, task];

  @override
  String toString() {
    return 'TaskQueueResult('
        'hasTask: $hasTask, '
        'task: $task'
        ')';
  }
}
