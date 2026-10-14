import 'package:media_core/cache/cache_entry.dart';

/// Cache eviction policy.
///
/// Eviction is responsible only for deciding which entries should be removed
/// when a cache exceeds its configured limits.
abstract interface class CacheEviction<T> {
  const CacheEviction();

  /// Returns entries that should be evicted.
  ///
  /// The returned entries must be a subset of [entries].
  List<CacheEntry<T>> select(List<CacheEntry<T>> entries, {required int maxEntries, required int maxBytes});
}

/// Least-recently-used eviction policy.
///
/// Entries that have not been accessed for the longest time are removed
/// first.
final class LruCacheEviction<T> implements CacheEviction<T> {
  /// Creates a least-recently-used eviction policy.
  const LruCacheEviction();

  @override
  List<CacheEntry<T>> select(List<CacheEntry<T>> entries, {required int maxEntries, required int maxBytes}) {
    if (entries.isEmpty) {
      return <CacheEntry<T>>[];
    }

    final sorted = List<CacheEntry<T>>.from(entries)..sort((a, b) => a.accessedAt.compareTo(b.accessedAt));

    final evicted = <CacheEntry<T>>[];
    var remainingEntries = entries.length;
    var remainingBytes = entries.fold<int>(0, (total, entry) => total + entry.sizeBytes);

    for (final entry in sorted) {
      final exceedsEntries = maxEntries > 0 && remainingEntries > maxEntries;
      final exceedsBytes = maxBytes > 0 && remainingBytes > maxBytes;

      if (!exceedsEntries && !exceedsBytes) {
        break;
      }

      evicted.add(entry);
      remainingEntries--;
      remainingBytes -= entry.sizeBytes;
    }

    return evicted;
  }
}

/// FIFO eviction policy.
///
/// Entries created earliest are removed first.
final class FifoCacheEviction<T> implements CacheEviction<T> {
  /// Creates a first-in-first-out eviction policy.
  const FifoCacheEviction();

  @override
  List<CacheEntry<T>> select(List<CacheEntry<T>> entries, {required int maxEntries, required int maxBytes}) {
    if (entries.isEmpty) {
      return <CacheEntry<T>>[];
    }

    final sorted = List<CacheEntry<T>>.from(entries)..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final evicted = <CacheEntry<T>>[];
    var remainingEntries = entries.length;
    var remainingBytes = entries.fold<int>(0, (total, entry) => total + entry.sizeBytes);

    for (final entry in sorted) {
      final exceedsEntries = maxEntries > 0 && remainingEntries > maxEntries;
      final exceedsBytes = maxBytes > 0 && remainingBytes > maxBytes;

      if (!exceedsEntries && !exceedsBytes) {
        break;
      }

      evicted.add(entry);
      remainingEntries--;
      remainingBytes -= entry.sizeBytes;
    }

    return evicted;
  }
}
