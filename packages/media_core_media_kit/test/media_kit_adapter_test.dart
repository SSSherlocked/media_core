import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';

void main() {
  group('MpvPlatformProfile driver tables', () {
    test('iOS exposes only the video output it actually has', () {
      final drivers = MpvPlatformProfile.videoOutputDriversForPlatform(TargetPlatform.iOS);

      expect(drivers.keys, <String>['libmpv']);
      // Desktop tables would offer a driver libmpv-on-iOS cannot open.
      expect(MpvPlatformProfile.videoOutputDriversForPlatform(TargetPlatform.windows).keys, contains('gpu'));
    });

    test('each mobile platform gets its own audio backends', () {
      final android = MpvPlatformProfile.audioOutputDriversForPlatform(TargetPlatform.android);
      final ios = MpvPlatformProfile.audioOutputDriversForPlatform(TargetPlatform.iOS);

      expect(android.keys, containsAll(<String>['audiotrack', 'aaudio', 'opensles', 'null']));
      expect(ios.keys, containsAll(<String>['audiounit', 'null']));
      expect(ios.keys, isNot(contains('audiotrack')));
      expect(android.keys, isNot(contains('audiounit')));
    });

    test('hardware decoders are the platform sets, iOS carrying videotoolbox', () {
      expect(MpvPlatformProfile.hardwareDecodersForPlatform(TargetPlatform.iOS).keys, contains('videotoolbox'));
      expect(MpvPlatformProfile.hardwareDecodersForPlatform(TargetPlatform.macOS).keys, contains('videotoolbox'));
      expect(MpvPlatformProfile.hardwareDecodersForPlatform(TargetPlatform.iOS).keys, isNot(contains('d3d11va')));
    });
  });

  group('MpvPlatformProfile normalization', () {
    test('a known driver passes through untouched', () {
      expect(MpvPlatformProfile.normalizeVideoOutputDriverForPlatform('gpu', TargetPlatform.windows), 'gpu');
      expect(MpvPlatformProfile.normalizeHardwareDecoderForPlatform('auto-safe', TargetPlatform.windows), 'auto-safe');
    });

    test('a value persisted on another platform falls back instead of reaching libmpv', () {
      // `gpu-next` is a desktop renderer; a setting carried onto iOS must not
      // be handed to libmpv there.
      expect(MpvPlatformProfile.normalizeVideoOutputDriverForPlatform('gpu-next', TargetPlatform.iOS), 'libmpv');
      // An Android backend name on iOS falls back to the auto answer.
      expect(MpvPlatformProfile.normalizeAudioOutputDriverForPlatform('audiotrack', TargetPlatform.iOS), 'auto');
      // A decoder string from another platform's table never leaks through.
      expect(MpvPlatformProfile.normalizeHardwareDecoderForPlatform('audiotrack', TargetPlatform.iOS), 'auto');
    });

    test('defaults follow the platform: libmpv on iOS, gpu elsewhere', () {
      expect(MpvPlatformProfile.defaultVideoOutputDriverForPlatform(TargetPlatform.iOS), 'libmpv');
      for (final platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        expect(MpvPlatformProfile.defaultVideoOutputDriverForPlatform(platform), 'gpu', reason: '$platform');
      }
    });

    test('only Android and Linux ship a native audio preference', () {
      expect(
        MpvPlatformProfile.defaultAudioOutputDriverForPlatform(TargetPlatform.android),
        'audiotrack,aaudio,opensles,',
      );
      expect(MpvPlatformProfile.defaultAudioOutputDriverForPlatform(TargetPlatform.linux), 'alsa');
      expect(MpvPlatformProfile.defaultAudioOutputDriverForPlatform(TargetPlatform.macOS), isNull);
      expect(MpvPlatformProfile.defaultAudioOutputDriverForPlatform(TargetPlatform.windows), isNull);
      expect(MpvPlatformProfile.defaultAudioOutputDriverForPlatform(TargetPlatform.iOS), isNull);
    });
  });

  group('MpvPlatformProfile effective audio output', () {
    test('without an expert override the platform default is used', () {
      expect(
        MpvPlatformProfile.effectiveAudioOutputDriverForPlatform(
          customOutput: false,
          configuredDriver: 'pulse',
          platform: TargetPlatform.android,
        ),
        'audiotrack,aaudio,opensles,',
      );
      expect(
        MpvPlatformProfile.effectiveAudioOutputDriverForPlatform(
          customOutput: false,
          configuredDriver: 'aaudio',
          platform: TargetPlatform.macOS,
        ),
        isNull,
      );
    });

    test('Android `auto` means the ordered fallback chain, not the pseudo-driver', () {
      expect(
        MpvPlatformProfile.effectiveAudioOutputDriverForPlatform(
          customOutput: true,
          configuredDriver: 'auto',
          platform: TargetPlatform.android,
        ),
        'audiotrack,aaudio,opensles,',
      );
    });

    test('a real backend selected on its own platform is honored verbatim', () {
      expect(
        MpvPlatformProfile.effectiveAudioOutputDriverForPlatform(
          customOutput: true,
          configuredDriver: 'aaudio',
          platform: TargetPlatform.android,
        ),
        'aaudio',
      );
      expect(
        MpvPlatformProfile.effectiveAudioOutputDriverForPlatform(
          customOutput: true,
          configuredDriver: 'pulse',
          platform: TargetPlatform.linux,
        ),
        'pulse',
      );
    });

    test('`null` is recognized as "audio output disabled" only when configured', () {
      expect(
        MpvPlatformProfile.isAudioOutputDisabledForPlatform(
          customOutput: true,
          configuredDriver: 'null',
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
      expect(
        MpvPlatformProfile.isAudioOutputDisabledForPlatform(
          customOutput: false,
          configuredDriver: 'null',
          platform: TargetPlatform.windows,
        ),
        isFalse,
        reason: 'a disabled setting the host did not choose must not mute the player',
      );
    });
  });

  group('PlayerConsts', () {
    test('the desktop tables include the drivers this adapter offers', () {
      expect(PlayerConsts.videoOutputDrivers.keys, containsAll(<String>['auto', 'gpu', 'gpu-next']));
      expect(PlayerConsts.audioOutputDrivers.keys, containsAll(<String>['auto', 'null']));
      expect(PlayerConsts.hardwareDecoder.keys, containsAll(<String>['auto', 'no']));
    });
  });

  group('MediaKitPlayerAdapter capability honesty', () {
    test('the frame heartbeat is only claimed where the observer can run', () {
      final adapter = MediaKitPlayerAdapter(
        capabilities: MediaKitPlayerAdapter.defaultCapabilities.copyWith(supportsVideoFrameProgress: true),
      );
      addTearDown(adapter.dispose);

      final expected = defaultTargetPlatform == TargetPlatform.windows;
      expect(
        adapter.capabilities.supportsVideoFrameProgress,
        expected,
        reason: 'a watchdog armed on a heartbeat that can never arrive tears down healthy streams',
      );
    });

    test('availability is false before a video controller exists', () {
      final adapter = MediaKitPlayerAdapter();
      addTearDown(adapter.dispose);

      expect(adapter.available, isFalse);
      expect(adapter.hasDecodedVideoFrame, isFalse);
    });
  });

  group('MediaKitAdapterFactory', () {
    test('claims only its own backend id', () {
      const factory = MediaKitAdapterFactory();

      expect(factory.supports('mpv'), isTrue);
      expect(factory.supports('fvp'), isFalse);
    });

    test('the registration carries capabilities and the default priority', () {
      const factory = MediaKitAdapterFactory();

      final registration = factory.registration();

      expect(registration.id, 'mpv');
      expect(registration.priority, 100, reason: 'media_kit is the default engine');
      expect(registration.capabilities.supportsEngineOptions, isTrue);
    });

    test('a builder-supplied video configuration is re-evaluated per adapter', () {
      var calls = 0;
      final factory = MediaKitAdapterFactory(
        videoControllerConfigurationBuilder: () {
          calls++;
          return const VideoControllerConfiguration(enableHardwareAcceleration: false);
        },
      );

      // Thrown away on purpose: the test counts the builder calls, and disposing
      // an adapter that never opened a source has nothing to wait for.
      unawaited((factory.create('mpv') as MediaKitPlayerAdapter).dispose());
      unawaited((factory.create('mpv') as MediaKitPlayerAdapter).dispose());

      expect(calls, 2, reason: 'an engine rebuild must pick up host settings changed at runtime');
    });

    test('custom-input recipe key is the documented metadata name', () {
      expect(kMediaKitCustomInputKey, 'media_kit.custom_input');
    });
  });
}
