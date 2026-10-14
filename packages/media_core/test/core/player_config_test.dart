import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/core/player_config.dart';
import 'package:media_core/core/player_constants.dart';

void main() {
  group('PlayerConfig', () {
    test('default values are sensible', () {
      const config = PlayerConfig.defaults;
      expect(config.autoInitialize, isTrue);
      expect(config.autoPlay, isFalse);
      expect(config.loop, isFalse);
      expect(config.muted, isFalse);
      expect(config.volume, PlayerConstants.defaultVolume);
      expect(config.playbackRate, PlayerConstants.defaultPlaybackRate);
      expect(config.enableAudio, isTrue);
      expect(config.enableVideo, isTrue);
      expect(config.enableRecovery, isTrue);
      expect(config.enableFallback, isTrue);
    });

    test('asserts reject invalid volume', () {
      expect(() => PlayerConfig(volume: 1.5), throwsA(isA<AssertionError>()));
      expect(() => PlayerConfig(volume: -0.1), throwsA(isA<AssertionError>()));
    });

    test('asserts reject invalid playback rate', () {
      expect(() => PlayerConfig(playbackRate: 0), throwsA(isA<AssertionError>()));
      expect(() => PlayerConfig(playbackRate: 99), throwsA(isA<AssertionError>()));
    });

    test('asserts reject negative attempt counts', () {
      expect(() => PlayerConfig(maxRecoveryAttempts: -1), throwsA(isA<AssertionError>()));
      expect(() => PlayerConfig(maxFallbackAttempts: -1), throwsA(isA<AssertionError>()));
    });

    test('presence helpers', () {
      const plain = PlayerConfig.defaults;
      expect(plain.hasName, isFalse);
      expect(plain.hasMediaType, isFalse);
      expect(plain.hasSource, isFalse);

      const named = PlayerConfig(name: 'main-player');
      expect(named.hasName, isTrue);
    });

    test('output mode falls back to enable flags', () {
      const audioOnly = PlayerConfig(enableVideo: false);
      expect(audioOnly.isAudioOnly, isTrue);
      expect(audioOnly.isVideoOnly, isFalse);

      const videoOnly = PlayerConfig(enableAudio: false);
      expect(videoOnly.isVideoOnly, isTrue);

      const both = PlayerConfig.defaults;
      expect(both.isAudioVideo, isTrue);
    });

    test('equality includes all fields', () {
      const a = PlayerConfig(name: 'x', volume: 0.5);
      const b = PlayerConfig(name: 'x', volume: 0.5);
      const c = PlayerConfig(name: 'x', volume: 0.6);
      expect(a, b);
      expect(a, isNot(c));
    });
  });
}
