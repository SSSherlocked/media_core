import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_pip/src/native_pip_system_pip.dart';
import 'package:media_core_pip/src/system_pip.dart';
import 'package:native_picture_in_picture/native_picture_in_picture_platform_interface.dart';
import 'package:native_picture_in_picture/pip_event.dart';

/// Scriptable stand-in for the plugin's platform side.
final class _FakePlatform extends NativePictureInPicturePlatform {
  bool supported = true;
  bool active = false;
  Object? throwError;

  final List<String> calls = <String>[];
  String? initializedUrl;
  Duration? seekedTo;
  bool? autoPip;

  final StreamController<PipEvent> events = StreamController<PipEvent>.broadcast();

  void _record(String name) {
    final error = throwError;
    if (error != null) {
      // Rethrown as-is: the seam holds an `Object?` so a test can script the
      // channel error a real platform throws (`UnsupportedError` off-device),
      // and the backend's `catch` still sees that exact object.
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    calls.add(name);
  }

  @override
  Future<bool> isPipSupported() async {
    _record('isPipSupported');
    return supported;
  }

  @override
  Future<void> initialize(String videoUrl) async {
    _record('initialize');
    initializedUrl = videoUrl;
  }

  @override
  Future<void> startPiP() async => _record('startPiP');

  @override
  Future<void> stopPiP() async => _record('stopPiP');

  @override
  Future<bool> isPipActive() async {
    _record('isPipActive');
    return active;
  }

  @override
  Future<void> seekTo(Duration position) async {
    _record('seekTo');
    seekedTo = position;
  }

  @override
  Future<Duration> getPosition() async {
    _record('getPosition');
    return const Duration(seconds: 42);
  }

  @override
  Future<void> play() async => _record('play');

  @override
  Future<void> pause() async => _record('pause');

  @override
  Future<void> setAutoPipEnabled(bool enabled) async {
    _record('setAutoPipEnabled');
    autoPip = enabled;
  }

  @override
  Future<void> dispose() async => _record('dispose');

  @override
  Stream<PipEvent> get onPipEvent => events.stream;
}

void main() {
  late _FakePlatform platform;

  setUp(() {
    platform = _FakePlatform();
    NativePictureInPicturePlatform.instance = platform;
  });

  group('NativePipSystemPip availability', () {
    test('reports the platform answer', () async {
      final pip = NativePipSystemPip();
      expect(await pip.isAvailable, isTrue);

      platform.supported = false;
      expect(await pip.isAvailable, isFalse);
    });

    test('a platform without a channel answers unavailable, not a throw', () async {
      platform.throwError = UnsupportedError('no Android/iOS here');
      final pip = NativePipSystemPip();
      expect(await pip.isAvailable, isFalse);
    });

    test('disposed answers unavailable', () async {
      final pip = NativePipSystemPip();
      await pip.dispose();
      expect(await pip.isAvailable, isFalse);
    });
  });

  group('NativePipSystemPip enable', () {
    test('without a source to replay it refuses rather than opening an empty window', () async {
      final pip = NativePipSystemPip();
      expect(pip.enable(width: 1280, height: 720), throwsA(isA<UnsupportedError>()));
      expect(platform.calls, isEmpty);
    });

    test('hands the url to the native player and resumes at the given position', () async {
      final pip = NativePipSystemPip();
      final status = await pip.enable(
        width: 1280,
        height: 720,
        media: const SystemPipMedia(url: 'https://host/video.mp4', position: Duration(seconds: 30)),
      );

      expect(status, SystemPipStatus.enabled);
      expect(platform.initializedUrl, 'https://host/video.mp4');
      expect(platform.seekedTo, const Duration(seconds: 30));
      expect(platform.calls, containsAllInOrder(<String>['initialize', 'seekTo', 'play', 'startPiP']));
    });

    test('a live source (no position) starts without a seek', () async {
      final pip = NativePipSystemPip();
      await pip.enable(width: 1920, height: 1080, media: const SystemPipMedia(url: 'https://host/live.m3u8'));

      expect(platform.seekedTo, isNull);
      expect(platform.calls, isNot(contains('seekTo')));
    });

    test('a non-positive video size is refused', () async {
      final pip = NativePipSystemPip();
      expect(
        pip.enable(width: 0, height: 720, media: const SystemPipMedia(url: 'https://host/v.mp4')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the onLeaveApp trigger arms auto-PiP and reports automatic', () async {
      final pip = NativePipSystemPip();
      final status = await pip.enable(width: 1280, height: 720, trigger: SystemPipTrigger.onLeaveApp);

      expect(platform.autoPip, isTrue);
      expect(status, SystemPipStatus.automatic);
      // Arming is not playing: nothing was handed to the native player.
      expect(platform.calls, isNot(contains('initialize')));
    });

    test('enable after dispose throws StateError', () async {
      final pip = NativePipSystemPip();
      await pip.dispose();
      expect(pip.enable(width: 1280, height: 720, media: const SystemPipMedia(url: 'x')), throwsA(isA<StateError>()));
    });
  });

  group('NativePipSystemPip status stream', () {
    test('translates the settled plugin events', () async {
      final pip = NativePipSystemPip();
      final seen = <SystemPipStatus>[];
      pip.statusStream.listen(seen.add);

      platform.events.add(PipEvent.didStart);
      platform.events.add(PipEvent.willStop);
      await pumpEventQueue();
      expect(seen, <SystemPipStatus>[SystemPipStatus.enabled]);

      platform.events.add(PipEvent.didStop);
      await pumpEventQueue();
      expect(seen, <SystemPipStatus>[SystemPipStatus.enabled, SystemPipStatus.disabled]);
    });

    test('enable pushes the settled status without waiting for the event channel', () async {
      final pip = NativePipSystemPip();
      final seen = <SystemPipStatus>[];
      pip.statusStream.listen(seen.add);

      await pip.enable(width: 1280, height: 720, media: const SystemPipMedia(url: 'https://host/v.mp4'));
      await pumpEventQueue();
      expect(seen, contains(SystemPipStatus.enabled));
    });

    test('restoreUI ends the handoff once and calls the host back', () async {
      var returns = 0;
      final pip = NativePipSystemPip(onHandoffEnd: () async => returns++);

      await pip.enable(width: 1280, height: 720, media: const SystemPipMedia(url: 'https://host/v.mp4'));
      platform.events.add(PipEvent.restoreUI);
      await pumpEventQueue();
      expect(returns, 1);

      // A trailing didStop for the same window must not hand back twice.
      platform.events.add(PipEvent.didStop);
      await pumpEventQueue();
      expect(returns, 1);
    });

    test('a failing host callback is swallowed, the status still lands', () async {
      final pip = NativePipSystemPip(onHandoffEnd: () async => throw StateError('resume failed'));
      final seen = <SystemPipStatus>[];
      pip.statusStream.listen(seen.add);

      await pip.enable(width: 1280, height: 720, media: const SystemPipMedia(url: 'https://host/v.mp4'));
      platform.events.add(PipEvent.didStop);
      await pumpEventQueue();

      expect(seen, contains(SystemPipStatus.disabled));
      expect(pip, isNotNull);
    });
  });

  group('NativePipSystemPip status', () {
    test('mirrors the platform activity, then the armed handoff', () async {
      final pip = NativePipSystemPip();
      expect(await pip.status, SystemPipStatus.disabled);

      platform.active = true;
      expect(await pip.status, SystemPipStatus.enabled);

      platform.active = false;
      await pip.enable(width: 640, height: 360, trigger: SystemPipTrigger.onLeaveApp);
      expect(await pip.status, SystemPipStatus.automatic);
    });

    test('exposes the handoff player position for the return', () async {
      final pip = NativePipSystemPip();
      expect(await pip.position, const Duration(seconds: 42));
    });
  });

  test('dispose releases the plugin player', () async {
    final pip = NativePipSystemPip();
    await pip.dispose();
    expect(platform.calls, contains('dispose'));
  });
}
