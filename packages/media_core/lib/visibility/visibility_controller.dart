import 'dart:async';

import 'package:clock/clock.dart';
import 'package:media_core/visibility/visibility_event.dart';
import 'package:media_core/visibility/visibility_metrics.dart';
import 'package:media_core/visibility/visibility_observer.dart';
import 'package:media_core/visibility/visibility_snapshot.dart';
import 'package:media_core/visibility/visibility_state.dart';
import 'package:rxdart/rxdart.dart';

/// Controls player visibility state.
final class VisibilityController {
  /// Creates a controller starting from the default hidden state.
  VisibilityController();

  VisibilityState _state = const VisibilityState();

  VisibilityMetrics _metrics = const VisibilityMetrics();

  DateTime? _visibleStarted;

  final BehaviorSubject<VisibilitySnapshot> _snapshotSubject = BehaviorSubject.seeded(VisibilitySnapshot.initial());

  final PublishSubject<VisibilityEvent> _eventSubject = PublishSubject();

  final List<VisibilityObserver> _observers = [];

  /// Snapshot stream, one event per published visibility change.
  Stream<VisibilitySnapshot> get snapshots => _snapshotSubject.stream;

  /// Event stream carrying every visibility transition.
  Stream<VisibilityEvent> get events => _eventSubject.stream;

  /// Latest snapshot.
  VisibilitySnapshot get snapshot => _snapshotSubject.value;

  /// Cumulative visible/hidden time and change count.
  VisibilityMetrics get metrics => _metrics;

  /// Registers [observer] to receive subsequent events.
  void addObserver(VisibilityObserver observer) {
    _observers.add(observer);
  }

  /// Unregisters a previously added [observer].
  void removeObserver(VisibilityObserver observer) {
    _observers.remove(observer);
  }

  /// Updates visibility ratio.
  ///
  /// The ratio is clamped to the 0.0 - 1.0 range before it is applied.
  void update(double ratio) {
    final clamped = ratio.clamp(0.0, 1.0);

    final oldVisible = _state.visible;

    _state = _state.update(clamped);

    final eventType = _resolveEvent(oldVisible, _state.visible);

    _updateMetrics(_state.visible);

    _publish(eventType);
  }

  /// Records whether the player is inside the viewport.
  void setViewport({required bool value}) {
    _state = _state.copyWith(inViewport: value);

    _publish(VisibilityEventType.changed);
  }

  /// Records whether the player is covered by other content.
  void setOccluded({required bool value}) {
    _state = _state.copyWith(occluded: value);

    _publish(VisibilityEventType.changed);
  }

  VisibilityEventType _resolveEvent(bool oldValue, bool newValue) {
    if (!oldValue && newValue) {
      return VisibilityEventType.appeared;
    }

    if (oldValue && !newValue) {
      return VisibilityEventType.disappeared;
    }

    // `appeared`/`disappeared` describe the first/last moment; `visible` and
    // `hidden` are the steady states. Both were public API that nothing could
    // ever emit, so a consumer filtering on them saw nothing at all.
    return newValue ? VisibilityEventType.visible : VisibilityEventType.hidden;
  }

  /// Start of the current hidden stretch, for [VisibilityMetrics.hiddenDuration].
  DateTime? _hiddenStarted;

  void _updateMetrics(bool visible) {
    final now = clock.now();

    if (visible) {
      _visibleStarted ??= now;

      if (_hiddenStarted != null) {
        _metrics = _metrics.copyWith(hiddenDuration: _metrics.hiddenDuration + now.difference(_hiddenStarted!));

        _hiddenStarted = null;
      }
    } else {
      if (_visibleStarted != null) {
        _metrics = _metrics.copyWith(visibleDuration: _metrics.visibleDuration + now.difference(_visibleStarted!));

        _visibleStarted = null;
      }

      // `hiddenDuration` is public and was never written by anyone, so it
      // always read zero while `visibleDuration` accumulated.
      _hiddenStarted ??= now;
    }

    _metrics = _metrics.copyWith(changeCount: _metrics.changeCount + 1);
  }

  void _publish(VisibilityEventType type) {
    final snapshot = VisibilitySnapshot(state: _state, updatedAt: clock.now());

    final event = VisibilityEvent.now(type, _state.visibility);

    _snapshotSubject.add(snapshot);

    _eventSubject.add(event);

    for (final observer in List.of(_observers)) {
      observer.onVisibilityEvent(event);
    }
  }

  /// Closes the streams and drops every registered observer.
  Future<void> dispose() async {
    await _snapshotSubject.close();

    await _eventSubject.close();

    _observers.clear();
  }
}
