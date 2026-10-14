import 'package:flutter/foundation.dart';

/// Identifies a logical resource used for concurrency coordination.
///
/// The key is intentionally domain-agnostic. Higher-level modules decide
/// which scopes and resource identifiers they need.
@immutable
final class ConcurrencyKey {
  /// Creates a key for the resource [name] inside the [scope] bucket.
  const ConcurrencyKey({required this.scope, required this.name});

  /// Concurrency bucket the resource belongs to, for example `decoder`.
  final String scope;

  /// Identifier of the resource inside [scope].
  final String name;

  /// Canonical `scope:name` form used for diagnostics and as a map key.
  String get value => '$scope:$name';

  /// Whether the key belongs to [scope].
  bool hasScope(String scope) => this.scope == scope;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is ConcurrencyKey && other.scope == scope && other.name == name;
  }

  @override
  int get hashCode => Object.hash(scope, name);

  @override
  String toString() => 'ConcurrencyKey($value)';
}
