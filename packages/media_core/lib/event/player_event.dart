import 'package:equatable/equatable.dart';
import 'package:media_core/event/event_context.dart';
import 'package:media_core/event/event_priority.dart';
import 'package:media_core/event/player_event_type.dart';

/// Base type for all events emitted by the media core.
///
/// Events are immutable values. The event bus and dispatcher are responsible
/// for transport only; event subclasses describe what happened.
sealed class PlayerEvent extends Equatable {
  const PlayerEvent({required this.type, this.context, this.priority = EventPriority.normal});

  /// Broad category of this event, used by filters to select what to receive.
  final PlayerEventType type;

  /// Correlation context attached to this event, if any.
  final EventContext? context;

  /// Dispatch priority; events queued in the same cycle are ordered by it.
  final EventPriority priority;

  /// Whether this is a [EventPriority.critical] event that must lead its
  /// dispatch cycle ahead of everything else queued at the same time.
  bool get isCritical => priority == EventPriority.critical;

  /// Whether a correlation [context] is attached.
  bool get hasContext => context != null;

  /// Returns a copy of this event carrying [context].
  PlayerEvent copyWithContext(EventContext? context);

  /// Serialises the event into a string-keyed map for logging or transport.
  Map<String, dynamic> toMap();

  @override
  List<Object?> get props => <Object?>[type, context, priority];
}

/// Generic player event.
///
/// This is useful for event categories that do not yet require a dedicated
/// strongly typed event class.
final class GenericPlayerEvent extends PlayerEvent {
  /// Creates a generic event of [type] carrying an optional untyped [data]
  /// payload.
  const GenericPlayerEvent({required super.type, this.data = const <String, Object?>{}, super.context, super.priority});

  /// Event-specific payload left untyped so categories without a dedicated
  /// event class can still be reported.
  final Map<String, Object?> data;

  @override
  GenericPlayerEvent copyWithContext(EventContext? context) {
    return GenericPlayerEvent(type: type, data: data, context: context, priority: priority);
  }

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{'type': type.name, 'priority': priority.name, 'context': context?.toMap(), 'data': data};
  }

  @override
  List<Object?> get props => <Object?>[...super.props, data];

  @override
  String toString() {
    return 'GenericPlayerEvent('
        'type: $type, '
        'priority: $priority, '
        'data: $data'
        ')';
  }
}

/// Error event.
///
/// Error payload is kept as Object so the event layer does not depend on a
/// particular error hierarchy.
final class PlayerErrorEvent extends PlayerEvent {
  /// Creates an error event wrapping [error] and its optional [stackTrace].
  const PlayerErrorEvent({required this.error, this.stackTrace, super.context, super.priority = EventPriority.high})
    : super(type: PlayerEventType.error);

  /// The thrown object; kept as `Object` so the event layer does not depend on
  /// a particular error hierarchy.
  final Object error;

  /// Stack trace captured at the failure, when the source provided one.
  final StackTrace? stackTrace;

  /// Whether a [stackTrace] was captured alongside [error].
  bool get hasStackTrace => stackTrace != null;

  @override
  PlayerErrorEvent copyWithContext(EventContext? context) {
    return PlayerErrorEvent(error: error, stackTrace: stackTrace, context: context, priority: priority);
  }

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.name,
      'priority': priority.name,
      'context': context?.toMap(),
      'error': error.toString(),
      'stackTrace': stackTrace?.toString(),
    };
  }

  @override
  List<Object?> get props => <Object?>[...super.props, error, stackTrace];

  @override
  String toString() {
    return 'PlayerErrorEvent('
        'error: $error, '
        'stackTrace: $stackTrace'
        ')';
  }
}

/// Lifecycle event.
///
/// This event is intentionally generic and uses a string action so the event
/// layer does not duplicate lifecycle state definitions.
final class PlayerLifecycleEvent extends PlayerEvent {
  /// Creates a lifecycle event describing the [action] taken.
  const PlayerLifecycleEvent({
    required this.action,
    this.data = const <String, Object?>{},
    super.context,
    super.priority = EventPriority.normal,
  }) : super(type: PlayerEventType.lifecycle);

  /// Lifecycle action performed; a string so the event layer does not
  /// duplicate the lifecycle state definitions owned elsewhere.
  final String action;

  /// Extra values describing the action.
  final Map<String, Object?> data;

  @override
  PlayerLifecycleEvent copyWithContext(EventContext? context) {
    return PlayerLifecycleEvent(action: action, data: data, context: context, priority: priority);
  }

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.name,
      'priority': priority.name,
      'context': context?.toMap(),
      'action': action,
      'data': data,
    };
  }

  @override
  List<Object?> get props => <Object?>[...super.props, action, data];

  @override
  String toString() {
    return 'PlayerLifecycleEvent('
        'action: $action, '
        'data: $data'
        ')';
  }
}
