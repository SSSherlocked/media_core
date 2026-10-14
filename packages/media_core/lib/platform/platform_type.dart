import 'package:equatable/equatable.dart';

/// Supported runtime platform types.
///
/// [PlatformType] describes the target environment
/// where the media core is running.
///
/// It does not:
///
/// - detect platform
/// - query native APIs
///
/// Those belong to:
///
/// - PlatformProvider
/// - PlatformInfo
final class PlatformType extends Equatable {
  /// Creates from string.
  factory PlatformType.fromString(String value) {
    switch (value.toLowerCase()) {
      case 'android':
        return android;

      case 'ios':
        return ios;

      case 'windows':
        return windows;

      case 'macos':
        return macos;

      case 'linux':
        return linux;

      case 'web':
        return web;

      case 'tv':
        return tv;

      default:
        return unknown;
    }
  }

  /// Creates platform type.
  const PlatformType._(this.value);

  /// Android platform.
  static const android = PlatformType._('android');

  /// iOS platform.
  static const ios = PlatformType._('ios');

  /// Windows platform.
  static const windows = PlatformType._('windows');

  /// macOS platform.
  static const macos = PlatformType._('macos');

  /// Linux platform.
  static const linux = PlatformType._('linux');

  /// Web platform.
  static const web = PlatformType._('web');

  /// TV platform.
  ///
  /// Example:
  ///
  /// - Android TV
  /// - Google TV
  static const tv = PlatformType._('tv');

  /// Unknown platform.
  static const unknown = PlatformType._('unknown');

  /// Raw platform value.
  final String value;

  /// Whether this is mobile platform.
  bool get isMobile {
    return this == android || this == ios;
  }

  /// Whether this is desktop platform.
  bool get isDesktop {
    return this == windows || this == macos || this == linux;
  }

  /// Whether this is TV platform.
  bool get isTv {
    return this == tv;
  }

  /// Whether this is web.
  bool get isWeb {
    return this == web;
  }

  /// Whether platform is unknown.
  bool get isUnknown {
    return this == unknown;
  }

  @override
  List<Object?> get props => [value];

  @override
  String toString() {
    return value;
  }
}
