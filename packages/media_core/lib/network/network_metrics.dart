import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/media_core.dart' show DiagnosticsManager, NetworkMonitor;

part 'network_metrics.freezed.dart';

/// Represents network performance metrics.
///
/// A [NetworkMetrics] is an immutable snapshot
/// containing network performance statistics.
///
/// Responsibilities:
///
/// - store latency information
/// - store bandwidth information
/// - store request statistics
/// - provide diagnostic data
///
/// It does not:
///
/// - measure network speed
/// - perform ping tests
/// - collect metrics automatically
///
/// Those belong to:
///
/// - [NetworkMonitor]
/// - [DiagnosticsManager]
@freezed
abstract class NetworkMetrics with _$NetworkMetrics {
  /// Creates network metrics.
  const factory NetworkMetrics({
    /// Average latency in milliseconds.
    int? averageLatency,

    /// Minimum latency in milliseconds.
    int? minimumLatency,

    /// Maximum latency in milliseconds.
    int? maximumLatency,

    /// Download throughput in bytes per second.
    int? downloadSpeed,

    /// Upload throughput in bytes per second.
    int? uploadSpeed,

    /// Total requests performed.
    @Default(0) int totalRequests,

    /// Successful request count.
    @Default(0) int successfulRequests,

    /// Failed request count.
    @Default(0) int failedRequests,

    /// Total received bytes.
    @Default(0) int receivedBytes,

    /// Total sent bytes.
    @Default(0) int sentBytes,

    /// Timestamp of this metrics snapshot.
    DateTime? timestamp,
  }) = _NetworkMetrics;

  /// Creates empty metrics.
  factory NetworkMetrics.empty() {
    return const NetworkMetrics();
  }
}

/// Extensions for [NetworkMetrics].
extension NetworkMetricsExtension on NetworkMetrics {
  /// Total request failure rate.
  ///
  /// Returns a value between `0.0` and `1.0`.
  double get failureRate {
    if (totalRequests == 0) {
      return 0;
    }

    return failedRequests / totalRequests;
  }

  /// Whether requests are failing frequently.
  bool get hasHighFailureRate {
    return failureRate >= 0.5;
  }

  /// Whether latency information exists.
  bool get hasLatency {
    return averageLatency != null;
  }

  /// Whether download speed information exists.
  bool get hasDownloadSpeed {
    return downloadSpeed != null;
  }

  /// Whether network is performing well.
  bool get isHealthy {
    return !hasHighFailureRate;
  }
}
