import 'package:media_core/media_core.dart';

import 'package:media_core_native/src/media_core_native_platform.dart';

/// The channel method a probe is requested through.
///
/// Kept next to the parser because the two are one contract: the native side
/// answers this call with the payload [PlatformProbeReport] reads.
const String kProbeMethod = 'probe';

/// One native platform report, parsed into the core's vocabulary.
///
/// The plugin's whole job is this translation: the platform side answers with
/// plain data (booleans, numbers, codec names) because that is what a method
/// channel carries well, and this turns it into the typed values `media_core`
/// reasons about — [PlatformCapabilities], [PlatformDeviceProfile] and
/// [PlatformCodecCapabilities].
///
/// Responsibilities:
///
/// - parse one payload
/// - keep every field optional, defaulting to "unknown" rather than "no"
///
/// It does not:
///
/// - call the platform (that is the channel implementation)
/// - cache the result (the provider does)
/// - decide what a backend does with the answer
final class PlatformProbeReport {
  /// Creates a report.
  const PlatformProbeReport({
    required this.capabilities,
    required this.device,
    required this.codecs,
    required this.info,
  });

  /// Parses a channel payload.
  ///
  /// Every section is optional. A platform implementation that reports only
  /// what it can answer leaves the rest out, and the parser fills in the
  /// "unknown" values — which is deliberately different from "unsupported".
  factory PlatformProbeReport.fromPayload(Object? payload) {
    if (payload is! Map) {
      return unknown;
    }

    final map = payload.map((key, value) => MapEntry(key.toString(), value));

    return PlatformProbeReport(
      capabilities: _capabilitiesFrom(map['capabilities']),
      device: _deviceFrom(map['device']),
      codecs: _codecsFrom(map['codecs']),
      info: _infoFrom(map['info']),
    );
  }

  /// Capabilities reported by the platform.
  final PlatformCapabilities capabilities;

  /// Device facts reported by the platform.
  final PlatformDeviceProfile device;

  /// Codec decoding capability reported by the platform.
  final PlatformCodecCapabilities codecs;

  /// Platform identity reported by the platform.
  final PlatformInfo info;

  /// The report of a platform nobody probed.
  static const PlatformProbeReport unknown = PlatformProbeReport(
    capabilities: PlatformCapabilities(),
    device: PlatformDeviceProfile.unknown,
    codecs: PlatformCodecCapabilities.unknown,
    info: PlatformInfo(type: PlatformType.unknown),
  );

  /// Whether anything in this report came from the platform.
  bool get isReported => capabilities.reported || device.reported || codecs.reported;

  static PlatformCapabilities _capabilitiesFrom(Object? raw) {
    if (raw is! Map) {
      return const PlatformCapabilities();
    }

    final map = raw.map((key, value) => MapEntry(key.toString(), value));

    bool? flag(String key) => map[key] as bool?;

    // Anything the platform did not answer keeps the core's optimistic default
    // but the whole block is stamped as reported: it came from a real probe,
    // and a probe that answers "no" is different from no probe at all.
    return PlatformCapabilities(
      hardwareDecode: flag('hardwareDecode') ?? true,
      softwareDecode: flag('softwareDecode') ?? true,
      videoRendering: flag('videoRendering') ?? true,
      audioPlayback: flag('audioPlayback') ?? true,
      subtitleRendering: flag('subtitleRendering') ?? true,
      pictureInPicture: flag('pictureInPicture') ?? false,
      fullscreen: flag('fullscreen') ?? true,
      externalDisplay: flag('externalDisplay') ?? false,
      backgroundPlayback: flag('backgroundPlayback') ?? false,
      networkPlayback: flag('networkPlayback') ?? true,
      localPlayback: flag('localPlayback') ?? true,
      reported: true,
    );
  }

  static PlatformDeviceProfile _deviceFrom(Object? raw) {
    if (raw is! Map) {
      return PlatformDeviceProfile.unknown;
    }

    final map = raw.map((key, value) => MapEntry(key.toString(), value));

    return PlatformDeviceProfile.fromMap(map);
  }

  static PlatformCodecCapabilities _codecsFrom(Object? raw) {
    if (raw is! Map) {
      return PlatformCodecCapabilities.unknown;
    }

    final map = raw.map((key, value) => MapEntry(key.toString(), value));

    return PlatformCodecCapabilities.fromMap(map);
  }

  static PlatformInfo _infoFrom(Object? raw) {
    if (raw is! Map) {
      return const PlatformInfo(type: PlatformType.unknown);
    }

    final map = raw.map((key, value) => MapEntry(key.toString(), value));

    return PlatformInfo(
      type: PlatformType.fromString(map['type'] as String? ?? 'unknown'),
      name: map['name'] as String?,
      version: map['version'] as String?,
      buildNumber: map['buildNumber'] as String?,
      architecture: map['architecture'] as String?,
      deviceModel: map['deviceModel'] as String?,
      isEmulator: map['isEmulator'] as bool? ?? false,
    );
  }
}

/// Reads the platform report from [platform].
///
/// Failures are swallowed into [PlatformProbeReport.unknown]: a probe that
/// cannot run must never keep playback from starting, and every consumer
/// already treats "unknown" as "decide for yourself".
Future<PlatformProbeReport> readPlatformReport(MediaCoreNativePlatform platform) async {
  try {
    final payload = await platform.invoke<Object?>(kProbeMethod);

    return PlatformProbeReport.fromPayload(payload);
  } on Object catch (_) {
    return PlatformProbeReport.unknown;
  }
}
