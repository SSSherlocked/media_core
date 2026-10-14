import 'package:equatable/equatable.dart';

/// Priority used by the event dispatcher.
///
/// Higher priority events are dispatched before lower priority events when
/// they are queued in the same dispatch cycle.
enum EventPriority {
  /// Background detail (diagnostics, progress ticks) that may be delayed
  /// behind anything more urgent without harming the user.
  low,

  /// Routine event that carries no ordering urgency of its own.
  normal,

  /// Event tied to something the user can perceive, dispatched ahead of
  /// routine traffic when a cycle is congested.
  high,

  /// Event that must lead every queued event in its cycle, such as an error
  /// that should reach the UI before anything that follows it.
  critical,
}

/// Immutable priority value with ordering helpers.
final class EventPriorityValue extends Equatable {
  /// Wraps an [EventPriority] so ordering helpers can be expressed as
  /// operators on a comparable value object.
  const EventPriorityValue(this.value);

  /// The priority being wrapped.
  final EventPriority value;

  /// Numeric rank of [value], used by the ordering operators: higher sorts
  /// first.
  int get weight {
    switch (value) {
      case EventPriority.low:
        return 0;
      case EventPriority.normal:
        return 1;
      case EventPriority.high:
        return 2;
      case EventPriority.critical:
        return 3;
    }
  }

  /// Whether this priority sorts strictly before [other].
  bool operator <(EventPriorityValue other) {
    return weight < other.weight;
  }

  /// Whether this priority sorts strictly after [other].
  bool operator >(EventPriorityValue other) {
    return weight > other.weight;
  }

  /// Whether this priority sorts at or before [other].
  bool operator <=(EventPriorityValue other) {
    return weight <= other.weight;
  }

  /// Whether this priority sorts at or after [other].
  bool operator >=(EventPriorityValue other) {
    return weight >= other.weight;
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => 'EventPriorityValue($value)';
}
