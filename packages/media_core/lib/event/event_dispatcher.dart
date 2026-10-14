import 'dart:async';
import 'package:media_core/event/event_filter.dart';
import 'package:media_core/event/event_priority.dart';
import 'package:media_core/event/event_subscription.dart';
import 'package:media_core/event/player_event.dart';
import 'package:media_core/event/player_event_bus.dart' show PlayerEventBus;

/// Dispatches player events to subscribers.
///
/// The dispatcher provides filtering and listener registration but does not
/// own the event source. [PlayerEventBus] supplies the source stream.
final class EventDispatcher {
  /// Creates a dispatcher fed by [source], or an empty stream when none is
  /// supplied so a dispatcher with no event source is still usable.
  EventDispatcher({Stream<PlayerEvent>? source}) : _source = source;

  final Stream<PlayerEvent>? _source;

  final Set<EventSubscription> _subscriptions = <EventSubscription>{};

  bool _disposed = false;

  /// Whether [dispose] has run and further subscriptions are rejected.
  bool get isDisposed => _disposed;

  /// Subscribes to all events accepted by [filter].
  EventSubscription subscribe(
    void Function(PlayerEvent event) listener, {
    EventFilter? filter,
    EventPriority? minimumPriority,
  }) {
    _ensureNotDisposed();

    final effectiveFilter = _combineFilters(filter, minimumPriority);

    final source = _source ?? const Stream.empty();

    final result = EventSubscription(
      subscription: source
          .where(effectiveFilter.accepts)
          .listen(listener, onError: (Object error, StackTrace stackTrace) {}),
      filter: effectiveFilter,
      onCancelled: _remove,
    );

    _subscriptions.add(result);

    return result;
  }

  /// Subscribes to a stream and automatically cancels after the first event.
  EventSubscription subscribeOnce(
    void Function(PlayerEvent event) listener, {
    EventFilter? filter,
    EventPriority? minimumPriority,
  }) {
    _ensureNotDisposed();

    final effectiveFilter = _combineFilters(filter, minimumPriority);

    final source = _source ?? const Stream.empty();

    late EventSubscription result;

    final subscription = source.where(effectiveFilter.accepts).listen((event) async {
      listener(event);
      await result.cancel();
    });

    result = EventSubscription(subscription: subscription, filter: effectiveFilter, once: true, onCancelled: _remove);

    _subscriptions.add(result);

    return result;
  }

  /// Dispatches an event directly to a listener.
  ///
  /// This is useful when an event needs to pass through dispatcher filtering
  /// without creating a long-lived stream subscription.
  bool dispatchTo(PlayerEvent event, void Function(PlayerEvent event) listener, {EventFilter? filter}) {
    _ensureNotDisposed();

    final effectiveFilter = filter ?? const AllowAllEventFilter();

    if (!effectiveFilter.accepts(event)) {
      return false;
    }

    listener(event);
    return true;
  }

  /// Cancels one subscription.
  Future<void> unsubscribe(EventSubscription subscription) async {
    _ensureNotDisposed();

    await subscription.cancel();
  }

  /// Cancels every registered subscription.
  Future<void> cancelAll() async {
    if (_disposed) {
      return;
    }

    final subscriptions = List<EventSubscription>.from(_subscriptions);

    _subscriptions.clear();

    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  /// Cancels every registered subscription and rejects further use.
  ///
  /// Idempotent: a second call is a no-op once already disposed.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    final subscriptions = List<EventSubscription>.from(_subscriptions);

    _subscriptions.clear();

    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  /// Drops a subscription that cancelled itself.
  ///
  /// Registered with every subscription so a one-shot that fires — or any
  /// subscription cancelled by its owner — stops being tracked here instead of
  /// staying in the registry as a dead entry.
  void _remove(EventSubscription subscription) {
    _subscriptions.remove(subscription);
  }

  EventFilter _combineFilters(EventFilter? filter, EventPriority? minimumPriority) {
    if (filter == null && minimumPriority == null) {
      return const AllowAllEventFilter();
    }

    if (filter != null && minimumPriority == null) {
      return filter;
    }

    if (filter == null && minimumPriority != null) {
      return EventPriorityFilter(minimumPriority);
    }

    return CompositeEventFilter(<EventFilter>[filter!, EventPriorityFilter(minimumPriority!)]);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('EventDispatcher has been disposed.');
    }
  }
}
