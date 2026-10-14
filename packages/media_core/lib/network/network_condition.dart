import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/network/library.dart' show NetworkManager, NetworkMonitor;
import 'package:media_core/network/network_quality.dart';
import 'package:media_core/network/network_type.dart';

part 'network_condition.freezed.dart';

/// Represents current network condition.
///
/// A [NetworkCondition] is a snapshot describing
/// the current usable network environment.
///
/// Responsibilities:
///
/// - describe connectivity condition
/// - describe network transport type
/// - describe estimated quality
/// - provide immutable network information
///
/// It does not:
///
/// - detect network changes
/// - measure bandwidth
/// - perform connectivity checks
///
/// Those belong to:
///
/// - [NetworkMonitor]
/// - [NetworkManager]
@freezed
abstract class NetworkCondition with _$NetworkCondition {
  /// Creates a network condition.
  const factory NetworkCondition({
    /// Whether network is available.
    @Default(false) bool connected,

    /// Current network type.
    @Default(NetworkType.unknown) NetworkType type,

    /// Current network quality.
    @Default(NetworkQuality.unknown) NetworkQuality quality,

    /// Estimated download bandwidth in bits per second.
    ///
    /// May be unavailable.
    int? downloadBandwidth,

    /// Estimated upload bandwidth in bits per second.
    ///
    /// May be unavailable.
    int? uploadBandwidth,

    /// Network latency in milliseconds.
    ///
    /// May be unavailable.
    int? latency,

    /// Whether connection is metered.
    @Default(false) bool metered,

    /// Whether connection is considered expensive.
    @Default(false) bool expensive,

    /// Time when this condition was created.
    DateTime? timestamp,
  }) = _NetworkCondition;

  /// Creates an unknown network condition.
  factory NetworkCondition.unknown() {
    return const NetworkCondition();
  }
}

/// Extensions for [NetworkCondition].
extension NetworkConditionExtension on NetworkCondition {
  /// Whether this condition can be used.
  bool get isAvailable {
    return connected && quality != NetworkQuality.unavailable;
  }

  /// Whether this is a fast connection.
  bool get isFast {
    return quality == NetworkQuality.good || quality == NetworkQuality.excellent;
  }

  /// Whether latency information exists.
  bool get hasLatency {
    return latency != null;
  }

  /// Whether bandwidth information exists.
  bool get hasBandwidth {
    return downloadBandwidth != null || uploadBandwidth != null;
  }
}
