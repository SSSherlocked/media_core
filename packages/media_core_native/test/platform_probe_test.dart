import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_native/media_core_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kMediaCoreNativeChannel);

  /// Answers the probe with [payload] (or throws when it is `_fail`).
  void mockProbe(Object? payload) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != kProbeMethod) {
        throw MissingPluginException(call.method);
      }
      if (payload is _Throwing) {
        // Re-throw the fixture's canned failure verbatim to exercise the
        // probe's error path; its static type is Object so it cannot be
        // proven throwable.
        // ignore: only_throw_errors
        throw payload.error;
      }
      return payload;
    });
  }

  tearDown(() => mockProbe(null));

  group('PlatformProbeReport.fromPayload', () {
    test('a payload that is not a map is "nobody probed", not "all no"', () {
      for (final bad in <Object?>[null, 42, 'text', <Object?>[]]) {
        final report = PlatformProbeReport.fromPayload(bad);
        expect(report.isReported, isFalse);
        expect(report.capabilities.reported, isFalse);
      }
    });

    test('an empty map parses to a fully unknown report', () {
      final report = PlatformProbeReport.fromPayload(<String, Object?>{});

      expect(report.isReported, isFalse);
      expect(report.info.type, PlatformType.unknown);
      expect(report.codecs.isKnown, isFalse);
    });

    test('every answered section is stamped as reported', () {
      final report = PlatformProbeReport.fromPayload(<String, Object?>{
        'capabilities': <String, Object?>{'hardwareDecode': false, 'pictureInPicture': true},
        'device': <String, Object?>{'cpuCores': 8, 'totalRamMb': 4096, 'lowRamDevice': true},
        'codecs': <String, Object?>{
          'video': <String, Object?>{
            'hevc': <String, Object?>{'hardware': true, 'maxWidth': 3840, 'maxHeight': 2160},
            'avc1.640028': <String, Object?>{'hardware': false},
          },
        },
        'info': <String, Object?>{'type': 'android', 'name': 'Android', 'version': '14', 'isEmulator': true},
      });

      expect(report.isReported, isTrue);
      // An explicit "no" must not be confused with the optimistic default.
      expect(report.capabilities.hardwareDecode, isFalse);
      expect(report.capabilities.pictureInPicture, isTrue);
      // A question the platform skipped keeps the core's documented default.
      expect(report.capabilities.fullscreen, isTrue);

      expect(report.device.cpuCores, 8);
      expect(report.device.totalRamMb, 4096);
      expect(report.device.lowRamDevice, isTrue);

      // Engine spellings fold into the shared vocabulary.
      expect(report.codecs.video.keys, containsAll(<VideoCodec>[VideoCodec.hevc, VideoCodec.h264]));
      expect(report.codecs.canDecodeInHardware(VideoCodec.hevc, width: 1920, height: 1080), isTrue);
      expect(report.codecs.canDecodeInHardware(VideoCodec.h264), isFalse);
      // A codec nobody reported answers null, not false.
      expect(report.codecs.canDecodeInHardware(VideoCodec.av1), isNull);

      expect(report.info.type, PlatformType.android);
      expect(report.info.isEmulator, isTrue);
    });

    test('a capabilities block that says "no" is still reported', () {
      final report = PlatformProbeReport.fromPayload(<String, Object?>{
        'capabilities': <String, Object?>{'hardwareDecode': false},
      });

      expect(report.capabilities.reported, isTrue, reason: 'a real "no" differs from no probe');
      expect(report.capabilities.hardwareDecode, isFalse);
    });
  });

  group('NativePlatformProvider over the method channel', () {
    test('a successful probe answers from the payload', () async {
      mockProbe(<String, Object?>{
        'capabilities': <String, Object?>{'softwareDecode': false},
        'info': <String, Object?>{'type': 'windows', 'name': 'Windows'},
      });

      final provider = await NativePlatformProvider.load();

      expect(provider.isReady, isTrue);
      expect(provider.type, PlatformType.windows);
      expect(provider.capabilities.softwareDecode, isFalse);
    });

    test('a platform that cannot answer degrades to unreported, never throws', () async {
      // No mock handler installed: MissingPluginException, as on an unbuilt host.
      final provider = await NativePlatformProvider.load();

      expect(provider.isReady, isFalse);
      expect(provider.type, PlatformType.unknown);
      expect(provider.report.isReported, isFalse);
    });

    test('a platform-side error also reports unknown, not a crash', () async {
      mockProbe(_Throwing(PlatformException(code: 'PROBE_FAILED')));

      final provider = await NativePlatformProvider.load();

      expect(provider.isReady, isFalse);
    });

    test('refresh replaces the cached report', () async {
      mockProbe(<String, Object?>{
        'info': <String, Object?>{'type': 'android', 'name': 'Android'},
      });
      final provider = await NativePlatformProvider.load();
      expect(provider.type, PlatformType.android);

      mockProbe(<String, Object?>{
        'info': <String, Object?>{'type': 'ios', 'name': 'iOS'},
      });
      await provider.refresh();

      expect(provider.type, PlatformType.ios);
    });
  });

  group('probeOverChannel', () {
    test('exercises the payload contract without the singleton', () async {
      mockProbe(<String, Object?>{
        'codecs': <String, Object?>{
          'video': <String, Object?>{
            'video/av01': <String, Object?>{'hardware': true},
          },
        },
      });

      final report = await probeOverChannel(channel);

      expect(report.codecs.canDecodeInHardware(VideoCodec.av1), isTrue);
    });
  });
}

final class _Throwing {
  _Throwing(this.error);
  final Object error;
}
