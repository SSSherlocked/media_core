import 'dart:async';

import 'package:flutter/painting.dart' show Rect;
import 'package:media_core_fullscreen/src/fullscreen_window.dart';
import 'package:media_core_win32/media_core_win32.dart';

/// [FullscreenWindow] implemented with direct user32 calls.
///
/// `window_manager`'s `setFullScreen` sits behind a frameless fast path for
/// hosts whose window is created with a hidden title bar: styles and bounds
/// updates are silently skipped while the call still reports success, so a
/// fullscreen transition through it does nothing the user can see. This
/// implementation follows the `fullscreen_window` plugin sequence instead —
/// snapshot the placement, strip the caption/thickframe bits, fill the
/// monitor the window is on with one `SetWindowPos(FRAMECHANGED)`, and on
/// exit restore the snapshot followed by a forced re-layout.
final class Win32FullscreenWindow implements FullscreenWindow {
  static int? _hwnd;

  Win32WindowSnapshot? _snapshot;

  int get _windowHandle {
    if (_hwnd == null || _hwnd == 0) {
      _hwnd = Win32WindowFfi.mainWindowHandle();
    }
    return _hwnd ?? 0;
  }

  @override
  Future<bool> get isFullscreen async => _snapshot != null;

  @override
  Future<Rect> captureBounds() async => Win32WindowFfi.bounds(_windowHandle) ?? Rect.zero;

  @override
  Future<void> setFullscreen({required bool value, Rect? restoreBounds}) async {
    if (value) {
      _snapshot = Win32WindowFfi.capture(_windowHandle);
      Win32WindowFfi.setScreenFullscreen(_windowHandle, fullscreen: true, snapshot: _snapshot);
      return;
    }

    final snapshot = _snapshot;
    _snapshot = null;
    if (snapshot != null) {
      Win32WindowFfi.setScreenFullscreen(_windowHandle, fullscreen: false, snapshot: snapshot);
      return;
    }

    // Fullscreen was never entered through this window: fall back to forcing
    // a re-layout so the caller's [restoreBounds] still lands cleanly.
    Win32WindowFfi.setScreenFullscreen(_windowHandle, fullscreen: false);
    if (restoreBounds != null) {
      Win32WindowFfi.applyBounds(_windowHandle, restoreBounds, topmost: false);
    }
  }
}
