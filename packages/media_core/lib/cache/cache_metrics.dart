import 'package:equatable/equatable.dart';

/// Immutable cache metrics.
///
/// Metrics are descriptive statistics only. They do not perform cache
/// operations.
final class CacheMetrics extends Equatable {
  /// Creates a metrics snapshot; all counters start at zero by default.
  const CacheMetrics({
    this.hits = 0,
    this.misses = 0,
    this.writes = 0,
    this.removals = 0,
    this.evictions = 0,
    this.expirations = 0,
    this.bytesRead = 0,
    this.bytesWritten = 0,
  });

  /// Number of successful lookups.
  final int hits;

  /// Number of lookups that found no usable entry.
  final int misses;

  /// Number of entries written into the cache.
  final int writes;

  /// Number of entries explicitly removed.
  final int removals;

  /// Number of entries evicted by a capacity policy.
  final int evictions;

  /// Number of entries dropped because their deadline passed.
  final int expirations;

  /// Total bytes served from cache hits.
  final int bytesRead;

  /// Total bytes stored by cache writes.
  final int bytesWritten;

  /// Total number of cache lookups performed.
  int get lookups => hits + misses;

  /// Total number of cache operations, including writes and removals.
  int get operations => lookups + writes + removals;

  /// Share of lookups that were hits, or zero when no lookup happened yet.
  double get hitRate {
    final total = lookups;

    if (total == 0) {
      return 0;
    }

    return hits / total;
  }

  /// Share of lookups that missed, or zero when no lookup happened yet.
  double get missRate {
    final total = lookups;

    if (total == 0) {
      return 0;
    }

    return misses / total;
  }

  /// Returns a snapshot with one additional hit of [bytes] size.
  CacheMetrics recordHit({int bytes = 0}) {
    return copyWith(hits: hits + 1, bytesRead: bytesRead + bytes);
  }

  /// Returns a snapshot with one additional miss.
  CacheMetrics recordMiss() {
    return copyWith(misses: misses + 1);
  }

  /// Returns a snapshot with one additional write of [bytes] size.
  CacheMetrics recordWrite({int bytes = 0}) {
    return copyWith(writes: writes + 1, bytesWritten: bytesWritten + bytes);
  }

  /// Returns a snapshot with one additional explicit removal.
  CacheMetrics recordRemoval() {
    return copyWith(removals: removals + 1);
  }

  /// Returns a snapshot with one additional capacity eviction.
  CacheMetrics recordEviction() {
    return copyWith(evictions: evictions + 1);
  }

  /// Returns a snapshot with one additional expiration.
  CacheMetrics recordExpiration() {
    return copyWith(expirations: expirations + 1);
  }

  /// Returns a copy of this snapshot with the given counters replaced.
  CacheMetrics copyWith({
    int? hits,
    int? misses,
    int? writes,
    int? removals,
    int? evictions,
    int? expirations,
    int? bytesRead,
    int? bytesWritten,
  }) {
    return CacheMetrics(
      hits: hits ?? this.hits,
      misses: misses ?? this.misses,
      writes: writes ?? this.writes,
      removals: removals ?? this.removals,
      evictions: evictions ?? this.evictions,
      expirations: expirations ?? this.expirations,
      bytesRead: bytesRead ?? this.bytesRead,
      bytesWritten: bytesWritten ?? this.bytesWritten,
    );
  }

  /// Returns an all-zero snapshot, discarding every accumulated counter.
  CacheMetrics reset() {
    return const CacheMetrics();
  }

  /// Serializes the counters and derived rates into a plain map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'hits': hits,
      'misses': misses,
      'writes': writes,
      'removals': removals,
      'evictions': evictions,
      'expirations': expirations,
      'bytesRead': bytesRead,
      'bytesWritten': bytesWritten,
      'lookups': lookups,
      'hitRate': hitRate,
      'missRate': missRate,
    };
  }

  @override
  List<Object?> get props => <Object?>[hits, misses, writes, removals, evictions, expirations, bytesRead, bytesWritten];

  @override
  String toString() {
    return 'CacheMetrics('
        'hits: $hits, '
        'misses: $misses, '
        'writes: $writes, '
        'removals: $removals, '
        'evictions: $evictions, '
        'expirations: $expirations, '
        'bytesRead: $bytesRead, '
        'bytesWritten: $bytesWritten, '
        'hitRate: $hitRate'
        ')';
  }
}
