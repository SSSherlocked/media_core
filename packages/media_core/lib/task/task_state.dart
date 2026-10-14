import 'package:equatable/equatable.dart';
import 'package:media_core/task/player_task.dart' show PlayerTask;

/// Represents the lifecycle state of a [PlayerTask].
///
/// The normal lifecycle is:
///
/// ```text
/// created
///    │
///    ▼
/// queued
///    │
///    ▼
/// running
///   / | \
///  ▼  ▼  ▼
/// completed
/// failed
/// cancelled
/// ```
///
/// A task cannot leave a terminal state.
final class TaskState extends Equatable {
  /// Creates a task state from [value].
  ///
  /// Unknown values are supported as custom states.
  factory TaskState(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Task state cannot be empty.');
    }

    return TaskState.fromString(normalized);
  }

  /// Creates a task state from a string value.
  factory TaskState.fromValue(String value) {
    return TaskState.fromString(value);
  }
  const TaskState._(this.value);

  /// Creates the canonical state instance for [value].
  ///
  /// Unknown values are returned as custom states.
  factory TaskState.fromString(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Task state cannot be empty.');
    }

    switch (normalized) {
      case 'created':
        return created;
      case 'queued':
        return queued;
      case 'running':
        return running;
      case 'completed':
        return completed;
      case 'failed':
        return failed;
      case 'cancelled':
        return cancelled;
      default:
        return TaskState._(normalized);
    }
  }

  /// Deserializes a task state.
  factory TaskState.fromJson(Object? json) {
    if (json is! String) {
      throw ArgumentError.value(json, 'json', 'Task state must be a string.');
    }

    return TaskState.fromString(json);
  }

  /// Task has been created but has not entered the queue.
  static const TaskState created = TaskState._('created');

  /// Task has been queued and is waiting for execution.
  static const TaskState queued = TaskState._('queued');

  /// Task is currently executing.
  static const TaskState running = TaskState._('running');

  /// Task completed successfully.
  static const TaskState completed = TaskState._('completed');

  /// Task failed during execution.
  static const TaskState failed = TaskState._('failed');

  /// Task was cancelled before completion.
  static const TaskState cancelled = TaskState._('cancelled');

  /// String representation of this state.
  final String value;

  /// Human-readable state name.
  String get name => value;

  // ---------------------------------------------------------------------------
  // Type checks
  // ---------------------------------------------------------------------------

  /// Whether this is a built-in task state.
  bool get isBuiltIn => _builtInValues.contains(value);

  /// Whether this is a custom task state.
  bool get isCustom => !isBuiltIn;

  /// Whether the task has not yet been queued.
  bool get isCreated => value == created.value;

  /// Whether the task is waiting in the queue.
  bool get isQueued => value == queued.value;

  /// Whether the task is currently executing.
  bool get isRunning => value == running.value;

  /// Whether the task completed successfully.
  bool get isCompleted => value == completed.value;

  /// Whether the task failed.
  bool get isFailed => value == failed.value;

  /// Whether the task was cancelled.
  bool get isCancelled => value == cancelled.value;

  /// Whether the task has reached a terminal state.
  ///
  /// Terminal states are:
  ///
  /// - completed
  /// - failed
  /// - cancelled
  bool get isTerminal {
    return isCompleted || isFailed || isCancelled;
  }

  /// Whether the task is waiting to be executed.
  ///
  /// Both [created] and [queued] are considered pending.
  bool get isPending {
    return isCreated || isQueued;
  }

  /// Whether the task is currently participating in the scheduler.
  ///
  /// A task is active when it is queued or running.
  bool get isActive {
    return isQueued || isRunning;
  }

  /// Whether this task can be added to the queue.
  bool get canEnqueue {
    return isCreated;
  }

  /// Whether this task can be started.
  ///
  /// The normal scheduler lifecycle is:
  ///
  /// ```text
  /// created -> queued -> running
  /// ```
  bool get canStart {
    return isQueued;
  }

  /// Whether this task can be cancelled.
  ///
  /// Created, queued, and running tasks can be cancelled.
  bool get canCancel {
    return isCreated || isQueued || isRunning;
  }

  /// Whether this state represents successful completion.
  bool get isSuccess {
    return isCompleted;
  }

  /// Whether this state represents an unsuccessful terminal result.
  bool get isFailure {
    return isFailed || isCancelled;
  }

  // ---------------------------------------------------------------------------
  // Built-in states
  // ---------------------------------------------------------------------------

  /// All built-in state values.
  static const Set<String> _builtInValues = <String>{
    'created',
    'queued',
    'running',
    'completed',
    'failed',
    'cancelled',
  };

  /// All built-in task states.
  static const List<TaskState> builtIns = <TaskState>[created, queued, running, completed, failed, cancelled];

  /// Whether [value] represents a built-in state.
  static bool isBuiltInValue(String value) {
    return _builtInValues.contains(value.trim());
  }

  // ---------------------------------------------------------------------------
  // State transitions
  // ---------------------------------------------------------------------------

  /// Returns whether this state can transition to [next].
  ///
  /// Valid lifecycle transitions:
  ///
  /// ```text
  /// created -> queued
  /// created -> cancelled
  ///
  /// queued -> running
  /// queued -> cancelled
  ///
  /// running -> completed
  /// running -> failed
  /// running -> cancelled
  /// ```
  ///
  /// Terminal states cannot transition to another state.
  bool canTransitionTo(TaskState next) {
    if (value == next.value) {
      return false;
    }

    if (isCreated) {
      return next.isQueued || next.isCancelled;
    }

    if (isQueued) {
      return next.isRunning || next.isCancelled;
    }

    if (isRunning) {
      return next.isCompleted || next.isFailed || next.isCancelled;
    }

    return false;
  }

  /// Returns the valid next states from this state.
  List<TaskState> get nextStates {
    if (isCreated) {
      return const <TaskState>[queued, cancelled];
    }

    if (isQueued) {
      return const <TaskState>[running, cancelled];
    }

    if (isRunning) {
      return const <TaskState>[completed, failed, cancelled];
    }

    return const <TaskState>[];
  }

  /// Returns whether this state has at least one valid next state.
  bool get hasNextState => nextStates.isNotEmpty;

  /// Returns whether this state is a valid terminal state.
  bool get isValidTerminalState {
    return isCompleted || isFailed || isCancelled;
  }

  /// Validates a state transition.
  ///
  /// Throws [StateError] when the transition is invalid.
  void validateTransitionTo(TaskState next) {
    if (!canTransitionTo(next)) {
      throw StateError(
        'Invalid task state transition: '
        '$value -> ${next.value}.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Copy / serialization
  // ---------------------------------------------------------------------------

  /// Creates another state from [value].
  TaskState copyWith(String value) {
    return TaskState(value);
  }

  /// Serializes this state.
  ///
  /// The JSON representation is the state string.
  String toJson() {
    return value;
  }

  // ---------------------------------------------------------------------------
  // Equatable
  // ---------------------------------------------------------------------------

  @override
  List<Object?> get props => <Object?>[value];

  // ---------------------------------------------------------------------------
  // Debugging
  // ---------------------------------------------------------------------------

  @override
  String toString() {
    return value;
  }
}
