import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_pip/src/overlay_pip.dart';
import 'package:media_core_pip/src/overlay_pip_system_pip.dart';
import 'package:media_core_pip/src/system_pip.dart';
import 'package:pip_kit/pip_kit.dart';

/// Records every call the implementation makes, without a device.
final class _FakeOverlayWindow implements OverlayWindowApi {
  _FakeOverlayWindow({this.permissionGranted = true});

  bool permissionGranted;
  bool active = false;
  bool overlayShown = false;
  int? shownWidth;
  int? shownHeight;
  bool? shownEnableDrag;
  final List<Object?> shared = [];
  final StreamController<Object?> _inbox = StreamController<Object?>.broadcast();

  /// Simulates a message arriving from the overlay engine.
  void emit(Object? event) => _inbox.add(event);

  @override
  Future<bool> isPermissionGranted() async => permissionGranted;

  @override
  Future<bool?> requestPermission() async => permissionGranted;

  @override
  Future<void> showOverlay({
    required int width,
    required int height,
    required bool enableDrag,
    required String title,
  }) async {
    overlayShown = true;
    shownWidth = width;
    shownHeight = height;
    shownEnableDrag = enableDrag;
    active = true;
  }

  @override
  Future<bool> isActive() async => active;

  @override
  Future<bool?> closeOverlay() async {
    final wasActive = active;
    active = false;
    return wasActive;
  }

  @override
  Future<void> shareData(Object data) async => shared.add(data);

  @override
  Stream<Object?> get messages => _inbox.stream;
}

/// Records what reaches pip_kit, without a device.
final class _FakePipKit implements PipKitApi {
  _FakePipKit({this.supported = true, this.enterAccepted = true});

  bool supported;
  bool enterAccepted;
  PipContent? content;
  PipOptions? options;
  final ValueNotifier<bool> open = ValueNotifier<bool>(false);

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> enter({required PipContent content, required PipOptions options}) async {
    this.content = content;
    this.options = options;
    open.value = enterAccepted;
    return enterAccepted;
  }

  @override
  ValueListenable<bool> get isOpen => open;

  @override
  Future<void> disarm() async {
    open.value = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('iOS (pip_kit)', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('enters with the video aspect and autoEnter only for onLeaveApp', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final kit = _FakePipKit();
      final pip = OverlayPipSystemPip(pipKit: kit);

      final status = await pip.enable(width: 1920, height: 1080);

      expect(status, SystemPipStatus.enabled);
      expect(kit.content?.kind, PipContentKind.video);
      expect(kit.options?.aspectRatio, PipAspectRatio.landscape);
      expect(kit.options?.autoEnter, isFalse);

      // The shrink-on-leave trigger arms the system's own path instead of
      // opening the window right away.
      await pip.enable(width: 1080, height: 1920, trigger: SystemPipTrigger.onLeaveApp);
      expect(kit.options?.aspectRatio, PipAspectRatio.portrait);
      expect(kit.options?.autoEnter, isTrue);
    });

    test('reports unavailable when the system refuses', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final pip = OverlayPipSystemPip(pipKit: _FakePipKit(supported: false));

      expect(await pip.isAvailable, isFalse);
      expect(await pip.enable(width: 16, height: 9), SystemPipStatus.unavailable);
    });

    test('reports unavailable when pip_kit declines the entry', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final pip = OverlayPipSystemPip(pipKit: _FakePipKit(enterAccepted: false));

      expect(await pip.enable(width: 1920, height: 1080), SystemPipStatus.unavailable);
    });

    test('a system-initiated close reaches the status stream', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final kit = _FakePipKit();
      final pip = OverlayPipSystemPip(pipKit: kit);
      final seen = <SystemPipStatus>[];
      pip.statusStream.listen(seen.add);

      await pip.enable(width: 1920, height: 1080);
      kit.open.value = false;
      await pumpEventQueue();

      expect(seen, contains(SystemPipStatus.disabled));
    });

    test('never asks for a media payload — the player never leaves the app', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final kit = _FakePipKit();
      final pip = OverlayPipSystemPip(pipKit: kit);

      // No media, no resolver: the entry must still work.
      await expectLater(
        pip.enable(width: 1920, height: 1080),
        completion(SystemPipStatus.enabled),
      );
      expect(kit.content?.kind, PipContentKind.video);
    });
  });

  group('Android (flutter_overlay_window)', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('shows the overlay at the video aspect and shares the source', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final window = _FakeOverlayWindow();
      final pip = OverlayPipSystemPip(overlayWindow: window);

      final status = await pip.enable(
        width: 1920,
        height: 1080,
        media: const SystemPipMedia(url: 'https://example.com/v.mp4', position: Duration(seconds: 5)),
      );

      expect(status, SystemPipStatus.enabled);
      expect(window.overlayShown, isTrue);
      expect(window.shownEnableDrag, isTrue);
      // Physical pixels, shaped like the video.
      expect(window.shownWidth! / window.shownHeight!, closeTo(16 / 9, 0.05));
      final payload = window.shared.whereType<Map<String, Object?>>().firstWhere((m) => m['type'] == 'media');
      expect(payload['url'], 'https://example.com/v.mp4');
      expect(payload['positionMs'], 5000);
    });

    test('refuses the entry without a media payload', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pip = OverlayPipSystemPip(overlayWindow: _FakeOverlayWindow());

      await expectLater(pip.enable(width: 1920, height: 1080), throwsA(isA<UnsupportedError>()));
    });

    test('answers unavailable when the viewer denies the permission', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final window = _FakeOverlayWindow(permissionGranted: false);
      final pip = OverlayPipSystemPip(overlayWindow: window);

      final status = await pip.enable(
        width: 1920,
        height: 1080,
        media: const SystemPipMedia(url: 'https://example.com/v.mp4'),
      );

      expect(status, SystemPipStatus.unavailable);
      expect(window.overlayShown, isFalse);
    });

    test('the overlay closing reaches the status stream and the handback position', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final window = _FakeOverlayWindow();
      final pip = OverlayPipSystemPip(overlayWindow: window);
      final seen = <SystemPipStatus>[];
      pip.statusStream.listen(seen.add);

      await pip.enable(
        width: 1920,
        height: 1080,
        media: const SystemPipMedia(url: 'https://example.com/v.mp4'),
      );
      expect(pip.lastClosedPosition, isNull);

      // The overlay engine reports before tearing itself down.
      window.emit(<String, Object?>{'type': 'close', 'positionMs': 4200});
      await pumpEventQueue();

      expect(seen, contains(SystemPipStatus.disabled));
      expect(pip.lastClosedPosition, const Duration(milliseconds: 4200));
    });

    test('replays the payload when the overlay engine reports ready', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final window = _FakeOverlayWindow();
      final pip = OverlayPipSystemPip(overlayWindow: window);

      await pip.enable(
        width: 1920,
        height: 1080,
        media: const SystemPipMedia(url: 'https://example.com/v.mp4'),
      );
      final sentBefore = window.shared.length;

      // A payload sent during boot arrives before the engine's listener; the
      // handshake must make the app send it again.
      window.emit(<String, Object?>{'type': 'ready'});
      await pumpEventQueue();

      expect(window.shared.length, sentBefore + 1);
    });

    test('ignores messages it does not own', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final window = _FakeOverlayWindow();
      final pip = OverlayPipSystemPip(overlayWindow: window);

      await pip.enable(
        width: 1920,
        height: 1080,
        media: const SystemPipMedia(url: 'https://example.com/v.mp4'),
      );
      final sentBefore = window.shared.length;

      window
        ..emit('not a map')
        ..emit(<String, Object?>{'type': 'nonsense'});
      await pumpEventQueue();

      expect(window.shared.length, sentBefore);
      expect(pip.lastClosedPosition, isNull);
    });
  });

  group('an unsupported platform', () {
    test('answers unavailable without touching either backend', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final window = _FakeOverlayWindow();
      final pip = OverlayPipSystemPip(overlayWindow: window, pipKit: _FakePipKit());

      expect(await pip.isAvailable, isFalse);
      expect(
        await pip.enable(
          width: 1920,
          height: 1080,
          media: const SystemPipMedia(url: 'https://example.com/v.mp4'),
        ),
        SystemPipStatus.unavailable,
      );
      expect(window.overlayShown, isFalse);
    });
  });

  group('a disposed implementation', () {
    test('refuses further work', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final window = _FakeOverlayWindow();
      final pip = OverlayPipSystemPip(overlayWindow: window);
      await pip.enable(
        width: 1920,
        height: 1080,
        media: const SystemPipMedia(url: 'https://example.com/v.mp4'),
      );

      await pip.dispose();

      expect(await pip.isAvailable, isFalse);
      await expectLater(pip.enable(width: 1920, height: 1080), throwsA(isA<StateError>()));
      // Teardown closed the overlay it opened.
      expect(window.active, isFalse);
    });
  });
}
