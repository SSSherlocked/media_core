import 'package:flutter/painting.dart' show Rect;

/// Desktop window operations system fullscreen needs.
abstract interface class FullscreenWindow {
  /// Whether the window is currently fullscreen.
  Future<bool> get isFullscreen;

  /// Current window bounds.
  Future<Rect> captureBounds();

  /// Enters or leaves system fullscreen, restoring [restoreBounds] on exit.
  Future<void> setFullscreen({required bool value, Rect? restoreBounds});
}
