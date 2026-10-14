import 'package:media_core/event/event_priority.dart';
import 'package:media_core/event/player_event.dart';
import 'package:media_core/event/player_event_type.dart';

/// Predicate used to decide whether an event should be delivered.
///
/// Filters are intentionally composable and stateless.
abstract interface class EventFilter {
  const EventFilter();

  /// Whether [event] should be delivered to the subscriber.
  bool accepts(PlayerEvent event);
}

/// Accepts every event.
final class AllowAllEventFilter implements EventFilter {
  /// Creates the filter that lets all events through.
  const AllowAllEventFilter();

  @override
  bool accepts(PlayerEvent event) => true;
}

/// Filters by event type.
final class EventTypeFilter implements EventFilter {
  /// Creates a filter that accepts events whose type is in [types].
  const EventTypeFilter(this.types, {this.includeUnknown = true});

  /// Event types considered relevant.
  final Set<PlayerEventType> types;

  /// Whether [PlayerEventType.unknown] also passes even when it is not listed
  /// in [types], so events the consumer has not classified yet are not dropped
  /// silently.
  final bool includeUnknown;

  @override
  bool accepts(PlayerEvent event) {
    if (types.contains(event.type)) {
      return true;
    }

    return includeUnknown && event.type == PlayerEventType.unknown;
  }
}

/// Filters by minimum priority.
final class EventPriorityFilter implements EventFilter {
  /// Creates a filter that accepts events at or above [minimum] priority.
  const EventPriorityFilter(this.minimum);

  /// Lowest priority an event may carry and still pass.
  final EventPriority minimum;

  @override
  bool accepts(PlayerEvent event) {
    return _weight(event.priority) >= _weight(minimum);
  }

  int _weight(EventPriority value) {
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
}

/// Filters events using player/session/source correlation.
final class EventContextFilter implements EventFilter {
  /// Creates a filter that accepts events whose context matches every supplied
  /// id; omitted ids are not part of the match.
  const EventContextFilter({this.playerId, this.sessionId, this.sourceId});

  /// Required player id, or null to ignore the player when matching.
  final Object? playerId;

  /// Required session id, or null to ignore the session when matching.
  final Object? sessionId;

  /// Required source id, or null to ignore the source when matching.
  final Object? sourceId;

  @override
  bool accepts(PlayerEvent event) {
    final context = event.context;

    if (context == null) {
      return false;
    }

    if (playerId != null && context.playerId != playerId) {
      return false;
    }

    if (sessionId != null && context.sessionId != sessionId) {
      return false;
    }

    if (sourceId != null && context.sourceId != sourceId) {
      return false;
    }

    return true;
  }
}

/// Combines multiple filters.
///
/// All configured filters must accept the event.
final class CompositeEventFilter implements EventFilter {
  /// Creates a filter that accepts an event only when every entry in [filters]
  /// accepts it.
  const CompositeEventFilter(this.filters);

  /// The sub-filters that must all agree for an event to pass.
  final List<EventFilter> filters;

  @override
  bool accepts(PlayerEvent event) {
    for (final filter in filters) {
      if (!filter.accepts(event)) {
        return false;
      }
    }

    return true;
  }
}
