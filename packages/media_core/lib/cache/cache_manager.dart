import 'package:clock/clock.dart';
import 'package:media_core/cache/cache_entry.dart';
import 'package:media_core/cache/cache_key.dart';
import 'package:media_core/cache/cache_metrics.dart';
import 'package:media_core/cache/cache_result.dart';
import 'package:media_core/cache/cache_state.dart';
import 'package:media_core/cache/cache_storage.dart';
import 'package:media_core/cache/memory_cache.dart';

/// Coordinates cache storage and cache lifecycle.
///
/// [CacheManager] provides the high-level cache API while delegating actual
/// storage to [CacheStorage] implementations.
///
/// When a [MemoryCache] is supplied as the memory layer, the manager can use
/// it as a fast first-level cache and optionally fall back to a persistent
/// storage implementation.
///
/// Typical hierarchy:
///
/// ```text
/// CacheManager
///      │
///      ├── MemoryCache
///      │
///      └── DiskCache / other CacheStorage
/// ```
///
/// The manager owns cache policy at the orchestration level but does not
/// implement a specific disk format.
final class CacheManager<T> {
  /// Creates a manager over an optional memory layer and persistent [storage].
  CacheManager({CacheStorage<T>? storage, MemoryCache<T>? memory}) : _storage = storage, _memory = memory;

  final CacheStorage<T>? _storage;

  final MemoryCache<T>? _memory;

  CacheState _state = const CacheState.initial();

  bool _disposed = false;

  /// Current lifecycle state of the manager.
  CacheState get state => _state;

  /// Metrics snapshot carried by the current state.
  CacheMetrics get metrics => _state.metrics;

  /// Whether the manager has completed initialization.
  bool get initialized => _state.initialized;

  /// Number of entries currently tracked across the active layers.
  int get size => _state.size;

  /// Total size in bytes currently tracked across the active layers.
  int get sizeBytes => _state.sizeBytes;

  /// Initializes all configured storage layers.
  Future<void> initialize() async {
    _ensureNotDisposed();

    if (_state.initialized) {
      return;
    }

    if (_memory != null) {
      await _memory.initialize();
    }

    if (_storage != null) {
      await _storage.initialize();
    }

    await _refreshState(metrics: _state.metrics);
  }

  /// Reads an entry.
  ///
  /// Memory storage is checked first. On a memory miss, persistent storage is
  /// queried and a successful result is promoted into memory.
  Future<CacheResult<T>> get(CacheKey key) async {
    _ensureReady();

    if (_memory != null) {
      final memoryEntry = await _memory.read(key);

      if (memoryEntry != null) {
        _state = _state.update(metrics: _state.metrics.recordHit(bytes: memoryEntry.sizeBytes));

        await _refreshState(metrics: _state.metrics);

        return CacheResult<T>.hit(memoryEntry);
      }
    }

    if (_storage != null) {
      final storedEntry = await _storage.read(key);

      if (storedEntry != null) {
        if (storedEntry.isExpired) {
          _state = _state.update(metrics: _state.metrics.recordExpiration());

          await _refreshState(metrics: _state.metrics);

          return CacheResult<T>.expired(storedEntry);
        }

        final touched = storedEntry.touch();

        if (_memory != null) {
          await _memory.write(touched);
        }

        _state = _state.update(metrics: _state.metrics.recordHit(bytes: touched.sizeBytes));

        await _refreshState(metrics: _state.metrics);

        return CacheResult<T>.hit(touched);
      }
    }

    _state = _state.update(metrics: _state.metrics.recordMiss());

    await _refreshState(metrics: _state.metrics);

    return CacheResult<T>.miss();
  }

  /// Writes a value into the configured cache layers.
  Future<void> put(
    CacheKey key,
    T value, {
    Duration? ttl,
    int sizeBytes = 0,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    _ensureReady();

    final now = clock.now();

    final entry = CacheEntry<T>(
      key: key,
      value: value,
      createdAt: now,
      accessedAt: now,
      expiresAt: ttl == null ? null : now.add(ttl),
      sizeBytes: sizeBytes,
      metadata: metadata,
    );

    await _writeEntry(entry);
  }

  /// Writes an already constructed cache entry.
  Future<void> putEntry(CacheEntry<T> entry) async {
    _ensureReady();

    await _writeEntry(entry);
  }

  /// Removes one cache entry.
  Future<bool> remove(CacheKey key) async {
    _ensureReady();

    var removed = false;

    if (_memory != null) {
      removed = await _memory.remove(key) || removed;
    }

    if (_storage != null) {
      removed = await _storage.remove(key) || removed;
    }

    if (removed) {
      _state = _state.update(metrics: _state.metrics.recordRemoval());
    }

    await _refreshState(metrics: _state.metrics);

    return removed;
  }

  /// Clears all cache layers.
  Future<void> clear() async {
    _ensureReady();

    if (_memory != null) {
      await _memory.clear();
    }

    if (_storage != null) {
      await _storage.clear();
    }

    await _refreshState(metrics: _state.metrics);
  }

  /// Returns whether a key exists in any configured cache layer.
  Future<bool> contains(CacheKey key) async {
    _ensureReady();

    if (_memory != null && await _memory.contains(key)) {
      return true;
    }

    if (_storage != null && await _storage.contains(key)) {
      return true;
    }

    return false;
  }

  /// Removes expired entries from configured storage layers.
  Future<int> removeExpired() async {
    _ensureReady();

    var removed = 0;

    if (_memory != null) {
      final entries = await _memory.entries();

      for (final entry in entries) {
        if (entry.isExpired) {
          if (await _memory.remove(entry.key)) {
            removed++;
          }
        }
      }
    }

    if (_storage != null) {
      final entries = await _storage.entries();

      for (final entry in entries) {
        if (entry.isExpired) {
          if (await _storage.remove(entry.key)) {
            removed++;
          }
        }
      }
    }

    if (removed > 0) {
      var metrics = _state.metrics;

      for (var i = 0; i < removed; i++) {
        metrics = metrics.recordExpiration();
      }

      _state = _state.update(metrics: metrics);
    }

    await _refreshState(metrics: _state.metrics);

    return removed;
  }

  /// Returns all entries from the primary storage.
  Future<List<CacheEntry<T>>> entries() async {
    _ensureReady();

    if (_storage != null) {
      return await _storage.entries();
    }

    if (_memory != null) {
      return await _memory.entries();
    }

    return <CacheEntry<T>>[];
  }

  /// Releases all configured storage layers.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    if (_memory != null) {
      await _memory.dispose();
    }

    if (_storage != null) {
      await _storage.dispose();
    }
  }

  Future<void> _writeEntry(CacheEntry<T> entry) async {
    if (_memory != null) {
      await _memory.write(entry);
    }

    if (_storage != null) {
      await _storage.write(entry);
    }

    _state = _state.update(metrics: _state.metrics.recordWrite(bytes: entry.sizeBytes));

    await _refreshState(metrics: _state.metrics);
  }

  Future<void> _refreshState({required CacheMetrics metrics}) async {
    var size = 0;
    var sizeBytes = 0;

    if (_memory != null) {
      size += _memory.length;
      sizeBytes += _memory.sizeBytes;
    } else if (_storage != null) {
      final entries = await _storage.entries();

      size = entries.length;
      sizeBytes = entries.fold<int>(0, (total, entry) => total + entry.sizeBytes);
    }

    _state = _state.update(size: size, sizeBytes: sizeBytes, metrics: metrics);

    if (!_state.initialized) {
      _state = _state.initialize(size: size, sizeBytes: sizeBytes, metrics: metrics);
    }
  }

  void _ensureReady() {
    _ensureNotDisposed();

    if (!_state.initialized) {
      throw StateError('CacheManager has not been initialized.');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('CacheManager has been disposed.');
    }
  }
}
