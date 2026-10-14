import 'package:clock/clock.dart';

import 'package:media_core/visibility/visibility_event.dart';
import 'package:media_core/visibility/visibility_observer.dart';

/// Recording [VisibilityObserver] for tests.
final class FakeVisibilityObserver implements VisibilityObserver {
  final List<VisibilityEvent> _events = <VisibilityEvent>[];

  /// Received events in order.
  List<VisibilityEvent> get events => List.unmodifiable(_events);

  /// Number of received events.
  int get count => _events.length;

  /// Latest received event.
  VisibilityEvent? get last => _events.isEmpty ? null : _events.last;

  /// Latest visibility ratio, defaults to zero.
  double get latestRatio => _events.isEmpty ? 0 : _events.last.visibility;

  /// Whether a fully visible event was received.
  bool get sawVisible => _events.any((event) => event.visibility >= 1);

  /// Whether a fully hidden event was received.
  bool get sawHidden => _events.any((event) => event.visibility <= 0);

  @override
  void onVisibilityEvent(VisibilityEvent event) {
    _events.add(event);
  }

  /// Clears recorded events.
  void reset() => _events.clear();
}

/// Builds [VisibilityEvent] values for tests.
final class FakeVisibilityEvents {
  const FakeVisibilityEvents._();

  /// Builds a ratio changed event.
  static VisibilityEvent ratio(double ratio, {DateTime? timestamp}) {
    return VisibilityEvent(type: VisibilityEventType.changed, visibility: ratio, timestamp: timestamp ?? clock.now());
  }

  /// Builds a fully visible event.
  static VisibilityEvent visible({DateTime? timestamp}) {
    return VisibilityEvent(type: VisibilityEventType.visible, visibility: 1, timestamp: timestamp ?? clock.now());
  }

  /// Builds a fully hidden event.
  static VisibilityEvent hidden({DateTime? timestamp}) {
    return VisibilityEvent(type: VisibilityEventType.hidden, visibility: 0, timestamp: timestamp ?? clock.now());
  }
}
