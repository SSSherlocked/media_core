import 'dart:async';
import 'dart:math' as math;

/// Configuration for retry behavior.
class StreamRetryOptions {
  /// Builds a retry policy: [maxAttempts] total tries starting with [delay],
  /// grown by [backoffFactor] per failure, capped at [maxDelay], with up to
  /// [jitter] of random extra wait; [shouldRetry] decides per failure and
  /// [onRetry] observes each scheduled retry.
  const StreamRetryOptions({
    this.maxAttempts = 3,
    this.delay = const Duration(seconds: 1),
    this.backoffFactor = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.jitter = Duration.zero,
    this.shouldRetry,
    this.onRetry,
  }) : assert(maxAttempts >= 1, 'maxAttempts must count the first attempt'),
       assert(backoffFactor >= 1.0, 'backoffFactor below 1.0 would shrink the delay on every retry');

  /// Total number of attempts, including the first attempt.
  ///
  /// For example, maxAttempts = 3 means:
  ///
  /// 1. Initial attempt
  /// 2. First retry
  /// 3. Second retry
  final int maxAttempts;

  /// Initial delay before the first retry.
  final Duration delay;

  /// Multiplier applied to the delay after each failed attempt.
  ///
  /// Example with delay = 1 second and backoffFactor = 2:
  ///
  /// 1s -> 2s -> 4s -> 8s
  final double backoffFactor;

  /// Maximum delay between attempts.
  final Duration maxDelay;

  /// Optional random jitter added to the retry delay.
  ///
  /// For example:
  ///
  /// ```dart
  /// jitter: const Duration(milliseconds: 500),
  /// ```
  ///
  /// means up to 500ms of random delay can be added.
  final Duration jitter;

  /// Determines whether a failed attempt should be retried.
  ///
  /// `attempt` starts at 1.
  final bool Function(Object error, StackTrace stackTrace, int attempt)? shouldRetry;

  /// Called before waiting for the next retry.
  final FutureOr<void> Function(Object error, StackTrace stackTrace, int attempt, Duration nextDelay)? onRetry;
}

/// Async retry utilities.
///
/// This implementation does not depend on RxDart retry operators,
/// so it is compatible with RxDart 0.28.x.
abstract final class StreamRetry {
  /// Executes [action] and retries when it fails.
  ///
  /// The attempt budget comes from `options.maxAttempts`.
  ///
  /// The final error is rethrown with its original stack trace.
  static Future<T> run<T>(
    Future<T> Function() action, {
    StreamRetryOptions options = const StreamRetryOptions(),
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= options.maxAttempts; attempt++) {
      try {
        return await action();
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;

        final canRetry =
            attempt < options.maxAttempts && (options.shouldRetry?.call(error, stackTrace, attempt) ?? true);

        if (!canRetry) {
          Error.throwWithStackTrace(error, stackTrace);
        }

        final retryDelay = calculateDelay(options, attempt);

        await options.onRetry?.call(error, stackTrace, attempt, retryDelay);

        if (retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  /// Retry with a fixed delay.
  ///
  /// Example:
  ///
  /// ```text
  /// failure -> 1s -> retry
  /// failure -> 1s -> retry
  /// failure -> final error
  /// ```
  static Future<T> fixed<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
    Duration delay = const Duration(seconds: 1),
    bool Function(Object error, StackTrace stackTrace, int attempt)? shouldRetry,
    FutureOr<void> Function(Object error, StackTrace stackTrace, int attempt, Duration nextDelay)? onRetry,
  }) {
    return run(
      action,
      options: StreamRetryOptions(
        maxAttempts: maxAttempts,
        delay: delay,
        backoffFactor: 1,
        shouldRetry: shouldRetry,
        onRetry: onRetry,
      ),
    );
  }

  /// Retry with exponential backoff.
  ///
  /// Example with:
  ///
  /// ```dart
  /// delay: 1 second
  /// backoffFactor: 2
  /// ```
  ///
  /// results in:
  ///
  /// ```text
  /// 1s -> 2s -> 4s -> 8s
  /// ```
  static Future<T> exponential<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
    Duration delay = const Duration(seconds: 1),
    double backoffFactor = 2.0,
    Duration maxDelay = const Duration(seconds: 30),
    Duration jitter = Duration.zero,
    bool Function(Object error, StackTrace stackTrace, int attempt)? shouldRetry,
    FutureOr<void> Function(Object error, StackTrace stackTrace, int attempt, Duration nextDelay)? onRetry,
  }) {
    return run(
      action,
      options: StreamRetryOptions(
        maxAttempts: maxAttempts,
        delay: delay,
        backoffFactor: backoffFactor,
        maxDelay: maxDelay,
        jitter: jitter,
        shouldRetry: shouldRetry,
        onRetry: onRetry,
      ),
    );
  }

  /// Calculates the delay before the next retry.
  static Duration calculateDelay(StreamRetryOptions options, int attempt) {
    final baseMilliseconds = options.delay.inMilliseconds * math.pow(options.backoffFactor, attempt - 1);

    final maxMilliseconds = options.maxDelay.inMilliseconds;

    var milliseconds = math.min(baseMilliseconds, maxMilliseconds.toDouble()).round();

    final jitterMilliseconds = options.jitter.inMilliseconds;

    if (jitterMilliseconds > 0) {
      milliseconds += math.Random().nextInt(jitterMilliseconds + 1);
    }

    if (milliseconds <= 0) {
      return Duration.zero;
    }

    return Duration(milliseconds: milliseconds);
  }
}

/// A reusable retry controller.
///
/// Unlike [StreamRetry.run], this controller can invalidate the current
/// retry chain using [cancel].
///
/// Note:
/// Calling [cancel] does not forcibly cancel the currently executing
/// Future. It prevents the retry chain from continuing after the current
/// operation/wait finishes.
class StreamRetryController {
  /// Creates a controller that retries with [options] by default.
  StreamRetryController({this.options = const StreamRetryOptions()});

  /// Policy this controller applies to the operations it runs.
  final StreamRetryOptions options;

  bool _disposed = false;
  int _generation = 0;

  /// Whether the controller has been disposed.
  bool get isDisposed => _disposed;

  /// Whether the controller is still usable.
  bool get isAlive => !_disposed;

  /// Current generation.
  int get generation => _generation;

  /// Execute [action] with retry support.
  ///
  /// If [cancel] is called while the operation is running or waiting,
  /// the retry chain will not continue.
  Future<T> run<T>(Future<T> Function() action) async {
    if (_disposed) {
      throw StateError('StreamRetryController has been disposed.');
    }

    final generation = _generation;

    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= options.maxAttempts; attempt++) {
      _ensureCurrent(generation);

      try {
        return await action();
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;

        _ensureCurrent(generation);

        final canRetry =
            attempt < options.maxAttempts && (options.shouldRetry?.call(error, stackTrace, attempt) ?? true);

        if (!canRetry) {
          Error.throwWithStackTrace(error, stackTrace);
        }

        final retryDelay = StreamRetry.calculateDelay(options, attempt);

        await options.onRetry?.call(error, stackTrace, attempt, retryDelay);

        _ensureCurrent(generation);

        if (retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  /// Invalidates the current retry chain.
  ///
  /// The currently executing Future cannot be forcibly cancelled,
  /// but no further retry will be performed.
  void cancel() {
    if (_disposed) {
      return;
    }

    _generation++;
  }

  /// Dispose the controller.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _generation++;
  }

  void _ensureCurrent(int generation) {
    if (_disposed) {
      throw StateError('StreamRetryController has been disposed.');
    }

    if (generation != _generation) {
      throw StateError('StreamRetryController operation was cancelled.');
    }
  }
}

/// Retry predicate helpers.
abstract final class StreamRetryPredicates {
  /// Always retry.
  static bool always(Object error, StackTrace stackTrace, int attempt) {
    return true;
  }

  /// Never retry.
  static bool never(Object error, StackTrace stackTrace, int attempt) {
    return false;
  }

  /// Retry only while the attempt number is less than [maxRetryAttempt].
  static bool Function(Object error, StackTrace stackTrace, int attempt) until(int maxRetryAttempt) {
    return (Object error, StackTrace stackTrace, int attempt) {
      return attempt < maxRetryAttempt;
    };
  }

  /// Retry only when [predicate] returns true.
  static bool Function(Object error, StackTrace stackTrace, int attempt) where(bool Function(Object error) predicate) {
    return (Object error, StackTrace stackTrace, int attempt) {
      return predicate(error);
    };
  }
}
