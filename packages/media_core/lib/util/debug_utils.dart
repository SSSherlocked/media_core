import 'dart:developer' as developer;

/// Debug related utilities.
abstract final class DebugUtils {
  DebugUtils._();

  /// Whether assertions are enabled.
  static bool get isDebug {
    var result = false;

    assert(() {
      result = true;
      return true;
    }(), 'isDebug probe: this callback must return true so assertions stay enabled.');

    return result;
  }

  /// Prints debug message.
  static void log(Object? message, {String name = 'media_core'}) {
    developer.log('$message', name: name);
  }

  /// Prints error message.
  static void error(Object error, StackTrace stackTrace, {String name = 'media_core'}) {
    developer.log('Error: $error', name: name, error: error, stackTrace: stackTrace, level: 1000);
  }

  /// Executes callback only in debug mode.
  static void debugOnly(void Function() callback) {
    if (isDebug) {
      callback();
    }
  }

  /// Checks condition in debug mode.
  static void assertDebug({required bool condition, required String message}) {
    assert(condition, message);
  }

  /// Measures synchronous execution time.
  static T measure<T>(String name, T Function() action) {
    final stopwatch = Stopwatch()..start();

    try {
      return action();
    } finally {
      stopwatch.stop();

      log(
        '$name completed in '
        '${stopwatch.elapsedMilliseconds}ms',
      );
    }
  }

  /// Measures asynchronous execution time.
  static Future<T> measureAsync<T>(String name, Future<T> Function() action) async {
    final stopwatch = Stopwatch()..start();

    try {
      return await action();
    } finally {
      stopwatch.stop();

      log(
        '$name completed in '
        '${stopwatch.elapsedMilliseconds}ms',
      );
    }
  }

  /// Creates debug description.
  static String describe(Object? value) {
    if (value == null) {
      return 'null';
    }

    return '${value.runtimeType}: $value';
  }

  /// Returns identity description.
  static String identity(Object object) {
    return '${object.runtimeType}'
        '@${identityHashCode(object)}';
  }
}
