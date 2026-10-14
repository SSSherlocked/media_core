import 'package:media_core/network/library.dart' show NetworkManager, NetworkMonitor;

/// Represents the type of network connection.
///
/// This enum describes the current transport type
/// used by the network layer.
///
/// It does not:
///
/// - detect network changes
/// - query platform APIs
/// - provide connectivity monitoring
///
/// Those belong to:
///
/// - [NetworkMonitor]
/// - [NetworkManager]
enum NetworkType {
  /// Unknown network type.
  unknown,

  /// No network connection.
  none,

  /// Ethernet connection.
  ethernet,

  /// Wi-Fi connection.
  wifi,

  /// Cellular/mobile connection.
  mobile,

  /// Bluetooth or PAN connection.
  bluetooth,

  /// VPN connection.
  vpn,

  /// Other network type.
  other,
}

/// Extensions for [NetworkType].
extension NetworkTypeExtension on NetworkType {
  /// Whether this type represents an active connection.
  bool get isConnected {
    switch (this) {
      case NetworkType.unknown:
      case NetworkType.none:
        return false;

      case NetworkType.ethernet:
      case NetworkType.wifi:
      case NetworkType.mobile:
      case NetworkType.bluetooth:
      case NetworkType.vpn:
      case NetworkType.other:
        return true;
    }
  }

  /// Whether this is a wireless connection.
  bool get isWireless {
    switch (this) {
      case NetworkType.wifi:
      case NetworkType.mobile:
      case NetworkType.bluetooth:
        return true;

      case NetworkType.unknown:
      case NetworkType.none:
      case NetworkType.ethernet:
      case NetworkType.vpn:
      case NetworkType.other:
        return false;
    }
  }

  /// Returns a readable name.
  String get displayName {
    switch (this) {
      case NetworkType.unknown:
        return 'unknown';

      case NetworkType.none:
        return 'none';

      case NetworkType.ethernet:
        return 'ethernet';

      case NetworkType.wifi:
        return 'wifi';

      case NetworkType.mobile:
        return 'mobile';

      case NetworkType.bluetooth:
        return 'bluetooth';

      case NetworkType.vpn:
        return 'vpn';

      case NetworkType.other:
        return 'other';
    }
  }
}
