import 'package:equatable/equatable.dart';
import 'package:media_core/diagnostics/network_snapshot.dart';
import 'package:media_core/diagnostics/performance_sample.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// Represents a point-in-time diagnostic snapshot of the player.
///
/// A [PlayerDebugSnapshot] aggregates diagnostic information from multiple
/// monitoring subsystems into one immutable value.
///
/// Responsibilities:
///
/// - capture the diagnostic timestamp
/// - contain the latest memory information
/// - contain the latest network information
/// - contain collected performance samples
/// - carry additional player-specific diagnostic values
///
/// It does not:
///
/// - collect memory information
/// - measure network activity
/// - measure performance
/// - manage the lifetime of monitoring components
///
/// Those responsibilities belong to:
///
/// - MemoryMonitor
/// - NetworkMonitor
/// - PerformanceMonitor
/// - DiagnosticsManager
final class PlayerDebugSnapshot extends Equatable {
  /// Creates a diagnostic snapshot.
  const PlayerDebugSnapshot({
    required this.timestamp,
    this.memory,
    this.network,
    this.performanceSamples = const [],
    this.values = const {},
  });

  /// Time at which this snapshot was created.
  final DateTime timestamp;

  /// Latest memory snapshot available at the time of capture.
  final MemorySnapshot? memory;

  /// Latest network snapshot available at the time of capture.
  final NetworkSnapshot? network;

  /// Performance samples retained by the performance monitor.
  final List<PerformanceSample> performanceSamples;

  /// Additional diagnostic values supplied by the caller.
  ///
  /// This map is intentionally generic so higher-level player components can
  /// include diagnostic state without introducing player-specific fields into
  /// the diagnostics module.
  final Map<String, Object?> values;

  /// Whether this snapshot contains memory information.
  bool get hasMemory {
    return memory != null;
  }

  /// Whether this snapshot contains network information.
  bool get hasNetwork {
    return network != null;
  }

  /// Whether this snapshot contains performance information.
  bool get hasPerformance {
    return performanceSamples.isNotEmpty;
  }

  /// Converts this snapshot into a serializable map.
  Map<String, Object?> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'memory': memory?.toMap(),
      'network': network?.toMap(),
      'performanceSamples': performanceSamples.map((sample) => sample.toMap()).toList(growable: false),
      'values': values,
    };
  }

  @override
  List<Object?> get props => [timestamp, memory, network, performanceSamples, values];

  @override
  String toString() {
    return 'PlayerDebugSnapshot('
        'timestamp: $timestamp, '
        'hasMemory: $hasMemory, '
        'hasNetwork: $hasNetwork, '
        'performanceSamples: ${performanceSamples.length}, '
        'values: $values'
        ')';
  }
}
