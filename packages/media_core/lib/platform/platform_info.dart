import 'package:equatable/equatable.dart';
import 'package:media_core/platform/platform_type.dart';

/// Runtime platform information.
///
/// [PlatformInfo] contains immutable information
/// about the execution environment.
///
/// Responsibilities:
///
/// - store platform identity
/// - store system metadata
/// - provide platform classification
///
/// It does not:
///
/// - detect platform
/// - access native APIs
///
/// Those belong to:
///
/// - PlatformProvider
final class PlatformInfo extends Equatable {
  /// Creates platform information.
  const PlatformInfo({
    required this.type,

    this.name,

    this.version,

    this.buildNumber,

    this.architecture,

    this.deviceModel,

    this.isEmulator = false,
  });

  /// Current platform type.
  final PlatformType type;

  /// Platform display name.
  ///
  /// Example:
  ///
  /// - Android
  /// - Windows
  /// - macOS
  final String? name;

  /// Operating system version.
  ///
  /// Example:
  ///
  /// - Android 15
  /// - Windows 11
  final String? version;

  /// Build number.
  final String? buildNumber;

  /// CPU architecture.
  ///
  /// Example:
  ///
  /// - arm64
  /// - x64
  final String? architecture;

  /// Device model.
  ///
  /// Example:
  ///
  /// - Pixel
  /// - Surface
  final String? deviceModel;

  /// Whether running on emulator.
  final bool isEmulator;

  /// Whether this is Android.
  bool get isAndroid {
    return type == PlatformType.android;
  }

  /// Whether this is iOS.
  bool get isIos {
    return type == PlatformType.ios;
  }

  /// Whether this is mobile.
  bool get isMobile {
    return type.isMobile;
  }

  /// Whether this is desktop.
  bool get isDesktop {
    return type.isDesktop;
  }

  /// Whether this is TV.
  bool get isTv {
    return type.isTv;
  }

  /// Whether this is web.
  bool get isWeb {
    return type.isWeb;
  }

  /// Creates modified information.
  PlatformInfo copyWith({
    PlatformType? type,

    String? name,

    String? version,

    String? buildNumber,

    String? architecture,

    String? deviceModel,

    bool? isEmulator,
  }) {
    return PlatformInfo(
      type: type ?? this.type,

      name: name ?? this.name,

      version: version ?? this.version,

      buildNumber: buildNumber ?? this.buildNumber,

      architecture: architecture ?? this.architecture,

      deviceModel: deviceModel ?? this.deviceModel,

      isEmulator: isEmulator ?? this.isEmulator,
    );
  }

  @override
  List<Object?> get props => [type, name, version, buildNumber, architecture, deviceModel, isEmulator];

  @override
  String toString() {
    return 'PlatformInfo('
        'type=$type, '
        'version=$version, '
        'arch=$architecture'
        ')';
  }
}
