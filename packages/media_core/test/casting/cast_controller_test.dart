import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/casting/cast_controller.dart';
import 'package:media_core/casting/cast_device.dart';
import 'package:media_core/casting/cast_media.dart';
import 'package:media_core/casting/cast_transport.dart';
import 'package:media_core/casting/media_cast_backend.dart';

const _tv = CastDevice(id: 'uuid:tv-1', name: 'Living Room TV', backendId: 'fake');
const _other = CastDevice(id: 'uuid:tv-2', name: 'Bedroom TV', backendId: 'fake');
const _media = CastMedia(url: 'https://cdn.example.com/movie.mp4', title: 'Movie');

/// Scriptable backend: the tests decide what each command does.
class _FakeBackend implements MediaCastBackend {
  _FakeBackend();

  final eventSink = StreamController<CastEvent>.broadcast();

  final List<String> calls = <String>[];
  CastPosition? Function(CastDevice device)? positionReader;

  CastPosition nextPosition = const CastPosition(
    position: Duration(seconds: 30),
    duration: Duration(minutes: 10),
    transportState: CastTransportState.playing,
  );

  @override
  String get id => 'fake';

  @override
  Stream<CastEvent> get events => eventSink.stream;

  @override
  List<CastDevice> devices = <CastDevice>[];

  @override
  Future<void> startDiscovery() async => calls.add('startDiscovery');

  @override
  Future<void> dispose() async => calls.add('backendDispose');

  @override
  Future<void> setMedia(CastDevice device, CastMedia media) async {
    calls.add('setMedia:${device.id}');
  }

  @override
  Future<void> play(CastDevice device) async {
    calls.add('play:${device.id}');
  }

  @override
  Future<void> pause(CastDevice device) async {
    calls.add('pause:${device.id}');
  }

  @override
  Future<void> stop(CastDevice device) async {
    calls.add('stop:${device.id}');
  }

  @override
  Future<void> seek(CastDevice device, Duration position) async {
    calls.add('seek:${device.id}:${position.inSeconds}');
  }

  /// Held until the test completes it: a receiver that answers late is exactly
  /// when an unguarded poll ticker stacks requests.
  Completer<void>? positionGate;

  @override
  Future<CastPosition> position(CastDevice device) async {
    calls.add('position:${device.id}');
    final gate = positionGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    return positionReader?.call(device) ?? nextPosition;
  }

  @override
  Future<void> setVolume(CastDevice device, int percent) async {
    calls.add('volume:${device.id}:$percent');
  }

  void found(CastDevice device) {
    devices = [...devices, device];
    eventSink.add(DeviceFound(device));
  }
}

void main() {
  late _FakeBackend backend;
  late CastController controller;

  setUp(() {
    backend = _FakeBackend();
    controller = CastController(backend: backend, positionInterval: Duration.zero);
  });

  tearDown(() async {
    // Awaited: disposal closes the controller's own subscriptions, and letting
    // it race the sink close hides a failure that only happens on the way out.
    await controller.dispose();
    await backend.eventSink.close();
  });

  group('device presence', () {
    test('DeviceFound surfaces in the device list', () async {
      backend.found(_tv);
      await Future<void>.delayed(Duration.zero);

      expect(controller.devices.map((d) => d.id), [_tv.id]);
    });

    test('a re-announced device replaces the old row, not a second one', () async {
      backend
        ..found(_tv)
        ..found(const CastDevice(id: 'uuid:tv-1', name: 'Renamed TV', backendId: 'fake'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.devices, hasLength(1));
      expect(controller.devices.single.name, 'Renamed TV');
    });

    test('DeviceLost ends a session on the vanished device', () async {
      backend.found(_tv);
      await controller.cast(_tv, _media);
      expect(controller.isCasting, isTrue);

      backend.eventSink.add(const DeviceLost('uuid:tv-1'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.isCasting, isFalse);
      expect(controller.device, isNull);
      expect(controller.transportState, CastTransportState.noMedia);
    });
  });

  group('cast session', () {
    test('cast stops the previous device before switching', () async {
      await controller.cast(_tv, _media);
      backend.calls.clear();

      await controller.cast(_other, _media);

      expect(backend.calls, ['stop:${_tv.id}', 'setMedia:${_other.id}', 'play:${_other.id}', 'position:${_other.id}']);
      expect(controller.device!.id, _other.id);
    });

    test('a slow playhead read does not stack one poll per tick', () async {
      final ticking = CastController(backend: backend, positionInterval: const Duration(milliseconds: 50));
      addTearDown(ticking.dispose);

      await ticking.cast(_tv, _media);
      backend.calls.clear();
      backend.positionGate = Completer<void>();

      // Five ticks due while the receiver has not answered the first one.
      await Future<void>.delayed(const Duration(milliseconds: 260));

      expect(
        backend.calls.where((call) => call == 'position:${_tv.id}'),
        hasLength(1),
        reason:
            'a wedged renderer must not accumulate a round trip per tick, '
            'and a late answer must not overwrite a newer reading',
      );

      backend.positionGate!.complete();
      backend.positionGate = null;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        backend.calls.where((call) => call == 'position:${_tv.id}').length,
        lessThanOrEqualTo(3),
        reason: 'polling resumes at its own cadence, not all at once',
      );
    });

    test('a playhead failure marks unknown and keeps the last position', () async {
      await controller.cast(_tv, _media);
      final before = controller.position;
      backend.positionReader = (_) => throw const CastException('timeout');

      await controller.refresh();

      expect(controller.transportState, CastTransportState.unknown);
      expect(controller.position.position, before.position);
    });

    test('seek updates optimistically and commands the receiver', () async {
      await controller.cast(_tv, _media);
      backend.calls.clear();

      await controller.seek(const Duration(minutes: 2));

      expect(controller.position.position, const Duration(minutes: 2));
      expect(backend.calls.first, 'seek:${_tv.id}:120');
    });

    test('commands before a device was picked raise CastException', () async {
      await expectLater(controller.pause(), throwsA(isA<CastException>()));
    });

    test('volume clamps into the protocol range', () async {
      await controller.cast(_tv, _media);
      backend.calls.clear();

      await controller.setVolume(180);

      expect(backend.calls.single, 'volume:${_tv.id}:100');
    });

    test('stopCasting releases the session but keeps the device', () async {
      backend.found(_tv);
      await controller.cast(_tv, _media);

      await controller.stopCasting();

      expect(controller.isCasting, isFalse);
      expect(controller.devices.map((d) => d.id), contains(_tv.id));
      expect(backend.calls, contains('stop:${_tv.id}'));
    });
  });

  group('TransportStateChanged', () {
    test('an event for the active device updates state without a poll', () async {
      await controller.cast(_tv, _media);
      backend.calls.clear();

      backend.eventSink.add(const TransportStateChanged(deviceId: 'uuid:tv-1', state: CastTransportState.paused));
      await Future<void>.delayed(Duration.zero);

      expect(controller.transportState, CastTransportState.paused);
      expect(backend.calls, isEmpty);
    });

    test('an event for another device is ignored', () async {
      await controller.cast(_tv, _media);

      backend.eventSink.add(const TransportStateChanged(deviceId: 'other', state: CastTransportState.paused));
      await Future<void>.delayed(Duration.zero);

      expect(controller.transportState, CastTransportState.playing);
    });
  });
}
