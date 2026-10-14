import 'dart:async';

/// Attaches fields to every record logged inside `body`.
///
/// The problem it solves is the one that makes player logs hard to read: the
/// interesting events come from four layers (session, playback, adapter,
/// goroutine-ish callbacks) and only the caller knows which room they belong to.
/// Passing `roomId` through every layer is noise; putting it in scope makes every
/// line inside carry it.
///
/// ```dart
/// LogScope.run({'roomId': room.id, 'engine': 'media_kit'}, () async {
///   await player.open(source);   // every record here is tagged
/// });
/// ```
///
/// Nested scopes merge, inner winning on conflicts. Values are captured at scope
/// entry, not read later.
abstract final class LogScope {
  static const String _key = 'media_core_log_scope';

  /// Fields attached to the current scope, or an empty map outside one.
  static Map<String, Object?> get fields {
    final value = Zone.current[_key];
    return value is Map<String, Object?> ? value : const <String, Object?>{};
  }

  /// Whether a scope is active.
  static bool get isActive => Zone.current[_key] != null;

  /// Runs [body] with [fields] in scope.
  static R run<R>(Map<String, Object?> fields, R Function() body) {
    if (fields.isEmpty) {
      return body();
    }
    return runZoned(
      body,
      zoneValues: <Object, Object?>{
        _key: <String, Object?>{...LogScope.fields, ...fields},
      },
    );
  }

  /// Runs [body] with [fields] in scope, awaiting its result.
  static Future<R> runAsync<R>(Map<String, Object?> fields, Future<R> Function() body) {
    if (fields.isEmpty) {
      return body();
    }
    return runZoned(
      body,
      zoneValues: <Object, Object?>{
        _key: <String, Object?>{...LogScope.fields, ...fields},
      },
    );
  }
}
