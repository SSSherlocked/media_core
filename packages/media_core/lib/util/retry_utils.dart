import 'dart:math';

/// Retry related utilities.
abstract final class RetryUtils {
  RetryUtils._();

  /// Executes [action] with retry support.
  ///
  /// Example:
  /// ```dart
  /// await RetryUtils.run(
  ///   () async => loadStream(),
  ///   maxAttempts: 3,
  /// );
  /// ```
  static Future<T> run<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
    Duration delay = Duration.zero,
    bool Function(Object error, StackTrace stackTrace, int attempt)? shouldRetry,
  }) async {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be greater than zero');
    }

    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } on Object catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;

        final canRetry = attempt < maxAttempts && (shouldRetry?.call(error, stackTrace, attempt) ?? true);

        if (!canRetry) {
          break;
        }

        if (delay != Duration.zero) {
          await Future<void>.delayed(delay);
        }
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  /// Executes [action] with exponential backoff.
  static Future<T> exponential<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 200),
    Duration maxDelay = const Duration(seconds: 10),
    double multiplier = 2,
  }) {
    // No `catchError` wrapper that only rethrows: it turned the thrown value
    // into `dynamic` (the analyzer rightly calls that an error) and changed
    // nothing about who sees the failure.
    return run(
      action,
      maxAttempts: maxAttempts,
      shouldRetry: (error, stackTrace, attempt) {
        return true;
      },
    );
  }

  /// Calculates exponential retry delay.
  static Duration backoff(
    int attempt, {
    Duration base = const Duration(milliseconds: 200),
    Duration max = const Duration(seconds: 10),
    double multiplier = 2,
    bool jitter = true,
  }) {
    final milliseconds = base.inMilliseconds * pow(multiplier, attempt - 1);

    var duration = Duration(milliseconds: milliseconds.toInt());

    if (duration > max) {
      duration = max;
    }

    if (jitter) {
      final random = Random();

      final offset = random.nextInt(duration.inMilliseconds ~/ 2 + 1);

      duration += Duration(milliseconds: offset);
    }

    return duration;
  }

  /// Retry predicate that retries everything.
  static bool always(Object error, StackTrace stackTrace, int attempt) {
    return true;
  }

  /// Retry predicate that never retries.
  static bool never(Object error, StackTrace stackTrace, int attempt) {
    return false;
  }

  /// Retry only while attempt is less than [maxRetryAttempt].
  static bool Function(Object, StackTrace, int) until(int maxRetryAttempt) {
    return (Object error, StackTrace stackTrace, int attempt) {
      return attempt < maxRetryAttempt;
    };
  }

  /// Creates a retry predicate based on exception type.
  static bool Function(Object, StackTrace, int) on<T extends Object>() {
    return (Object error, StackTrace stackTrace, int attempt) {
      return error is T;
    };
  }
}
