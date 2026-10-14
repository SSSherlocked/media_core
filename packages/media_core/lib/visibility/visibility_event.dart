import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';

/// Visibility event types.
enum VisibilityEventType {
  /// The player just became visible.
  appeared,

  /// The player just stopped being visible.
  disappeared,

  /// The player is visible.
  visible,

  /// The player is hidden.
  hidden,

  /// A visibility input changed without an appearance transition.
  changed,
}

/// Visibility event.
final class VisibilityEvent extends Equatable {
  /// Creates an event from explicit values.
  const VisibilityEvent({required this.type, required this.visibility, this.timestamp});

  /// Creates an event for [type] stamped with the current time.
  factory VisibilityEvent.now(VisibilityEventType type, double visibility) {
    return VisibilityEvent(type: type, visibility: visibility, timestamp: clock.now());
  }

  /// Which transition this event reports.
  final VisibilityEventType type;

  /// Value from 0.0 to 1.0.
  final double visibility;

  /// When the event was emitted; null for hand-built events.
  final DateTime? timestamp;

  @override
  List<Object?> get props => [type, visibility, timestamp];
}
