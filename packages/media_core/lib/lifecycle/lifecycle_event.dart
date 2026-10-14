import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';

/// Lifecycle events.
enum LifecycleEventType {
  /// The player object was constructed.
  created,

  /// Its backend engine was initialized.
  initialized,

  /// Bound to a foreground surface and ready to play.
  activated,

  /// Playback was paused while the player stays active.
  paused,

  /// Paused playback was resumed.
  resumed,

  /// Released from the surface (for example, backgrounded); playback stops.
  inactive,

  /// Detached from its resources ahead of disposal.
  detached,

  /// Disposal has begun; the player is winding down.
  disposing,

  /// Fully disposed; no further transitions are recorded.
  disposed,
}

/// Lifecycle event.
final class LifecycleEvent extends Equatable {
  /// Creates an event for [type], optionally stamped with [timestamp].
  const LifecycleEvent({required this.type, this.timestamp});

  /// Creates an event for [type] stamped with the current clock time.
  factory LifecycleEvent.now(LifecycleEventType type) {
    return LifecycleEvent(type: type, timestamp: clock.now());
  }

  /// Which lifecycle transition this event reports.
  final LifecycleEventType type;

  /// When the transition happened, or `null` when the caller left it unset.
  final DateTime? timestamp;

  @override
  List<Object?> get props => [type, timestamp];
}
