import 'package:equatable/equatable.dart';
import 'package:media_core/cache/cache_entry.dart';

/// Result of a cache lookup.
///
/// A lookup can distinguish a normal miss from an expired entry. This allows
/// the cache manager to maintain accurate metrics without exposing storage
/// implementation details.
sealed class CacheResult<T> extends Equatable {
  const CacheResult();

  const factory CacheResult.hit(CacheEntry<T> entry) = CacheHit<T>;

  const factory CacheResult.miss() = CacheMiss<T>;

  const factory CacheResult.expired(CacheEntry<T> entry) = CacheExpired<T>;

  /// Whether the lookup returned a usable entry.
  bool get isHit => this is CacheHit<T>;

  /// Whether the lookup found no entry at all.
  bool get isMiss => this is CacheMiss<T>;

  /// Whether the lookup found an entry that is no longer valid.
  bool get isExpired => this is CacheExpired<T>;

  /// The entry carried by a hit or expired result, or null on a miss.
  CacheEntry<T>? get entry {
    final result = this;

    if (result is CacheHit<T>) {
      return result.entry;
    }

    if (result is CacheExpired<T>) {
      return result.entry;
    }

    return null;
  }

  @override
  List<Object?> get props => <Object?>[];
}

/// Cache hit.
final class CacheHit<T> extends CacheResult<T> {
  /// Creates a hit carrying the usable [entry].
  const CacheHit(this.entry);

  @override
  final CacheEntry<T> entry;

  @override
  List<Object?> get props => <Object?>[entry];

  @override
  String toString() => 'CacheHit($entry)';
}

/// Cache miss.
final class CacheMiss<T> extends CacheResult<T> {
  /// Creates a miss result; there is no entry to carry.
  const CacheMiss();

  @override
  String toString() => 'CacheMiss';
}

/// Cache entry exists but has expired.
final class CacheExpired<T> extends CacheResult<T> {
  /// Creates an expired result carrying the stale [entry].
  const CacheExpired(this.entry);

  @override
  final CacheEntry<T> entry;

  @override
  List<Object?> get props => <Object?>[entry];

  @override
  String toString() => 'CacheExpired($entry)';
}
