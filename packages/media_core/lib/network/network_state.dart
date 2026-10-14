import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/network/library.dart' show NetworkManager, NetworkMonitor;
import 'package:media_core/network/network_quality.dart';
import 'package:media_core/network/network_type.dart';

part 'network_state.freezed.dart';

/// Represents current network state.
///
/// This is an immutable snapshot describing
/// the current network environment.
///
/// Responsibilities:
///
/// - store current network type
/// - store network quality
/// - represent connectivity availability
/// - provide immutable state updates
///
/// It does not:
///
/// - monitor network changes
/// - perform network requests
/// - manage listeners
///
/// Those belong to:
///
/// - [NetworkMonitor]
/// - [NetworkManager]
@freezed
abstract class NetworkState with _$NetworkState {
  /// Creates a network state.
  const factory NetworkState({
    /// Whether network connection is available.
    @Default(false) bool connected,

    /// Current network type.
    @Default(NetworkType.unknown) NetworkType type,

    /// Current network quality.
    @Default(NetworkQuality.unknown) NetworkQuality quality,

    /// Whether the network is metered.
    ///
    /// Examples:
    /// - mobile data
    /// - restricted hotspot
    @Default(false) bool metered,

    /// Whether network is considered expensive.
    @Default(false) bool expensive,

    /// Last update timestamp.
    DateTime? updatedAt,
  }) = _NetworkState;

  /// Creates an initial unknown network state.
  factory NetworkState.initial() {
    return const NetworkState();
  }
}
