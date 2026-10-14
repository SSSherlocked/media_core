import 'package:equatable/equatable.dart';

/// Hardware facts about the device the app is running on.
///
/// These are the numbers that decide *how* to play rather than *what* to play:
/// how many threads a software decoder gets, whether the box can hold a 1080p
/// decode next to the rest of the app, and whether the SoC is 32-bit only.
///
/// Responsibilities:
///
/// - carry the device facts a backend needs
/// - answer the "low end" question in one place
///
/// It does not:
///
/// - detect the platform (PlatformInfo does)
/// - query native APIs (PlatformProvider does)
/// - describe codecs (PlatformCodecCapabilities does)
///
/// ### Unknown is not low-end
///
/// [PlatformDeviceProfile.unknown] reports [reported] `false` and behaves like
/// a healthy device on purpose: a probe that failed, or a platform that has no
/// probe, must never silently tune playback down. Callers that want to be
/// conservative on unknown devices have to say so explicitly.
final class PlatformDeviceProfile extends Equatable {
  /// Creates a device profile.
  const PlatformDeviceProfile({
    this.cpuCores = 0,
    this.totalRamMb,
    this.lowRamDevice = false,
    this.supports64BitAbi = true,
    this.reported = false,
  });

  /// Creates a profile from a map.
  ///
  /// Every field falls back to the unknown profile, so a partial payload can
  /// never turn into a tuned-down device.
  factory PlatformDeviceProfile.fromMap(Map<String, Object?> map) {
    return PlatformDeviceProfile(
      cpuCores: (map['cpuCores'] as num?)?.toInt() ?? 0,
      totalRamMb: (map['totalRamMb'] as num?)?.toInt(),
      lowRamDevice: map['lowRamDevice'] as bool? ?? false,
      supports64BitAbi: map['supports64BitAbi'] as bool? ?? true,
      reported: map['reported'] as bool? ?? true,
    );
  }

  /// The profile of a device nobody probed.
  static const PlatformDeviceProfile unknown = PlatformDeviceProfile();

  /// Physical memory ceiling, in megabytes, below which a device counts as
  /// low-end.
  ///
  /// 2 GB is where Android boxes stop being able to hold a 1080p decode
  /// pipeline plus the demuxer budget next to the rest of the app.
  static const int lowRamThresholdMb = 2048;

  /// Core count at or below which a device counts as low-end.
  static const int lowCoreThreshold = 2;

  /// Lower bound of [softwareDecodeThreads].
  static const int minSoftwareDecodeThreads = 2;

  /// Upper bound of [softwareDecodeThreads].
  ///
  /// Past a handful of threads a decoder spends more time synchronising than
  /// decoding on the small SoCs this policy is about.
  static const int maxSoftwareDecodeThreads = 6;

  /// Logical CPU cores; `0` when unknown.
  final int cpuCores;

  /// Total physical memory in megabytes; null when unknown.
  final int? totalRamMb;

  /// Whether the platform itself classifies this device as low on RAM.
  ///
  /// Android answers this (`ActivityManager.isLowRamDevice`); nothing else
  /// does, and its absence is not a statement about the device.
  final bool lowRamDevice;

  /// Whether the *device* can run 64-bit code.
  ///
  /// Read from the device's supported ABI list, not from the running process:
  /// a 64-bit TV that happens to run a 32-bit APK is fine and must keep the
  /// normal pipeline.
  final bool supports64BitAbi;

  /// Whether these numbers came from a probe.
  ///
  /// `false` means the fields above are a guess, and every rule that would
  /// tune playback down must be skipped.
  final bool reported;

  /// Whether the numbers are known.
  bool get isKnown => reported;

  /// Whether the device cannot be assumed to decode full-resolution video
  /// smoothly in software.
  bool get isLowEnd {
    if (!reported) {
      return false;
    }

    if (lowRamDevice || !supports64BitAbi) {
      return true;
    }

    final ram = totalRamMb;

    if (ram != null && ram > 0 && ram <= lowRamThresholdMb) {
      return true;
    }

    return cpuCores > 0 && cpuCores <= lowCoreThreshold;
  }

  /// Threads to hand a software decoder.
  ///
  /// Clamped rather than proportional: mpv's own default is roughly one thread
  /// per core, which on a 2-core box starves the decode and on a 16-core one
  /// wastes scheduling. A device nobody probed gets the lower bound, which is
  /// what mpv would have used on a small device anyway.
  int get softwareDecodeThreads {
    if (cpuCores <= 0) {
      return minSoftwareDecodeThreads;
    }

    return cpuCores.clamp(minSoftwareDecodeThreads, maxSoftwareDecodeThreads);
  }

  /// Creates a modified profile.
  PlatformDeviceProfile copyWith({
    int? cpuCores,
    int? totalRamMb,
    bool? lowRamDevice,
    bool? supports64BitAbi,
    bool? reported,
  }) {
    return PlatformDeviceProfile(
      cpuCores: cpuCores ?? this.cpuCores,
      totalRamMb: totalRamMb ?? this.totalRamMb,
      lowRamDevice: lowRamDevice ?? this.lowRamDevice,
      supports64BitAbi: supports64BitAbi ?? this.supports64BitAbi,
      reported: reported ?? this.reported,
    );
  }

  /// Debug serialization.
  Map<String, Object?> toMap() {
    return {
      'cpuCores': cpuCores,
      'totalRamMb': totalRamMb,
      'lowRamDevice': lowRamDevice,
      'supports64BitAbi': supports64BitAbi,
      'reported': reported,
    };
  }

  @override
  List<Object?> get props => [cpuCores, totalRamMb, lowRamDevice, supports64BitAbi, reported];

  @override
  String toString() {
    return 'PlatformDeviceProfile('
        'cores: $cpuCores, '
        'ramMb: $totalRamMb, '
        'lowRam: $lowRamDevice, '
        '64bit: $supports64BitAbi, '
        'reported: $reported'
        ')';
  }
}
