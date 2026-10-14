import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/cache/cache_key.dart';

/// Immutable cache entry.
///
/// A cache entry contains the cached value and metadata required by cache
/// management policies.
///
/// The cache entry does not know where it is stored. The same entry can be
/// used by memory or disk storage.
final class CacheEntry<T> extends Equatable {
  /// Creates a cache entry for [value] under [key].
  ///
  /// [createdAt] and [accessedAt] default to the current time so callers can
  /// omit them when storing a fresh entry.
  CacheEntry({
    required this.key,
    required this.value,
    DateTime? createdAt,
    DateTime? accessedAt,
    this.expiresAt,
    this.sizeBytes = 0,
    this.metadata = const <String, Object?>{},
  }) : createdAt = createdAt ?? clock.now(),
       accessedAt = accessedAt ?? createdAt ?? clock.now();

  /// Key this entry is stored under.
  final CacheKey key;

  /// The cached value.
  final T value;

  /// Moment the entry was first created.
  final DateTime createdAt;

  /// Moment the entry was last read or touched.
  final DateTime accessedAt;

  /// Moment after which the entry is no longer valid, if it expires at all.
  final DateTime? expiresAt;

  /// Size of the value in bytes, used by byte-bounded eviction policies.
  final int sizeBytes;

  /// Free-form policy metadata attached to this entry.
  final Map<String, Object?> metadata;

  /// Whether the entry carries an expiration deadline.
  bool get hasExpiration => expiresAt != null;

  /// Whether the entry's expiration deadline has already passed.
  bool get isExpired {
    final expiration = expiresAt;

    if (expiration == null) {
      return false;
    }

    return !clock.now().isBefore(expiration);
  }

  /// Whether the entry may still be served from the cache.
  bool get isValid => !isExpired;

  /// How long ago the entry was created.
  Duration get age => clock.now().difference(createdAt);

  /// How long the entry has gone unaccessed.
  Duration get idleDuration => clock.now().difference(accessedAt);

  /// Returns a copy of this entry with a refreshed access time.
  CacheEntry<T> touch({DateTime? accessedAt}) {
    return CacheEntry<T>(
      key: key,
      value: value,
      createdAt: createdAt,
      accessedAt: accessedAt ?? clock.now(),
      expiresAt: expiresAt,
      sizeBytes: sizeBytes,
      metadata: metadata,
    );
  }

  /// Returns a copy of this entry with the given fields replaced.
  CacheEntry<T> copyWith({
    CacheKey? key,
    T? value,
    DateTime? createdAt,
    DateTime? accessedAt,
    DateTime? expiresAt,
    int? sizeBytes,
    Map<String, Object?>? metadata,
  }) {
    return CacheEntry<T>(
      key: key ?? this.key,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
      accessedAt: accessedAt ?? this.accessedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Serializes the entry for disk storage.
  ///
  /// [valueEncoder] converts the typed value into a JSON-compatible form;
  /// without it the raw value is stored as-is.
  Map<String, dynamic> toMap({Object? Function(T value)? valueEncoder}) {
    return <String, dynamic>{
      'key': key.value,
      'value': valueEncoder?.call(value) ?? value,
      'createdAt': createdAt.toIso8601String(),
      'accessedAt': accessedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'sizeBytes': sizeBytes,
      'metadata': Map<String, dynamic>.from(metadata),
    };
  }

  @override
  List<Object?> get props => <Object?>[key, value, createdAt, accessedAt, expiresAt, sizeBytes, metadata];

  @override
  String toString() {
    return 'CacheEntry('
        'key: $key, '
        'createdAt: $createdAt, '
        'accessedAt: $accessedAt, '
        'expiresAt: $expiresAt, '
        'sizeBytes: $sizeBytes, '
        'metadata: $metadata'
        ')';
  }
}
