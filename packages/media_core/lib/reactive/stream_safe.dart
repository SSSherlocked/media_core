import 'dart:async';

/// Result of a safe asynchronous operation.
class StreamSafeResult<T> {
  /// Builds the success shape; [error] and [stackTrace] are always `null`.
  const StreamSafeResult.success(this.value) : error = null, stackTrace = null;

  /// Builds the failure shape carrying [error] and where it came from.
  const StreamSafeResult.failure(this.error, [this.stackTrace]) : value = null;

  /// Produced value, or `null` when the operation failed.
  final T? value;

  /// Error the operation threw, or `null` when it succeeded.
  final Object? error;

  /// Stack trace captured where [error] was thrown.
  final StackTrace? stackTrace;

  /// Whether the operation completed without an error.
  bool get isSuccess => error == null;

  /// Whether the operation ended in a failure.
  bool get isError => error != null;

  /// The produced value.
  ///
  /// Throws the recorded error instead of handing back `null`, so callers that
  /// cannot continue without a value can read [requireValue] directly.
  T get requireValue {
    if (error != null) {
      Error.throwWithStackTrace(error!, stackTrace ?? StackTrace.current);
    }

    return value as T;
  }

  /// The produced value or `null`, without ever throwing.
  T? get valueOrNull => value;
}

/// Safe asynchronous helpers.
abstract final class StreamSafe {
  /// Executes [action] and converts exceptions into [StreamSafeResult].
  static Future<StreamSafeResult<T>> run<T>(Future<T> Function() action) async {
    try {
      final value = await action();
      return StreamSafeResult<T>.success(value);
    } on Object catch (error, stackTrace) {
      return StreamSafeResult<T>.failure(error, stackTrace);
    }
  }

  /// Executes [action] and returns [fallback] when it fails.
  static Future<T> withFallback<T>(Future<T> Function() action, T fallback) async {
    try {
      return await action();
    } on Object catch (_) {
      return fallback;
    }
  }

  /// Executes [action] and returns null when it fails.
  static Future<T?> tryRun<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (_) {
      return null;
    }
  }

  /// Executes [action] and invokes [onError] when it fails.
  ///
  /// The original exception is rethrown.
  static Future<T> runAndReport<T>(
    Future<T> Function() action, {
    FutureOr<void> Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      await onError?.call(error, stackTrace);

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Executes [action] and converts any error using [convertError].
  static Future<T> mapError<T>(
    Future<T> Function() action, {
    required Object Function(Object error, StackTrace stackTrace) convertError,
  }) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      final converted = convertError(error, stackTrace);

      Error.throwWithStackTrace(converted, stackTrace);
    }
  }

  /// Executes [action] and ignores any error.
  static Future<void> ignore(FutureOr<void> Function() action) async {
    try {
      await action();
    } on Object catch (_) {
      // Intentionally ignored.
    }
  }

  /// Executes [action] and logs the error.
  static Future<void> ignoreWithReport(
    FutureOr<void> Function() action, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  /// Executes [action] only when [condition] is true.
  static Future<T?> when<T>({required bool condition, required Future<T> Function() action}) {
    if (!condition) {
      return Future<T?>.value();
    }

    return action();
  }

  /// Executes [action] only when [condition] is true.
  ///
  /// Errors are converted into null.
  static Future<T?> tryWhen<T>({required bool condition, required Future<T> Function() action}) {
    if (!condition) {
      return Future<T?>.value();
    }

    return tryRun(action);
  }

  /// Executes [action] and returns [fallback] when the operation
  /// exceeds [timeout].
  static Future<T> withTimeout<T>(Future<T> Function() action, {required Duration timeout, required T fallback}) async {
    try {
      return await action().timeout(timeout);
    } on TimeoutException {
      return fallback;
    } on Object catch (_) {
      return fallback;
    }
  }

  /// Executes [action] with a timeout and returns null on failure.
  static Future<T?> tryWithTimeout<T>(Future<T> Function() action, {required Duration timeout}) async {
    try {
      return await action().timeout(timeout);
    } on Object catch (_) {
      return null;
    }
  }

  /// Converts a Future into a safe result.
  static Future<StreamSafeResult<T>> result<T>(Future<T> future) async {
    try {
      return StreamSafeResult<T>.success(await future);
    } on Object catch (error, stackTrace) {
      return StreamSafeResult<T>.failure(error, stackTrace);
    }
  }
}

/// Utility for executing synchronous code safely.
abstract final class StreamSafeSync {
  /// Executes [action] and converts exceptions into a result.
  static StreamSafeResult<T> run<T>(T Function() action) {
    try {
      return StreamSafeResult<T>.success(action());
    } on Object catch (error, stackTrace) {
      return StreamSafeResult<T>.failure(error, stackTrace);
    }
  }

  /// Executes [action] and returns [fallback] on error.
  static T withFallback<T>(T Function() action, T fallback) {
    try {
      return action();
    } on Object catch (_) {
      return fallback;
    }
  }

  /// Executes [action] and returns null on error.
  static T? tryRun<T>(T Function() action) {
    try {
      return action();
    } on Object catch (_) {
      return null;
    }
  }
}

/// A typed exception wrapper.
///
/// Useful when a lower-level exception needs to be given additional context.
class StreamWrappedException implements Exception {
  /// Adds [message] and [stackTrace] around the underlying [cause].
  StreamWrappedException({required this.message, required this.cause, this.stackTrace});

  /// Context describing what the caller was trying to do.
  final String message;

  /// Exception this wrapper replaced; kept so the origin is not lost.
  final Object cause;

  /// Trace of the wrapped failure, when the caller had one.
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'StreamWrappedException: $message '
        '(cause: $cause)';
  }
}
