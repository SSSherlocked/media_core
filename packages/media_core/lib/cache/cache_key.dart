import 'package:equatable/equatable.dart';

/// Immutable cache key.
///
/// Cache keys are intentionally represented as a dedicated value object
/// instead of passing raw strings throughout the cache subsystem.
///
/// A key identifies one logical cache entry. It does not describe how the
/// entry is stored or when it should be evicted.
final class CacheKey extends Equatable {
  /// Creates a cache key from [value].
  ///
  /// The empty string is rejected because it would let unrelated entries
  /// collide on one key.
  const CacheKey(this.value) : assert(value != '', 'Cache key must not be empty.');

  /// The raw key string this value object wraps.
  final String value;

  /// Whether the key string is empty; only reachable in release builds where
  /// the constructor assert is skipped.
  bool get isEmpty => value.isEmpty;

  /// Whether the key string carries an identity.
  bool get isNotEmpty => value.isNotEmpty;

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}
