import 'package:clock/clock.dart';

/// Test clock with manually advanced time.
///
/// Wrap test bodies in [run] to make code using `package:clock`
/// deterministic while still reading `clock.now()`.
final class FakeClock {
  /// Creates a clock anchored at [start].
  factory FakeClock.start([DateTime? start]) {
    return FakeClock._(start ?? DateTime.utc(2024));
  }
  FakeClock._(this._now);

  DateTime _now;

  /// Current fake time.
  DateTime get now => _now;

  /// Runs [body] with this clock installed.
  T run<T>(T Function() body) {
    return withClock(Clock(() => now), body);
  }

  /// Runs [body] asynchronously with this clock installed.
  Future<R> runAsync<R>(Future<R> Function() body) {
    return withClock(Clock(() => now), body);
  }

  /// Advances fake time by [duration].
  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  /// Advances fake time to an absolute [time].
  void advanceTo(DateTime time) {
    if (time.isAfter(_now)) {
      _now = time;
    }
  }
}
