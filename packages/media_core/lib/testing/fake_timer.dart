import 'dart:async';

/// A manually pumped timer for tests.
///
/// The callback is queued and fires only once the accumulated
/// pumped time reaches the configured duration.
final class FakeTimer implements Timer {
  /// Creates a timer that fires [_callback] once [_duration] of pumped time
  /// has accumulated.
  FakeTimer(this._duration, this._callback);

  final Duration _duration;
  final void Function() _callback;

  bool _fired = false;
  bool _canceled = false;
  Duration _elapsed = Duration.zero;
  final List<Duration> _pumps = <Duration>[];

  /// Whether the timer fired.
  bool get fired => _fired;

  /// Number of pumps performed.
  int get pumpCount => _pumps.length;

  /// Elapsed virtual time.
  Duration get elapsed => _elapsed;

  @override
  bool get isActive => !_canceled && !_fired;

  /// Number of times the timer fired.
  @override
  int get tick => _fired ? 1 : 0;

  /// Advances virtual time by [duration], firing the callback when due.
  void pump([Duration duration = Duration.zero]) {
    if (!isActive) {
      return;
    }

    _elapsed += duration;
    _pumps.add(duration);

    if (_elapsed >= _duration) {
      _fired = true;
      _callback();
    }
  }

  /// Fires the timer immediately if still active.
  void fireNow() {
    if (isActive) {
      _fired = true;
      _callback();
    }
  }

  @override
  void cancel() {
    _canceled = true;
  }
}
