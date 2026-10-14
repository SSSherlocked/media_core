import 'package:flutter/foundation.dart';
import 'package:media_core_media_kit/src/utils/player_consts.dart';

const Map<String, String> _iosVideoOutputDrivers = {'libmpv': 'libmpv'};

const Map<String, String> _iosAudioOutputDrivers = {
  'auto': 'auto',
  'audiounit': 'audiounit (iOS only)',
  'null': 'null (No audio output)',
};

const Map<String, String> _androidAudioOutputDrivers = {
  'auto': 'auto (Automatic fallback)',
  'audiotrack': 'audiotrack (Android AudioTrack)',
  'aaudio': 'aaudio (Android 8.0+)',
  'opensles': 'opensles (Legacy fallback)',
  'null': 'null (No audio output)',
};

const Map<String, String> _iosHardwareDecoders = {
  'auto': 'auto',
  'auto-safe': 'auto-safe',
  'auto-copy': 'auto-copy',
  'no': 'no',
  'videotoolbox': 'videotoolbox',
  'videotoolbox-copy': 'videotoolbox-copy',
};

/// Platform contract for MPV drivers and decoders.
///
/// Every choice is normalised here before it reaches libmpv, so a value
/// persisted on one platform cannot leak a broken driver into another.
abstract final class MpvPlatformProfile {
  /// The video output drivers a platform will accept, in preference order.
  static Map<String, String> videoOutputDriversForPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.iOS ? _iosVideoOutputDrivers : PlayerConsts.videoOutputDrivers;

  /// The audio output drivers a platform will accept, in preference order.
  static Map<String, String> audioOutputDriversForPlatform(TargetPlatform platform) => switch (platform) {
    TargetPlatform.android => _androidAudioOutputDrivers,
    TargetPlatform.iOS => _iosAudioOutputDrivers,
    _ => PlayerConsts.audioOutputDrivers,
  };

  /// The hardware decoders a platform is allowed to reach for.
  static Map<String, String> hardwareDecodersForPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.iOS ? _iosHardwareDecoders : PlayerConsts.hardwareDecoder;

  /// The video driver used when the host configured none.
  static String defaultVideoOutputDriverForPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.iOS ? 'libmpv' : 'gpu';

  /// Native audio preference applied when expert output overrides are
  /// disabled.
  static String? defaultAudioOutputDriverForPlatform(TargetPlatform platform) => switch (platform) {
    TargetPlatform.android => 'audiotrack,aaudio,opensles,',
    TargetPlatform.linux => 'alsa',
    _ => null,
  };

  /// Maps a configured video driver onto one this platform can actually load.
  static String normalizeVideoOutputDriverForPlatform(String value, TargetPlatform platform) =>
      _normalize(value, videoOutputDriversForPlatform(platform), defaultVideoOutputDriverForPlatform(platform));

  /// Maps a configured audio driver onto one this platform can actually load.
  static String normalizeAudioOutputDriverForPlatform(String value, TargetPlatform platform) =>
      _normalize(value, audioOutputDriversForPlatform(platform), 'auto');

  /// Maps a configured decoder onto one this platform can actually load.
  static String normalizeHardwareDecoderForPlatform(String value, TargetPlatform platform) =>
      _normalize(value, hardwareDecodersForPlatform(platform), 'auto');

  /// Resolves the value sent to libmpv after applying the platform
  /// contract.
  ///
  /// On Android, `auto` is rewritten to the same ordered fallback chain
  /// used by the safe default instead of being passed as a pseudo-driver.
  static String? effectiveAudioOutputDriverForPlatform({
    required bool customOutput,
    required String configuredDriver,
    required TargetPlatform platform,
  }) {
    if (!customOutput) return defaultAudioOutputDriverForPlatform(platform);

    final normalized = normalizeAudioOutputDriverForPlatform(configuredDriver, platform);

    if (platform == TargetPlatform.android && normalized == 'auto') {
      return defaultAudioOutputDriverForPlatform(platform);
    }

    return normalized;
  }

  /// Whether the resolved configuration asks for audio to be switched off.
  static bool isAudioOutputDisabledForPlatform({
    required bool customOutput,
    required String configuredDriver,
    required TargetPlatform platform,
  }) => customOutput && normalizeAudioOutputDriverForPlatform(configuredDriver, platform) == 'null';

  static String _normalize(String value, Map<String, String> available, String fallback) =>
      available.containsKey(value) ? value : fallback;
}
