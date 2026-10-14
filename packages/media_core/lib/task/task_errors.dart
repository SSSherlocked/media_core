/// Errors raised by the task manager around task execution.
///
/// Split out of `task_manager.dart` so callers can import the failure
/// types without dragging the whole manager along.
library;

import 'package:media_core/task/player_task.dart';

/// Represents a failure raised while executing a task.
///
/// This wrapper preserves the failed [PlayerTask], original error, and
/// original stack trace for callers that want to distinguish execution
/// failure from cancellation.
final class TaskExecutionFailure implements Exception {
  /// Wraps the failed [task] together with the original [error] and its
  /// [stackTrace].
  const TaskExecutionFailure({required this.task, required this.error, required this.stackTrace});

  /// The task whose execution failed.
  final PlayerTask task;

  /// The original error thrown by the task.
  final Object error;

  /// The stack trace captured with [error].
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'TaskExecutionFailure('
        'task: ${task.id}, '
        'error: $error'
        ')';
  }
}

/// Error used when the task manager is disposed while tasks are running.
final class TaskManagerDisposedError implements Exception {
  /// Signals that pending tasks were dropped because the manager was disposed.
  const TaskManagerDisposedError();

  @override
  String toString() {
    return 'TaskManager was disposed while the task was running.';
  }
}
