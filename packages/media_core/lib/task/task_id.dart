import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/task/player_task.dart' show PlayerTask;

/// Immutable unique identifier for a [PlayerTask].
///
/// [TaskId] is intentionally a small value object rather than a raw
/// [String]. This prevents accidental mixing of task IDs with other kinds
/// of identifiers such as request IDs or generation IDs.
final class TaskId extends Equatable implements Comparable<TaskId> {
  /// Creates a task ID from a non-empty string.
  ///
  /// Leading and trailing whitespace is removed.
  ///
  /// Throws [ArgumentError] when the normalized value is empty.
  factory TaskId(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Task ID must not be empty.');
    }

    return TaskId._(normalized);
  }

  const TaskId._(this.value);

  /// Creates a new unique task ID.
  ///
  /// The generated format is:
  ///
  /// ```text
  /// task_<timestamp>_<counter>
  /// ```
  ///
  /// [clock] is used instead of [DateTime.now] so ID generation remains
  /// deterministic in tests.
  factory TaskId.generate() {
    final timestamp = clock.now().microsecondsSinceEpoch;
    final counter = _counter++;

    return TaskId._('task_${timestamp}_$counter');
  }

  /// Creates a [TaskId] from a string.
  ///
  /// This is equivalent to calling [TaskId].
  factory TaskId.parse(String value) = TaskId;

  /// Creates a [TaskId] from a JSON-compatible value.
  ///
  /// Throws [FormatException] when [json] is not a string.
  factory TaskId.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('TaskId JSON value must be a String.');
    }

    return TaskId(json);
  }

  static int _counter = 0;

  /// The normalized string representation of this ID.
  final String value;

  /// Returns whether this ID is empty.
  ///
  /// This is always `false` for a valid [TaskId].
  bool get isEmpty => value.isEmpty;

  /// Returns whether this ID is non-empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns whether [value] represents a valid task ID.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Compares this ID with [other] lexicographically.
  @override
  int compareTo(TaskId other) {
    return value.compareTo(other.value);
  }

  /// Returns this ID as a JSON-compatible string.
  String toJson() {
    return value;
  }

  @override
  List<Object?> get props => [value];

  @override
  String toString() {
    return value;
  }
}
