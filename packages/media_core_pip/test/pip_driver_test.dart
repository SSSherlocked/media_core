import 'dart:async';

import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_pip/media_core_pip.dart';
import 'package:native_picture_in_picture/native_picture_in_picture_platform_interface.dart';
import 'package:native_picture_in_picture/pip_event.dart';

/// The default mobile backend, driven without a device.
final class _FakeNativePlatform extends NativePictureInPicturePlatform {
  String? initializedUrl;
  final StreamController<PipEvent> events = StreamController<PipEvent>.broadcast();

  @override
  Future<bool> isPipSupported() async => true;

  @override
  Future<void> initialize(String videoUrl) async => initializedUrl = videoUrl;

  @override
  Future<void> startPiP() async {}

  @override
  Future<void> stopPiP() async {}

  @override
  Future<bool> isPipActive() async => false;

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<Duration> getPosition() async => Duration.zero;

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> setAutoPipEnabled(bool enabled) async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<PipEvent> get onPipEvent => events.stream;
}

final class _FakePipWindow implements PipWindow {
  Rect bounds = const Rect.fromLTWH(100, 100, 1280, 720);
  bool alwaysOnTop = false;
  bool resizable = true;
  bool skipTaskbar = false;
  String title = 'Pure Live';

  int captureCount = 0;
  int restoreCount = 0;
  Size? lastSize;
  Offset? lastPosition;
  double? lastAspectRatio;
  double? pushedAspectRatio;
  int setAspectCount = 0;
  Size? lastMinimumSize;
  int minimumSizeCalls = 0;
  Object? minimumSizeError;
  bool? lastAlwaysOnTop;
  bool? lastResizable;

  @override
  Future<PipWindowSnapshot> capture() async {
    captureCount++;
    return PipWindowSnapshot(
      bounds: bounds,
      alwaysOnTop: alwaysOnTop,
      resizable: resizable,
      skipTaskbar: skipTaskbar,
      title: title,
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
    lastSize = size;
    lastPosition = position;
    lastAspectRatio = aspectRatio;
    lastAlwaysOnTop = alwaysOnTop;
    lastResizable = resizable;
  }

  @override
  Future<void> restore(PipWindowSnapshot snapshot) async {
    restoreCount++;
  }

  @override
  Future<void> setAspectRatio(double aspectRatio) async {
    pushedAspectRatio = aspectRatio;
    setAspectCount++;
  }

  @override
  Future<void> setAlwaysOnTop({required bool value}) async {
    alwaysOnTop = value;
  }

  @override
  Future<void> setMinimumSize(Size size) async {
    lastMinimumSize = size;
    minimumSizeCalls++;
    final error = minimumSizeError;
    if (error != null) {
      // Rethrow the injected object itself: the seam holds an `Object?` so a
      // test can script any failure a real backend produces, and `isA<...>`
      // assertions still match on its exact type.
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  Future<void> startDragging() async {}
}

final class _FakeSystemPip implements SystemPip {
  bool available = true;
  SystemPipStatus enableResult = SystemPipStatus.enabled;
  Object? enableError;

  int enableCount = 0;
  int disposeCount = 0;
  int? lastWidth;
  int? lastHeight;
  SystemPipSourceRect? lastSourceRect;
  SystemPipMedia? lastMedia;

  final StreamController<SystemPipStatus> _statusController = StreamController<SystemPipStatus>.broadcast();

  void emitStatus(SystemPipStatus status) => _statusController.add(status);

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<SystemPipStatus> get status async => SystemPipStatus.disabled;

  @override
  Stream<SystemPipStatus> get statusStream => _statusController.stream;

  @override
  Future<SystemPipStatus> enable({
    required int width,
    required int height,
    SystemPipSourceRect? sourceRect,
    SystemPipTrigger trigger = SystemPipTrigger.immediate,
    SystemPipMedia? media,
  }) async {
    enableCount++;
    lastWidth = width;
    lastHeight = height;
    lastSourceRect = sourceRect;
    lastMedia = media;
    final error = enableError;
    if (error != null) {
      // Same seam as above: the configured object is rethrown unchanged so the
      // driver's caller sees exactly the failure the test injected.
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return enableResult;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    await _statusController.close();
  }
}

PlayerId _player() => PlayerId('player_pip');

void main() {
  group('PipDriver on desktop', () {
    late _FakePipWindow window;
    late PipDriver driver;

    setUp(() {
      window = _FakePipWindow();
      driver = PipDriver(platform: PipPlatform.desktop, desktopWindow: window);
    });

    tearDown(() => driver.dispose());

    test('shrinks the window and locks it to the video shape', () async {
      await driver.initialize();
      driver.onVideoSize(1920, 1080);

      await driver.apply(_player(), PresentationRequest.pip());

      expect(window.captureCount, 1);
      expect(window.lastAlwaysOnTop, isTrue);
      expect(window.lastResizable, isTrue);
      expect(window.lastAspectRatio, closeTo(16 / 9, 0.001));
      // Landscape video: wide window, height derived from the ratio.
      expect(window.lastSize, const Size(320, 180));
      expect(driver.isPip, isTrue);
    });

    test('sizes a portrait stream with a tall window', () async {
      await driver.initialize();
      driver.onVideoSize(1080, 1920);

      await driver.apply(_player(), PresentationRequest.pip());

      expect(window.lastSize, const Size(180, 320));
      expect(window.lastAspectRatio, closeTo(1080 / 1920, 0.001));
    });

    test('a failing compact minimum never aborts the entry', () async {
      window.minimumSizeError = StateError('this backend has no minimum size');
      await driver.initialize();
      driver.onVideoSize(1920, 1080);

      await driver.apply(_player(), PresentationRequest.pip());

      // By the time the minimum is applied the window has already shrunk, so a
      // throw here must not skip the state change: a host that never hears
      // "PiP started" keeps rendering its previous layout inside the small
      // window.
      expect(window.lastMinimumSize, const Size(140, 90));
      expect(driver.isPip, isTrue);
    });

    test('never locks the shape when the host unlocks it', () async {
      driver.config = PipConfig.defaults.copyWith(lockAspectRatio: false);
      await driver.initialize();
      driver.onVideoSize(1920, 1080);

      await driver.apply(_player(), PresentationRequest.pip());

      // A ratio handed to the window is what starts the desktop post-resize
      // shape snap, and that snap is what stops the viewer from changing the
      // height on its own. Unlocked means the window never receives one.
      expect(window.lastAspectRatio, isNull);
      expect(window.lastSize, const Size(320, 180));
    });

    test('applies the configured compact minimum to the window', () async {
      driver.config = PipConfig.defaults.copyWith(minWidth: 120, minHeight: 68);
      await driver.initialize();
      driver.onVideoSize(1920, 1080);

      await driver.apply(_player(), PresentationRequest.pip());

      // The floor belongs to the viewer's setting. Before this the two config
      // fields were never read by anything, so every backend applied whatever
      // floor it happened to have.
      expect(window.lastMinimumSize, const Size(120, 68));
    });

    test('re-shapes the open window when the stream changes orientation', () async {
      await driver.initialize();
      driver.onVideoSize(1920, 1080);
      await driver.apply(_player(), PresentationRequest.pip());

      expect(window.pushedAspectRatio, isNull);

      // A portrait stream that only reports its size after the first frame, or
      // a room that switches shape mid-play: the window must follow it, or the
      // old shape stays and the picture arrives with black bars.
      driver.onVideoSize(1080, 1920);
      await Future<void>.delayed(Duration.zero);

      expect(window.pushedAspectRatio, closeTo(1080 / 1920, 0.001));
    });

    test('leaves the window shape alone while PiP is closed', () async {
      await driver.initialize();
      driver.onVideoSize(1080, 1920);

      expect(window.setAspectCount, 0);
    });

    test('never re-shapes a window the host unlocked', () async {
      final unlocked = PipDriver(
        platform: PipPlatform.desktop,
        desktopWindow: window,
        config: PipConfig.defaults.copyWith(lockAspectRatio: false),
      );
      addTearDown(unlocked.dispose);

      await unlocked.initialize();
      unlocked.onVideoSize(1920, 1080);
      await unlocked.apply(_player(), PresentationRequest.pip());
      unlocked.onVideoSize(1080, 1920);
      await Future<void>.delayed(Duration.zero);

      expect(window.setAspectCount, 0);
    });

    test('can leave the window unlocked for a fixed-shape small window', () async {
      final unlocked = PipDriver(
        platform: PipPlatform.desktop,
        desktopWindow: window,
        config: PipConfig.defaults.copyWith(lockAspectRatio: false),
      );
      addTearDown(unlocked.dispose);

      await unlocked.initialize();
      unlocked.onVideoSize(1080, 1920);
      await unlocked.apply(_player(), PresentationRequest.pip());

      expect(window.lastAspectRatio, isNull, reason: 'the video is fitted into the window instead of shaping it');
    });

    test('falls back to the configured size when the video size is unknown', () async {
      await driver.initialize();

      await driver.apply(_player(), PresentationRequest.pip());

      expect(window.lastSize, const Size(320, 180));
      expect(window.lastAspectRatio, isNull);
    });

    test('snaps into the bottom-right corner of the previous bounds', () async {
      await driver.initialize();
      driver.onVideoSize(1920, 1080);

      await driver.apply(_player(), PresentationRequest.pip());

      // 100 + 1280 - 320 - 16 = 1044, 100 + 720 - 180 - 16 = 624
      expect(window.lastPosition, const Offset(1044, 624));
    });

    test('leaving PiP restores the captured window state', () async {
      await driver.initialize();
      await driver.apply(_player(), PresentationRequest.pip());

      await driver.apply(_player(), PresentationRequest.normal());

      expect(window.restoreCount, 1);
      expect(driver.isPip, isFalse);
    });

    test('does not restore when restoreWindowOnExit is off', () async {
      final custom = PipDriver(
        platform: PipPlatform.desktop,
        desktopWindow: window,
        config: PipConfig.defaults.copyWith(restoreWindowOnExit: false),
      );
      addTearDown(custom.dispose);

      await custom.initialize();
      await custom.apply(_player(), PresentationRequest.pip());
      await custom.apply(_player(), PresentationRequest.normal());

      expect(window.restoreCount, 0);
      expect(custom.isPip, isFalse);
    });

    test('repeating the request does not capture the window twice', () async {
      await driver.initialize();
      await driver.apply(_player(), PresentationRequest.pip());
      await driver.apply(_player(), PresentationRequest.pip());

      expect(window.captureCount, 1);
    });

    test('refuses modes another driver owns', () async {
      await driver.initialize();

      await expectLater(driver.apply(_player(), PresentationRequest.fullscreen()), throwsA(isA<UnsupportedError>()));
      await expectLater(
        driver.apply(_player(), PresentationRequest.windowFullscreen()),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(driver.apply(_player(), PresentationRequest.floating()), throwsA(isA<UnsupportedError>()));
    });

    test('reports a stable state stream', () async {
      await driver.initialize();
      final reported = <bool>[];
      driver.onPipChanged.listen(reported.add);

      await driver.apply(_player(), PresentationRequest.pip());
      await driver.apply(_player(), PresentationRequest.normal());
      // The state stream delivers asynchronously.
      await Future<void>.delayed(Duration.zero);

      expect(reported, <bool>[true, false]);
    });
  });

  group('PipDriver on mobile', () {
    late _FakeSystemPip systemPip;
    late PipDriver driver;

    setUp(() {
      systemPip = _FakeSystemPip();
      driver = PipDriver(platform: PipPlatform.mobile, systemPip: systemPip);
    });

    tearDown(() => driver.dispose());

    test('requests the platform with the video size and the source hint', () async {
      await driver.initialize();
      driver
        ..onVideoSize(1280, 720)
        ..videoRect = const Rect.fromLTWH(10, 20, 640, 360);

      await driver.apply(_player(), PresentationRequest.pip());

      expect(systemPip.enableCount, 1);
      expect(systemPip.lastWidth, 1280);
      expect(systemPip.lastHeight, 720);
      expect(systemPip.lastSourceRect?.width, 640);
      expect(driver.isPip, isTrue);
    });

    test('omits the source hint when the feature is configured off', () async {
      final custom = PipDriver(
        platform: PipPlatform.mobile,
        systemPip: systemPip,
        config: PipConfig.defaults.copyWith(requestSourceRectHint: false),
      );
      addTearDown(custom.dispose);

      await custom.initialize();
      custom
        ..onVideoSize(1280, 720)
        ..videoRect = const Rect.fromLTWH(10, 20, 640, 360);

      await custom.apply(_player(), PresentationRequest.pip());

      expect(systemPip.lastSourceRect, isNull);
    });

    test('refuses PiP before a video size is known', () async {
      await driver.initialize();

      await expectLater(driver.apply(_player(), PresentationRequest.pip()), throwsA(isA<StateError>()));
      expect(systemPip.enableCount, 0);
    });

    test('refuses PiP when the device cannot present it', () async {
      systemPip.available = false;
      await driver.initialize();
      driver.onVideoSize(1280, 720);

      await expectLater(driver.apply(_player(), PresentationRequest.pip()), throwsA(isA<UnsupportedError>()));
      expect(driver.isPip, isFalse);
    });

    test('refuses PiP when the platform answers unavailable', () async {
      systemPip.enableResult = SystemPipStatus.unavailable;
      await driver.initialize();
      driver.onVideoSize(1280, 720);

      await expectLater(driver.apply(_player(), PresentationRequest.pip()), throwsA(isA<UnsupportedError>()));
      expect(driver.isPip, isFalse);
    });

    test('a system-initiated exit flips the reported state', () async {
      await driver.initialize();
      driver.onVideoSize(1280, 720);
      final reported = <bool>[];
      driver.onPipChanged.listen(reported.add);

      await driver.apply(_player(), PresentationRequest.pip());
      systemPip.emitStatus(SystemPipStatus.disabled);
      await Future<void>.delayed(Duration.zero);

      expect(driver.isPip, isFalse);
      expect(reported, <bool>[true, false]);
    });

    test('a handoff resolver is asked and its media reaches enable', () async {
      final withResolver = PipDriver(
        platform: PipPlatform.mobile,
        systemPip: systemPip,
        pipMediaResolver: (_) async => const SystemPipMedia(url: 'https://host/v.mp4', position: Duration(seconds: 12)),
      );
      addTearDown(withResolver.dispose);

      await withResolver.initialize();
      withResolver.onVideoSize(1280, 720);
      await withResolver.apply(_player(), PresentationRequest.pip());

      expect(systemPip.lastMedia?.url, 'https://host/v.mp4');
      expect(systemPip.lastMedia?.position, const Duration(seconds: 12));
      expect(withResolver.isPip, isTrue);
    });

    test('an unhandoffable source refuses the transition before the platform is asked', () async {
      final withoutMedia = PipDriver(
        platform: PipPlatform.mobile,
        systemPip: systemPip,
        pipMediaResolver: (_) async => null,
      );
      addTearDown(withoutMedia.dispose);

      await withoutMedia.initialize();
      withoutMedia.onVideoSize(1280, 720);

      await expectLater(withoutMedia.apply(_player(), PresentationRequest.pip()), throwsA(isA<UnsupportedError>()));
      expect(systemPip.enableCount, 0);
      expect(withoutMedia.isPip, isFalse);
    });

    test('the handoff return fires when the system window is gone', () async {
      // The default mobile backend is NativePipSystemPip: drive it through a
      // fake platform so the full chain (resolver -> enable -> didStop ->
      // host callback) runs the way a device would.
      final platform = _FakeNativePlatform();
      NativePictureInPicturePlatform.instance = platform;
      addTearDown(platform.events.close);

      final returns = <PlayerId>[];
      final handoff = PipDriver(
        platform: PipPlatform.mobile,
        pipMediaResolver: (_) async => const SystemPipMedia(url: 'https://host/v.mp4', position: Duration(seconds: 5)),
        onHandoffReturn: (playerId) async => returns.add(playerId),
      );
      addTearDown(handoff.dispose);

      await handoff.initialize();
      handoff.onVideoSize(1280, 720);
      final playerId = _player();
      await handoff.apply(playerId, PresentationRequest.pip());

      expect(handoff.isPip, isTrue);
      expect(platform.initializedUrl, 'https://host/v.mp4');
      expect(returns, isEmpty);

      platform.events.add(PipEvent.didStop);
      await Future<void>.delayed(Duration.zero);

      expect(handoff.isPip, isFalse);
      expect(returns, <PlayerId>[playerId]);
    });

    test('normal cannot exit the system window and does not claim it did', () async {
      await driver.initialize();
      driver.onVideoSize(1280, 720);
      await driver.apply(_player(), PresentationRequest.pip());

      await driver.apply(_player(), PresentationRequest.normal());

      expect(driver.isPip, isTrue);
      expect(systemPip.disposeCount, 0);
    });
  });

  group('PipDriver on an unsupported platform', () {
    test('is unavailable and refuses to enter', () async {
      final driver = PipDriver(platform: PipPlatform.unsupported);
      addTearDown(driver.dispose);

      await driver.initialize();

      expect(await driver.isAvailable, isFalse);
      await expectLater(driver.apply(_player(), PresentationRequest.pip()), throwsA(isA<UnsupportedError>()));
    });
  });

  group('PipDriver lifecycle hooks', () {
    test('fires the four hooks around a desktop enter and exit, in order', () async {
      final window = _FakePipWindow();
      final phases = <PresentationLifecyclePhase>[];
      final events = <PresentationLifecycleEvent>[];
      PresentationLifecycleHook record(PresentationLifecyclePhase phase) {
        return (PresentationLifecycleEvent event) async {
          phases.add(phase);
          events.add(event);
        };
      }

      final driver = PipDriver(
        platform: PipPlatform.desktop,
        desktopWindow: window,
        lifecycleHooks: PresentationLifecycleHooks(
          beforeEnter: record(PresentationLifecyclePhase.beforeEnter),
          afterEnter: record(PresentationLifecyclePhase.afterEnter),
          beforeExit: record(PresentationLifecyclePhase.beforeExit),
          afterExit: record(PresentationLifecyclePhase.afterExit),
        ),
      );
      addTearDown(driver.dispose);
      await driver.initialize();
      driver.onVideoSize(1920, 1080);

      final player = _player();
      await driver.apply(player, PresentationRequest.pip());

      expect(phases, <PresentationLifecyclePhase>[
        PresentationLifecyclePhase.beforeEnter,
        PresentationLifecyclePhase.afterEnter,
      ]);
      expect(driver.isPip, isTrue);

      await driver.apply(player, PresentationRequest.normal());

      expect(phases, <PresentationLifecyclePhase>[
        PresentationLifecyclePhase.beforeEnter,
        PresentationLifecyclePhase.afterEnter,
        PresentationLifecyclePhase.beforeExit,
        PresentationLifecyclePhase.afterExit,
      ]);
      expect(driver.isPip, isFalse);
      expect(events.every((event) => event.mode == PresentationMode.pip), isTrue);
      expect(events.every((event) => event.playerId == player), isTrue);
    });

    test('repeating the request fires nothing again', () async {
      final phases = <PresentationLifecyclePhase>[];
      PresentationLifecycleHook record(PresentationLifecyclePhase phase) {
        return (event) async => phases.add(phase);
      }

      final driver = PipDriver(
        platform: PipPlatform.desktop,
        desktopWindow: _FakePipWindow(),
        lifecycleHooks: PresentationLifecycleHooks(
          beforeEnter: record(PresentationLifecyclePhase.beforeEnter),
          afterEnter: record(PresentationLifecyclePhase.afterEnter),
          beforeExit: record(PresentationLifecyclePhase.beforeExit),
          afterExit: record(PresentationLifecyclePhase.afterExit),
        ),
      );
      addTearDown(driver.dispose);
      await driver.initialize();
      driver.onVideoSize(1920, 1080);

      await driver.apply(_player(), PresentationRequest.pip());
      await driver.apply(_player(), PresentationRequest.pip());

      expect(phases.length, 2);
    });

    test('a throwing hook never aborts the transition', () async {
      final window = _FakePipWindow();
      final driver = PipDriver(
        platform: PipPlatform.desktop,
        desktopWindow: window,
        lifecycleHooks: PresentationLifecycleHooks(
          beforeEnter: (_) async => throw StateError('hook failed'),
          afterEnter: (_) async => throw StateError('hook failed'),
        ),
      );
      addTearDown(driver.dispose);
      await driver.initialize();
      driver.onVideoSize(1920, 1080);

      await driver.apply(_player(), PresentationRequest.pip());

      expect(window.captureCount, 1);
      expect(driver.isPip, isTrue);
    });

    test('a system-initiated exit fires only afterExit', () async {
      final systemPip = _FakeSystemPip();
      final phases = <PresentationLifecyclePhase>[];
      PresentationLifecycleHook record(PresentationLifecyclePhase phase) {
        return (event) async => phases.add(phase);
      }

      final driver = PipDriver(
        platform: PipPlatform.mobile,
        systemPip: systemPip,
        lifecycleHooks: PresentationLifecycleHooks(
          beforeEnter: record(PresentationLifecyclePhase.beforeEnter),
          afterEnter: record(PresentationLifecyclePhase.afterEnter),
          beforeExit: record(PresentationLifecyclePhase.beforeExit),
          afterExit: record(PresentationLifecyclePhase.afterExit),
        ),
      );
      addTearDown(driver.dispose);
      await driver.initialize();
      driver.onVideoSize(1280, 720);

      await driver.apply(_player(), PresentationRequest.pip());
      // The platform ends the window on its own; the app never asked for an
      // exit, so only the settled after-hook may report it.
      systemPip.emitStatus(SystemPipStatus.disabled);
      await Future<void>.delayed(Duration.zero);

      expect(driver.isPip, isFalse);
      expect(phases, <PresentationLifecyclePhase>[
        PresentationLifecyclePhase.beforeEnter,
        PresentationLifecyclePhase.afterEnter,
        PresentationLifecyclePhase.afterExit,
      ]);
    });
  });
}
