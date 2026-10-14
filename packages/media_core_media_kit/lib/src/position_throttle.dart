import 'dart:async';

/// Coalesces a high-rate position source into UI-paced emissions.
///
/// libmpv reports `time-pos` as a property change on **every displayed frame**,
/// so a 60 fps video hands the adapter 60 position events per second. Each one
/// would otherwise rebuild the transport state and repaint every listener -
/// tens of times a second, per player, on the UI thread. The other backends in
/// this family do not have that problem because they poll (fvp reads the engine
/// position on a 500 ms timer); this brings the event-driven one to the same
/// shape without making the UI wait for information it already has.
///
/// Two rules keep it honest:
///
/// - **leading edge**: while the gap is open a tick is emitted immediately, so
///   the start of playback and every seek show up with no added latency;
/// - **nothing dropped**: a tick that arrives inside the gap is remembered and
///   emitted when the gap closes, so a stream that stops reporting still ends up
///   showing its true final position.
///
/// A position that moves further than the gap can explain (a seek, a loop
/// restart, a discontinuity) is emitted at once: dragging the timeline must
/// move the bar now, not one interval later.
final class PositionThrottle {
  /// Creates a throttle that emits at most once per [interval].
  PositionThrottle({this.interval = const Duration(milliseconds: 250)});

  /// The UI cadence the position stream is reduced to.
  final Duration interval;

  Timer? _gap;
  Duration? _lastEmitted;
  Duration? _pending;
  void Function(Duration value)? _emit;

  /// Reports a position tick from the engine.
  ///
  /// [emit] publishes a value the listeners should see; it is retained so the
  /// trailing edge can fire after the caller's own statement has returned.
  void report(Duration position, void Function(Duration value) emit) {
    _emit = emit;
    _pending = position;

    final last = _lastEmitted;
    final jumped = last == null || (position - last).abs() > interval * 4;

    if (_gap != null && !jumped) {
      return;
    }

    _flush();
  }

  /// Forgets the gap and the last value.
  ///
  /// Called when a source is (re)opened: the new video's position has no
  /// relationship to the last one reported, and its first tick must reach the
  /// UI immediately.
  void reset() {
    _gap?.cancel();
    _gap = null;
    _lastEmitted = null;
    _pending = null;
  }

  /// Cancels the pending gap. The throttle must not be used afterwards.
  void dispose() {
    reset();
    _emit = null;
  }

  void _flush() {
    final value = _pending;
    final emit = _emit;
    if (value == null || emit == null) {
      return;
    }

    _pending = null;
    _lastEmitted = value;
    _gap?.cancel();
    _gap = Timer(interval, _closeGap);

    emit(value);
  }

  void _closeGap() {
    _gap = null;
    if (_pending != null) {
      _flush();
    }
  }
}
