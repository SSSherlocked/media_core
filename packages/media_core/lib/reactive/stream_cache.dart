import 'dart:async';
import 'package:clock/clock.dart';

/// A lightweight in-memory cache with optional TTL.
///
/// This cache is intentionally independent from Hive or other persistent
/// storage. It is suitable for short-lived runtime data such as:
///
/// - resolved stream URLs
/// - EPG lookup results
/// - channel metadata
/// - source discovery results
/// - temporary player information
/// - API responses
///
/// Example:
/// ```dart
/// final cache = StreamCache<String>();
///
/// cache.set(
///   'channel_1',
///   'https://example.com/live.flv',
///   ttl: const Duration(minutes: 5),
/// );
///
/// final url = cache.get('channel_1');
///
/// cache.remove('channel_1');
/// cache.clear();
/// ```
class StreamCache<T> {
  /// Creates a cache whose entries expire after `defaultTtl` unless an explicit
  /// TTL is given to `set`; a `null` `defaultTtl` keeps entries forever.
  StreamCache({Duration? defaultTtl}) : _defaultTtl = defaultTtl;

  final Duration? _defaultTtl;

  final Map<String, _CacheEntry<T>> _entries = <String, _CacheEntry<T>>{};

  /// Number of currently stored entries.
  int get length {
    _removeExpired();
    return _entries.length;
  }

  /// Whether the cache contains [key] and the entry has not expired.
  bool containsKey(String key) {
    final entry = _entries[key];

    if (entry == null) {
      return false;
    }

    if (entry.isExpired) {
      _entries.remove(key);
      return false;
    }

    return true;
  }

  /// Get a cached value.
  ///
  /// Returns `null` when:
  /// - the key does not exist
  /// - the entry has expired
  T? get(String key) {
    final entry = _entries[key];

    if (entry == null) {
      return null;
    }

    if (entry.isExpired) {
      _entries.remove(key);
      return null;
    }

    return entry.value;
  }

  /// Get a cached value or create and cache it.
  ///
  /// If [loader] throws, the value is not cached and the error is propagated.
  Future<T> getOrSet(String key, FutureOr<T> Function() loader, {Duration? ttl}) async {
    final cached = get(key);

    if (cached != null) {
      return cached;
    }

    final value = await loader();

    set(key, value, ttl: ttl);

    return value;
  }

  /// Store [value] under [key].
  ///
  /// When [ttl] is omitted, the cache's `defaultTtl` is used.
  ///
  /// A `null` TTL means the entry never expires.
  void set(String key, T value, {Duration? ttl}) {
    final effectiveTtl = ttl ?? _defaultTtl;

    if (effectiveTtl != null && effectiveTtl.isNegative) {
      remove(key);
      return;
    }

    _entries[key] = _CacheEntry<T>(
      value: value,
      expiresAt: effectiveTtl == null ? null : clock.now().add(effectiveTtl),
    );
  }

  /// Remove a single cached value.
  T? remove(String key) {
    final entry = _entries.remove(key);
    return entry?.value;
  }

  /// Remove all cached values.
  void clear() {
    _entries.clear();
  }

  /// Remove expired entries.
  void removeExpired() {
    _removeExpired();
  }

  /// Return all currently valid keys.
  Iterable<String> get keys {
    _removeExpired();
    return List<String>.unmodifiable(_entries.keys);
  }

  /// Return all currently valid values.
  Iterable<T> get values {
    _removeExpired();
    return List<T>.unmodifiable(_entries.values.map((entry) => entry.value));
  }

  /// Return a snapshot of all currently valid entries.
  Map<String, T> toMap() {
    _removeExpired();

    return Map<String, T>.unmodifiable(_entries.map((key, entry) => MapEntry(key, entry.value)));
  }

  /// Dispose all cached values.
  ///
  /// This is currently equivalent to [clear], but provides a consistent
  /// lifecycle API for cache objects.
  void dispose() {
    clear();
  }

  void _removeExpired() {
    _entries.removeWhere((_, entry) => entry.isExpired);
  }
}

class _CacheEntry<T> {
  _CacheEntry({required this.value, required this.expiresAt});

  final T value;
  final DateTime? expiresAt;

  bool get isExpired {
    final expiration = expiresAt;

    if (expiration == null) {
      return false;
    }

    return clock.now().isAfter(expiration);
  }
}
