import 'package:flutter/painting.dart' show Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_pip/media_core_pip.dart';

final class _FakeInnerWindow implements PipWindow {
  Rect bounds = const Rect.fromLTWH(0, 0, 1280, 720);
  bool alwaysOnTop = false;
  Object? failOnApply;

  int captureCount = 0;
  int applyCount = 0;
  int restoreCount = 0;
  int dragCount = 0;
  int minimumSizeReleases = 0;
  int minimumSizeRestores = 0;
  Size? lastMinimumSize;
  Size? lastSize;
  Offset? lastPosition;
  double? lastAspectRatio;
  bool? lastAlwaysOnTop;
  bool? lastResizable;
  bool? lastSkipTaskbar;
  PipWindowSnapshot? lastRestored;

  @override
  Future<PipWindowSnapshot> capture() async {
    captureCount++;
    return PipWindowSnapshot(
      bounds: bounds,
      alwaysOnTop: alwaysOnTop,
      resizable: true,
      skipTaskbar: false,
      title: 'Test',
    );
  }

  @override
  Future<void> applySmallWindow({
    required Size size,
    required Offset position,
    required double? aspectRatio,
    required bool alwaysOnTop,
    required bool resizable,
    required bool skipTaskbar,
    required String title,
  }) async {
    final failure = failOnApply;
    if (failure != null) {
      // Rethrown as-is: the seam holds an `Object?` so a test can script any
      // failure a backend might raise, and the `isA<...>` assertion still
      // matches the injected object's own type.
      Error.throwWithStackTrace(failure, StackTrace.current);
    }
    applyCount++;
    bounds = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
    lastSize = size;
    lastPosition = position;
    lastAspectRatio = aspectRatio;
    lastAlwaysOnTop = alwaysOnTop;
    lastResizable = resizable;
    lastSkipTaskbar = skipTaskbar;
  }

  @override
  Future<void> restore(PipWindowSnapshot snapshot) async {
    restoreCount++;
    lastRestored = snapshot;
    bounds = snapshot.bounds;
    alwaysOnTop = snapshot.alwaysOnTop;
  }

  @override
  Future<void> setAlwaysOnTop({required bool value}) async {
    alwaysOnTop = value;
  }

  @override
  Future<void> setMinimumSize(Size size) async {
    lastMinimumSize = size;
    if (size == Size.zero) {
      minimumSizeReleases++;
    } else {
      minimumSizeRestores++;
    }
  }

  @override
  Future<void> setAspectRatio(double aspectRatio) async {
    aspectPushCount++;
  }

  int aspectPushCount = 0;

  @override
  Future<void> startDragging() async {
    dragCount++;
  }
}

void main() {
  group('defaultDesktopPipWindow', () {
    test('picks the Win32 backend on Windows', () {
      expect(defaultDesktopPipWindow(isWindows: true, isMacOS: false, isLinux: false), isA<Win32PipWindow>());
    });

    test('picks the window_manager backend on macOS and Linux', () {
      expect(defaultDesktopPipWindow(isWindows: false, isMacOS: true, isLinux: false), isA<WindowManagerPipWindow>());
      expect(defaultDesktopPipWindow(isWindows: false, isMacOS: false, isLinux: true), isA<WindowManagerPipWindow>());
    });

    test('refuses platforms without a desktop small window', () {
      expect(
        () => defaultDesktopPipWindow(isWindows: false, isMacOS: false, isLinux: false),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('DisplayAwarePipWindow', () {
    late _FakeInnerWindow inner;
    late PipSavedBounds? saved;
    late ({Size size, Offset position, String displayId})? written;

    DisplayAwarePipWindow build() {
      return DisplayAwarePipWindow(
        windowBuilder: () => inner,
        workAreasReader: () async => [const PipWorkArea(id: 'd1', area: Rect.fromLTWH(0, 0, 1920, 1080))],
        readSavedBounds: () => saved,
        writeSavedBounds: (size, position, displayId) =>
            written = (size: size, position: position, displayId: displayId),
        normalMinSize: const Size(960, 540),
      );
    }

    setUp(() {
      inner = _FakeInnerWindow();
      saved = null;
      written = null;
    });

    test('enter releases the minimum size and applies the compact placement', () async {
      final display = build();

      await display.applySmallWindow(
        size: const Size(360, 202.5),
        position: const Offset(1540, 857.5),
        aspectRatio: 16 / 9,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Test',
      );

      expect(display.isCompact, isTrue);
      expect(inner.minimumSizeReleases, 1);
      expect(inner.lastMinimumSize, Size.zero);
      expect(inner.applyCount, 1);
      // Landscape 16:9 caps the long side at 360 and lands bottom-right of
      // the work area with the default margin.
      expect(inner.lastSize, const Size(360, 202.5));
      expect(inner.lastPosition, const Offset(1540, 857.5));
      expect(inner.lastAlwaysOnTop, isFalse);
      expect(inner.lastResizable, isTrue);
      expect(inner.lastSkipTaskbar, isFalse);
      expect(written?.size, const Size(360, 202.5));
      expect(written?.displayId, 'd1');
    });

    test('the requested skip-taskbar flag reaches the backend', () async {
      final display = build();

      await display.applySmallWindow(
        size: const Size(360, 202.5),
        position: const Offset(1540, 857.5),
        aspectRatio: 16 / 9,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: true,
        title: 'Test',
      );

      expect(inner.lastSkipTaskbar, isTrue);
    });

    test('a matching saved placement wins over the default corner', () async {
      saved = const PipSavedBounds(displayId: 'd1', bounds: Rect.fromLTWH(120, 300, 320, 180));
      final display = build();

      await display.applySmallWindow(
        size: const Size(360, 202.5),
        position: Offset.zero,
        aspectRatio: 16 / 9,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Test',
      );

      expect(inner.lastSize, const Size(320, 180));
      expect(inner.lastPosition, const Offset(120, 300));
    });

    test('the remembered size follows the current video aspect — no black bars', () async {
      // A size remembered on a landscape stream…
      saved = const PipSavedBounds(displayId: 'd1', bounds: Rect.fromLTWH(120, 300, 360, 202));
      final display = build();

      // …must not letterbox a portrait stream: the remembered height drives,
      // the width re-derives from the current video's aspect.
      await display.applySmallWindow(
        size: const Size(213.75, 380),
        position: Offset.zero,
        aspectRatio: 9 / 16,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Test',
      );

      // The scale carries as the remembered long side (360); the short side
      // re-derives aspect-exactly instead of distorting the shape.
      expect(inner.lastSize?.width, closeTo(202.5, 0.5));
      expect(inner.lastSize?.height, closeTo(360, 0.5));
      expect(inner.lastSize!.width / inner.lastSize!.height, closeTo(9 / 16, 0.01));
    });

    test('an unlocked shape travels through instead of a substituted ratio', () async {
      final display = build();

      await display.applySmallWindow(
        size: const Size(360, 202.5),
        position: const Offset(1540, 857.5),
        aspectRatio: null,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Test',
      );

      // Replacing the null with the requested size's ratio is exactly what
      // re-locked the window: the backend would start its post-resize shape
      // snap and the viewer could no longer change the height on its own.
      expect(inner.applyCount, 1);
      expect(inner.lastAspectRatio, isNull);
    });

    test('an unlocked shape replays the remembered bounds as they are', () async {
      // A window the viewer squashed while the shape was unlocked…
      saved = const PipSavedBounds(displayId: 'd1', bounds: Rect.fromLTWH(120, 300, 360, 120));
      final display = build();

      await display.applySmallWindow(
        size: const Size(360, 202.5),
        position: Offset.zero,
        aspectRatio: null,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Test',
      );

      // …must come back squashed. Re-deriving the video's 16:9 here would undo
      // the viewer's shape on every entry into the small window.
      expect(inner.lastSize, const Size(360, 120));
    });

    test('a landscape stream re-derives the height from a remembered portrait size', () async {
      saved = const PipSavedBounds(displayId: 'd1', bounds: Rect.fromLTWH(100, 100, 213.75, 380));
      final display = build();

      await display.applySmallWindow(
        size: const Size(360, 202.5),
        position: Offset.zero,
        aspectRatio: 16 / 9,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Test',
      );

      // The scale carries as the remembered long side (380); the height
      // re-derives aspect-exactly.
      expect(inner.lastSize?.width, closeTo(380, 0.5));
      expect(inner.lastSize?.height, closeTo(380 * 9 / 16, 0.5));
      expect(inner.lastSize!.width / inner.lastSize!.height, closeTo(16 / 9, 0.01));
    });

    test('the always-on-top policy pin overrides the request', () async {
      final display = DisplayAwarePipWindow(
        windowBuilder: () => inner,
        workAreasReader: () async => [const PipWorkArea(id: 'd1', area: Rect.fromLTWH(0, 0, 1920, 1080))],
        alwaysOnTop: () => true,
      );

      await display.applySmallWindow(
        size: const Size(360, 202.5),
        position: Offset.zero,
        aspectRatio: 16 / 9,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Test',
      );

      expect(inner.lastAlwaysOnTop, isTrue);
    });

    test('exit restores the normal snapshot and re-applies the minimum size', () async {
      final display = build();
      await display.applySmallWindow(
        size: const Size(360, 202.5),
        position: const Offset(1540, 857.5),
        aspectRatio: 16 / 9,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Test',
      );

      await display.restore(
        PipWindowSnapshot(bounds: inner.bounds, alwaysOnTop: false, resizable: true, skipTaskbar: false, title: 'Test'),
      );

      expect(display.isCompact, isFalse);
      expect(inner.minimumSizeRestores, 1);
      expect(inner.lastMinimumSize, const Size(960, 540));
      expect(inner.restoreCount, 1);
      // The normal snapshot was captured before the shrink: original bounds
      // and the user's own always-on-top state.
      expect(inner.lastRestored?.bounds, const Rect.fromLTWH(0, 0, 1280, 720));
      expect(inner.bounds, const Rect.fromLTWH(0, 0, 1280, 720));
    });

    test('a failing backend is rolled back to normal and the error propagates', () async {
      final display = build();
      inner.failOnApply = StateError('backend refused');

      await expectLater(
        display.applySmallWindow(
          size: const Size(360, 202.5),
          position: Offset.zero,
          aspectRatio: 16 / 9,
          alwaysOnTop: false,
          resizable: true,
          skipTaskbar: false,
          title: 'Test',
        ),
        throwsA(isA<StateError>()),
      );

      expect(display.isCompact, isFalse);
      // The rollback put the minimum size back and replayed the normal
      // snapshot even though the backend failed mid-enter.
      expect(inner.minimumSizeRestores, 1);
      expect(inner.restoreCount, 1);
      expect(inner.bounds, const Rect.fromLTWH(0, 0, 1280, 720));
    });

    test('startDragging only reaches the backend while compact', () async {
      final display = build();

      await display.startDragging();
      expect(inner.dragCount, 0);

      await display.applySmallWindow(
        size: const Size(360, 202.5),
        position: Offset.zero,
        aspectRatio: 16 / 9,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Test',
      );
      await display.startDragging();
      expect(inner.dragCount, 1);
    });

    test('setAlwaysOnTop while compact reaches the backend', () async {
      final display = build();
      await display.applySmallWindow(
        size: const Size(360, 202.5),
        position: Offset.zero,
        aspectRatio: 16 / 9,
        alwaysOnTop: false,
        resizable: true,
        skipTaskbar: false,
        title: 'Test',
      );

      await display.setAlwaysOnTop(value: true);

      expect(inner.alwaysOnTop, isTrue);
    });
  });
}
