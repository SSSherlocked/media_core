import 'dart:async';
import 'package:media_core/event/event_filter.dart';
import 'package:media_core/event/player_event.dart';

/// Represents one active event subscription.
///
/// A subscription owns only delivery configuration. The event bus remains
/// responsible for event transport.
final class EventSubscription {
  /// Wraps a live stream [subscription] with the [filter] that produced it and
  /// an optional [onCancelled] callback the owner uses to drop it from its
  /// registry.
  EventSubscription({
    required StreamSubscription<PlayerEvent> subscription,
    EventFilter? filter,
    this.once = false,
    void Function(EventSubscription subscription)? onCancelled,
  }) : _subscription = subscription,
       _onCancelled = onCancelled,
       filter = filter ?? const AllowAllEventFilter();

  final StreamSubscription<PlayerEvent> _subscription;

  /// Notified once when this subscription is cancelled.
  ///
  /// A one-shot subscription cancels itself from inside a listener, so the
  /// owner cannot learn about it any other way and would keep a dead entry in
  /// its registry forever.
  final void Function(EventSubscription subscription)? _onCancelled;

  /// Filter that gated delivery to this subscription, kept so the owner can
  /// inspect what was subscribed to.
  final EventFilter filter;

  /// Whether this subscription removes itself after the first matching event.
  final bool once;

  bool _cancelled = false;

  /// Whether [cancel] has already run.
  bool get isCancelled => _cancelled;

  /// Pauses delivery until [resumeSignal], if one is supplied, completes.
  void pause([Future<void>? resumeSignal]) {
    _subscription.pause(resumeSignal);
  }

  /// Resumes delivery previously halted by [pause].
  void resume() {
    _subscription.resume();
  }

  /// Cancels the underlying stream and notifies the owner.
  ///
  /// Idempotent: subsequent calls do nothing and do not re-notify.
  Future<void> cancel() async {
    if (_cancelled) {
      return;
    }

    _cancelled = true;

    _onCancelled?.call(this);

    await _subscription.cancel();
  }
}
