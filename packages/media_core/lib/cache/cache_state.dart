import 'package:equatable/equatable.dart';
import 'package:media_core/cache/cache_metrics.dart';

/// Immutable cache state.
///
/// Tracks cache lifecycle and aggregate cache statistics.
///
/// This state does not contain individual cache entries.
final class CacheState extends Equatable {
  /// Creates a state snapshot with explicit lifecycle and metric values.
  const CacheState({required this.initialized, required this.size, required this.sizeBytes, required this.metrics});

  /// Creates the pre-initialization state with empty counters.
  const CacheState.initial() : initialized = false, size = 0, sizeBytes = 0, metrics = const CacheMetrics();

  /// Whether the owning cache has completed initialization.
  final bool initialized;

  /// Number of entries currently in the cache.
  final int size;

  /// Total size in bytes of the entries currently in the cache.
  final int sizeBytes;

  /// Aggregate statistics accumulated by the cache.
  final CacheMetrics metrics;

  /// Whether the cache holds no entries.
  bool get isEmpty => size == 0;

  /// Whether the cache holds at least one entry.
  bool get isNotEmpty => size > 0;

  /// Returns the initialized counterpart of this state with the given values.
  CacheState initialize({int size = 0, int sizeBytes = 0, CacheMetrics metrics = const CacheMetrics()}) {
    return CacheState(initialized: true, size: size, sizeBytes: sizeBytes, metrics: metrics);
  }

  /// Returns a copy of this state with the given fields replaced.
  CacheState update({int? size, int? sizeBytes, CacheMetrics? metrics}) {
    return CacheState(
      initialized: initialized,
      size: size ?? this.size,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      metrics: metrics ?? this.metrics,
    );
  }

  /// Returns the initial state, discarding initialization and counters.
  CacheState reset() {
    return const CacheState.initial();
  }

  /// Serializes the state into a plain map for logging or diagnostics.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'initialized': initialized,
      'size': size,
      'sizeBytes': sizeBytes,
      'metrics': metrics.toMap(),
    };
  }

  @override
  List<Object?> get props => <Object?>[initialized, size, sizeBytes, metrics];

  @override
  String toString() {
    return 'CacheState('
        'initialized: $initialized, '
        'size: $size, '
        'sizeBytes: $sizeBytes, '
        'metrics: $metrics'
        ')';
  }
}
