import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/resource/resource_metrics.dart';
import 'package:media_core/resource/resource_pressure.dart';
import 'package:media_core/resource/resource_state.dart';

/// Immutable snapshot of resource runtime state.
///
/// [ResourceSnapshot] provides a stable read-only
/// representation of the resource subsystem at
/// a specific point in time.
///
/// It is designed for:
///
/// - external observers
/// - debugging tools
/// - telemetry systems
/// - UI state binding
/// - performance monitoring
///
/// It does not:
///
/// - update resources
/// - trigger cleanup
/// - allocate resources
/// - release resources
///
/// Those responsibilities belong to:
///
/// - ResourceManager
/// - MemoryManager
/// - DecoderManager
/// - BandwidthManager
///
/// Snapshot flow:
///
/// ```text
/// ResourceManager
///        |
///        v
/// ResourceSnapshot
///        |
///        +--> UI
///        +--> Debug tools
///        +--> Metrics
/// ```
final class ResourceSnapshot extends Equatable {
  /// Creates resource snapshot.
  const ResourceSnapshot({required this.state, required this.createdAt});

  /// Creates an empty snapshot.
  factory ResourceSnapshot.empty() {
    return ResourceSnapshot.fromState(ResourceState.initial);
  }

  /// Creates snapshot from state.
  factory ResourceSnapshot.fromState(ResourceState state) {
    return ResourceSnapshot(state: state, createdAt: clock.now());
  }

  /// Resource runtime state.
  final ResourceState state;

  /// Snapshot creation time.
  final DateTime createdAt;

  /// Current resource metrics.
  ResourceMetrics get metrics {
    return state.metrics;
  }

  /// Current resource pressure.
  ResourcePressure get pressure {
    return state.pressure;
  }

  /// Whether resource pressure exists.
  bool get hasPressure {
    return pressure.hasPressure;
  }

  /// Whether emergency handling is required.
  bool get isEmergency {
    return pressure == ResourcePressure.emergency;
  }

  /// Whether system is degraded.
  bool get isDegraded {
    return state.degraded;
  }

  /// Whether resources are being released.
  bool get isReleasing {
    return state.releasing;
  }

  /// Number of active decoders.
  int get decoderCount {
    return metrics.decoderCount;
  }

  /// Current memory usage.
  int get memoryBytes {
    return metrics.memoryBytes;
  }

  /// Current bandwidth usage.
  double get bandwidthMbps {
    return metrics.bandwidthMbps;
  }

  /// Creates modified snapshot.
  ResourceSnapshot copyWith({ResourceState? state, DateTime? createdAt}) {
    return ResourceSnapshot(state: state ?? this.state, createdAt: createdAt ?? this.createdAt);
  }

  /// Returns whether two snapshots
  /// have the same pressure level.
  bool samePressure(ResourceSnapshot other) {
    return pressure == other.pressure;
  }

  /// Returns whether resource usage changed.
  bool usageChanged(ResourceSnapshot other) {
    return metrics != other.metrics;
  }

  @override
  List<Object?> get props => [state, createdAt];

  @override
  String toString() {
    return 'ResourceSnapshot('
        'pressure=$pressure, '
        'degraded=$isDegraded, '
        'releasing=$isReleasing, '
        'metrics=$metrics'
        ')';
  }
}
