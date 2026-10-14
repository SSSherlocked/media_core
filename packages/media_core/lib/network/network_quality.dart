import 'package:media_core/network/library.dart' show NetworkMetrics, NetworkMonitor;

/// Represents network quality level.
///
/// Network quality is an abstract classification
/// used by higher-level components.
///
/// It does not:
///
/// - measure bandwidth
/// - perform latency tests
/// - monitor network changes
///
/// Those belong to:
///
/// - [NetworkMonitor]
/// - [NetworkMetrics]
enum NetworkQuality {
  /// Unknown quality.
  unknown,

  /// No usable network.
  unavailable,

  /// Very poor network condition.
  poor,

  /// Limited but usable network condition.
  fair,

  /// Good network condition.
  good,

  /// Excellent network condition.
  excellent,
}

/// Extensions for [NetworkQuality].
extension NetworkQualityExtension on NetworkQuality {
  /// Whether this quality can support playback.
  bool get isUsable {
    switch (this) {
      case NetworkQuality.unknown:
      case NetworkQuality.unavailable:
      case NetworkQuality.poor:
        return false;

      case NetworkQuality.fair:
      case NetworkQuality.good:
      case NetworkQuality.excellent:
        return true;
    }
  }

  /// Whether this quality is stable.
  bool get isStable {
    switch (this) {
      case NetworkQuality.good:
      case NetworkQuality.excellent:
        return true;

      case NetworkQuality.unknown:
      case NetworkQuality.unavailable:
      case NetworkQuality.poor:
      case NetworkQuality.fair:
        return false;
    }
  }

  /// Returns a numeric score.
  ///
  /// Higher values represent better quality.
  int get score {
    switch (this) {
      case NetworkQuality.unknown:
        return 0;

      case NetworkQuality.unavailable:
        return 1;

      case NetworkQuality.poor:
        return 2;

      case NetworkQuality.fair:
        return 3;

      case NetworkQuality.good:
        return 4;

      case NetworkQuality.excellent:
        return 5;
    }
  }

  /// Returns readable name.
  String get displayName {
    switch (this) {
      case NetworkQuality.unknown:
        return 'unknown';

      case NetworkQuality.unavailable:
        return 'unavailable';

      case NetworkQuality.poor:
        return 'poor';

      case NetworkQuality.fair:
        return 'fair';

      case NetworkQuality.good:
        return 'good';

      case NetworkQuality.excellent:
        return 'excellent';
    }
  }
}
