import 'package:media_core/visibility/visibility_event.dart';

/// Receives visibility changes.
abstract interface class VisibilityObserver {
  /// Called for every visibility event published after registration.
  void onVisibilityEvent(VisibilityEvent event);
}
