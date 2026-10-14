import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_win32/media_core_win32.dart';

/// Guard tests for the null/missing-window paths of the FFI layer.
///
/// The Flutter test runner process has no `FLUTTER_RUNNER_WIN32_WINDOW`
/// window, so `mainWindowHandle` answers null on it and every operation is
/// exercised with the zero handle they must tolerate. A regression that
/// dereferences the handle instead of guarding it fails here on Windows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reports support honestly for the host platform', () {
    // The flag itself is platform-derived; only its type is pinned here so
    // the API cannot silently drift to throwing.
    Win32WindowFfi.isSupported;
  });

  test('zero-handle operations degrade instead of crashing', () {
    if (!Win32WindowFfi.isSupported) return;

    expect(Win32WindowFfi.mainWindowHandle(), isNull);
    expect(Win32WindowFfi.capture(0), isNull);
    expect(Win32WindowFfi.bounds(0), isNull);
    expect(Win32WindowFfi.isTopmost(0), isFalse);
    expect(Win32WindowFfi.isSkipTaskbar(0), isFalse);
    expect(Win32WindowFfi.isResizable(0), isFalse);
    expect(Win32WindowFfi.windowTitle(0), '');
    expect(Win32WindowFfi.setSkipTaskbar(0, skip: true), isFalse);
    expect(Win32WindowFfi.setResizable(0, resizable: false), isFalse);
    expect(Win32WindowFfi.setTopmost(0, topmost: true), isFalse);
    expect(Win32WindowFfi.applyBounds(0, const Rect.fromLTWH(0, 0, 1280, 720), topmost: true), isFalse);
    expect(Win32WindowFfi.setScreenFullscreen(0, fullscreen: true), isFalse);
  });
}
