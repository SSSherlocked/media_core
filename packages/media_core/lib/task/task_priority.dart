import 'package:equatable/equatable.dart';
import 'package:media_core/task/player_task.dart' show PlayerTask;

/// Defines the priority of a [PlayerTask].
///
/// Higher numeric values represent higher scheduling priority.
///
/// Built-in priorities:
///
/// ```text
/// highest   =  100
/// high      =   10
/// normal    =    0
/// low       =  -10
/// lowest    = -100
/// ```
///
/// Custom priorities are also supported:
///
/// ```dart
/// final priority = TaskPriority.custom(50);
/// ```
///
/// [TaskPriority] is a value object.
///
/// Equality is determined only by [value]. The [name] is descriptive and
/// does not participate in equality.
final class TaskPriority extends Equatable implements Comparable<TaskPriority> {
  /// Creates a custom task priority.
  ///
  /// Higher [value] means higher scheduling priority.
  ///
  /// If [name] is omitted or empty, a name in the form
  /// `custom:<value>` is generated.
  factory TaskPriority.custom(int value, {String? name}) {
    final normalizedName = name?.trim();

    return TaskPriority._(value, normalizedName == null || normalizedName.isEmpty ? 'custom:$value' : normalizedName);
  }
  const TaskPriority._(this.value, this.name);

  /// Returns the canonical built-in priority for [value].
  ///
  /// Unknown values are represented as custom priorities.
  factory TaskPriority.fromValue(int value) {
    switch (value) {
      case -100:
        return lowest;
      case -10:
        return low;
      case 0:
        return normal;
      case 10:
        return high;
      case 100:
        return highest;
      default:
        return TaskPriority.custom(value);
    }
  }

  /// Creates a priority from a JSON-compatible value.
  ///
  /// The canonical JSON representation is an integer.
  ///
  /// Integer-valued [num] and numeric [String] values are also accepted for
  /// tolerant deserialization.
  factory TaskPriority.fromJson(Object? json) {
    if (json is int) {
      return TaskPriority.fromValue(json);
    }

    if (json is num) {
      if (!json.isFinite || json != json.truncateToDouble()) {
        throw ArgumentError.value(json, 'json', 'Task priority must be an integer.');
      }

      return TaskPriority.fromValue(json.toInt());
    }

    if (json is String) {
      final value = int.tryParse(json.trim());

      if (value != null) {
        return TaskPriority.fromValue(value);
      }
    }

    throw ArgumentError.value(json, 'json', 'Task priority must be an integer.');
  }

  factory TaskPriority._fromValueWithName(int value, {String? name}) {
    switch (value) {
      case -100:
        return lowest;
      case -10:
        return low;
      case 0:
        return normal;
      case 10:
        return high;
      case 100:
        return highest;
      default:
        return TaskPriority.custom(value, name: name);
    }
  }

  /// Lowest built-in task priority.
  static const TaskPriority lowest = TaskPriority._(-100, 'lowest');

  /// Low built-in task priority.
  static const TaskPriority low = TaskPriority._(-10, 'low');

  /// Normal built-in task priority.
  static const TaskPriority normal = TaskPriority._(0, 'normal');

  /// High built-in task priority.
  static const TaskPriority high = TaskPriority._(10, 'high');

  /// Highest built-in task priority.
  static const TaskPriority highest = TaskPriority._(100, 'highest');

  /// All built-in priorities ordered from lowest to highest.
  static const List<TaskPriority> builtIns = <TaskPriority>[lowest, low, normal, high, highest];

  static const Set<int> _builtInValues = <int>{-100, -10, 0, 10, 100};

  /// Numeric priority value.
  ///
  /// Higher values have higher scheduling priority.
  final int value;

  /// Human-readable priority name.
  ///
  /// This value does not participate in equality.
  final String name;

  // ---------------------------------------------------------------------------
  // Built-in priority checks
  // ---------------------------------------------------------------------------

  /// Whether this is the lowest built-in priority.
  bool get isLowest => value == lowest.value;

  /// Whether this is the low built-in priority.
  bool get isLow => value == low.value;

  /// Whether this is the normal built-in priority.
  bool get isNormal => value == normal.value;

  /// Whether this is the high built-in priority.
  bool get isHigh => value == high.value;

  /// Whether this is the highest built-in priority.
  bool get isHighest => value == highest.value;

  /// Whether this priority uses a built-in numeric value.
  bool get isBuiltIn => _builtInValues.contains(value);

  /// Whether this priority is custom.
  bool get isCustom => !isBuiltIn;

  // ---------------------------------------------------------------------------
  // Numeric checks
  // ---------------------------------------------------------------------------

  /// Whether this priority is positive.
  bool get isPositive => value > 0;

  /// Whether this priority is negative.
  bool get isNegative => value < 0;

  /// Whether this priority is neutral.
  bool get isNeutral => value == 0;

  // ---------------------------------------------------------------------------
  // Comparison
  // ---------------------------------------------------------------------------

  /// Whether this priority has a higher value than [other].
  bool isHigherThan(TaskPriority other) {
    return value > other.value;
  }

  /// Whether this priority has a lower value than [other].
  bool isLowerThan(TaskPriority other) {
    return value < other.value;
  }

  /// Whether this priority is greater than or equal to [other].
  bool isHigherOrEqual(TaskPriority other) {
    return value >= other.value;
  }

  /// Whether this priority is less than or equal to [other].
  bool isLowerOrEqual(TaskPriority other) {
    return value <= other.value;
  }

  /// Whether this priority has the same numeric value as [other].
  bool isSameAs(TaskPriority other) {
    return value == other.value;
  }

  @override
  int compareTo(TaskPriority other) {
    return value.compareTo(other.value);
  }

  /// Whether this priority is lower than [other].
  bool operator <(TaskPriority other) {
    return value < other.value;
  }

  /// Whether this priority is lower than or equal to [other].
  bool operator <=(TaskPriority other) {
    return value <= other.value;
  }

  /// Whether this priority is higher than [other].
  bool operator >(TaskPriority other) {
    return value > other.value;
  }

  /// Whether this priority is higher than or equal to [other].
  bool operator >=(TaskPriority other) {
    return value >= other.value;
  }

  // ---------------------------------------------------------------------------
  // Conversion
  // ---------------------------------------------------------------------------

  /// Serializes this priority.
  ///
  /// Only the numeric [value] is serialized because it is the semantic
  /// scheduling value.
  int toJson() {
    return value;
  }

  // ---------------------------------------------------------------------------
  // Copy
  // ---------------------------------------------------------------------------

  /// Creates a priority with a different numeric value.
  ///
  /// Built-in values are automatically converted to their canonical
  /// instances.
  ///
  /// When [value] is unchanged and [name] is omitted, this instance is
  /// returned.
  TaskPriority copyWith(int value, {String? name}) {
    if (value == this.value && name == null) {
      return this;
    }

    return TaskPriority._fromValueWithName(value, name: name);
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  /// Returns the absolute distance between this priority and [other].
  int distanceTo(TaskPriority other) {
    return (value - other.value).abs();
  }

  /// Returns the higher priority between this priority and [other].
  TaskPriority max(TaskPriority other) {
    return value >= other.value ? this : other;
  }

  /// Returns the lower priority between this priority and [other].
  TaskPriority min(TaskPriority other) {
    return value <= other.value ? this : other;
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
    return name;
  }
}
