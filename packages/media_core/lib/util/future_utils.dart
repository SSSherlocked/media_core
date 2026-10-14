import 'dart:async';

import 'package:media_core/result/result.dart' show Result;

/// Future related utilities.
abstract final class FutureUtils {
  FutureUtils._();

  /// Creates a delayed future.
  static Future<void> delay(Duration duration) {
    return Future<void>.delayed(duration);
  }

  /// Executes [action] after [duration].
  static Future<T> delayed<T>(Duration duration, FutureOr<T> Function() action) {
    return Future<T>.delayed(duration, action);
  }

  /// Runs [action] and returns null when it throws.
  static Future<T?> tryExecute<T>(
    Future<T> Function() action, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);

      return null;
    }
  }

  /// Runs [action] and converts error to [Result].
  static Future<T?> catchError<T>(Future<T> Function() action) {
    return tryExecute(action);
  }

  /// Waits until all futures complete.
  static Future<List<T>> wait<T>(Iterable<Future<T>> futures) {
    return Future.wait(futures);
  }

  /// Runs futures sequentially.
  ///
  /// Results keep the same order.
  static Future<List<T>> sequence<T>(Iterable<Future<T> Function()> tasks) async {
    final result = <T>[];

    for (final task in tasks) {
      result.add(await task());
    }

    return result;
  }

  /// Runs futures in parallel.
  static Future<List<T>> parallel<T>(Iterable<Future<T> Function()> tasks) {
    return Future.wait(tasks.map((task) => task()));
  }

  /// Returns the first successful future.
  ///
  /// Throws the last error when all fail.
  static Future<T> firstSuccess<T>(Iterable<Future<T> Function()> tasks) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (final task in tasks) {
      try {
        return await task();
      } on Object catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }

    if (lastError != null && lastStackTrace != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace);
    }

    throw StateError('No tasks provided');
  }

  /// Adds timeout to a future.
  static Future<T> timeout<T>(Future<T> future, Duration duration, {FutureOr<T> Function()? onTimeout}) {
    return future.timeout(duration, onTimeout: onTimeout);
  }

  /// Ignores future errors.
  static Future<void> ignore(Future<void> future) async {
    try {
      await future;
    } on Object catch (_) {}
  }

  /// Converts `Future<T>` into `Future<void>`.
  static Future<void> discard<T>(Future<T> future) async {
    await future;
  }

  /// Runs [action] only once.
  ///
  /// Concurrent callers share the same Future.
  static Future<T> Function() memoize<T>(Future<T> Function() action) {
    Future<T>? cache;

    return () {
      return cache ??= action();
    };
  }

  /// Creates a completer.
  static Completer<T> completer<T>() {
    return Completer<T>();
  }

  /// Returns whether future completed successfully.
  static Future<bool> succeeds<T>(Future<T> future) async {
    try {
      await future;
      return true;
    } on Object catch (_) {
      return false;
    }
  }

  /// Returns whether future completed with error.
  static Future<bool> fails<T>(Future<T> future) async {
    try {
      await future;
      return false;
    } on Object catch (_) {
      return true;
    }
  }

  /// Runs [action] without awaiting result.
  ///
  /// Errors are swallowed.
  static void fireAndForget(Future<void> Function() action) {
    unawaited(ignore(action()));
  }
}
