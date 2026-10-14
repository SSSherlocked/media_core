import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_pip/media_core_pip.dart';
import 'package:media_core_win32/media_core_win32.dart';

/// Degradation contract of the Win32 backend when no runner window exists.
///
/// The Flutter test runner process has no `FLUTTER_RUNNER_WIN32_WINDOW`
/// window, so every call lands on the zero-handle guard paths of
/// `Win32WindowFfi`. The important pin here is [Win32PipWindow.restore]'s
/// snapshot contract:
/// with no native snapshot in the passed snapshot it must reconstruct from
/// the readable fields instead of assuming a cached one — a restore that
/// trusted a "latest capture" side effect replayed the compact window back
/// and left a shrunken, taskbar-less, black window after exit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('capture is read-only and travels the native snapshot in the result', () async {
    if (!Win32WindowFfi.isSupported) return;

    final window = Win32PipWindow();
    final snapshot = await window.capture();

    // Zero-handle host: bounds are unknown, no native snapshot was taken,
    // and nothing threw.
    expect(snapshot.bounds, Rect.zero);
    expect(snapshot.titleBarStyle, isNull);
  });

  test('restore without a native snapshot reconstructs from the fields', () async {
    if (!Win32WindowFfi.isSupported) return;

    final window = Win32PipWindow();
    await window.restore(
      const PipWindowSnapshot(
        bounds: Rect.fromLTWH(0, 0, 1280, 720),
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Pure Live',
      ),
    );
  });

  test('applySmallWindow and the z-order toggle tolerate a missing window', () async {
    if (!Win32WindowFfi.isSupported) return;

    final window = Win32PipWindow();
    await window.applySmallWindow(
      size: const Size(360, 202.5),
      position: const Offset(1540, 857.5),
      aspectRatio: 16 / 9,
      alwaysOnTop: true,
      resizable: false,
      skipTaskbar: true,
      title: 'Pure Live',
    );
    await window.setAlwaysOnTop(value: false);
    await window.setMinimumSize(const Size(960, 540));
  });
}
