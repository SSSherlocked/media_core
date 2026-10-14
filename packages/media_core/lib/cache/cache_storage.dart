import 'package:media_core/cache/cache_entry.dart';
import 'package:media_core/cache/cache_key.dart';
import 'package:media_core/cache/cache_manager.dart' show CacheManager;

/// Abstract cache storage.
///
/// Storage defines the persistence boundary used by [CacheManager].
///
/// Implementations can provide:
///
/// - memory storage
/// - disk storage
/// - platform storage
/// - test storage
///
/// Storage does not decide eviction policy.
abstract interface class CacheStorage<T> {
  const CacheStorage();

  /// Initializes the storage.
  Future<void> initialize();

  /// Reads an entry.
  ///
  /// Returns `null` when the key does not exist.
  Future<CacheEntry<T>?> read(CacheKey key);

  /// Writes an entry.
  Future<void> write(CacheEntry<T> entry);

  /// Removes one entry.
  Future<bool> remove(CacheKey key);

  /// Removes all entries.
  Future<void> clear();

  /// Returns whether the key exists.
  Future<bool> contains(CacheKey key);

  /// Returns all stored entries.
  ///
  /// This is primarily used by cache management and diagnostics. Storage
  /// implementations may optimize this operation internally.
  Future<List<CacheEntry<T>>> entries();

  /// Releases storage resources.
  Future<void> dispose();
}
