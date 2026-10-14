import 'dart:async';

/// Controls asynchronous operations so that stale operations can be ignored
/// or cancelled.
///
/// Typical use cases:
/// - search input
/// - stream URL resolving
/// - channel switching
/// - refreshing IPTV sources
/// - EPG loading
/// - player fallback operations
class StreamGate {
  /// Creates a gate at generation zero, ready to hand out operation tokens.
  StreamGate();

  int _generation = 0;
  bool _disposed = false;

  /// Whether this gate has been disposed.
  bool get isDisposed => _disposed;

  /// Whether this gate can still execute work.
  bool get isAlive => !_disposed;

  /// Current operation generation.
  int get generation => _generation;

  /// Start a new operation generation.
  ///
  /// Any previously started operation can use its generation to determine
  /// whether it is still the latest operation.
  int next() {
    if (_disposed) {
      return _generation;
    }

    return ++_generation;
  }

  /// Invalidate all currently running operations.
  int invalidate() {
    return next();
  }

  /// Returns whether [generation] is still the latest generation.
  bool isCurrent(int generation) {
    return !_disposed && generation == _generation;
  }

  /// Execute [action] only if this gate is still alive.
  Future<T?> run<T>(Future<T> Function() action) {
    if (_disposed) {
      return Future<T?>.value();
    }

    return action();
  }

  /// Start an operation and only return its result if it is still current.
  ///
  /// Example:
  /// ```dart
  /// final result = await gate.latest(() async {
  ///   return await resolveUrl();
  /// });
  ///
  /// if (result != null) {
  ///   play(result);
  /// }
  /// ```
  Future<T?> latest<T>(Future<T> Function() action) async {
    if (_disposed) {
      return null;
    }

    final currentGeneration = next();

    try {
      final result = await action();

      if (!isCurrent(currentGeneration)) {
        return null;
      }

      return result;
    } catch (_) {
      if (!isCurrent(currentGeneration)) {
        return null;
      }

      rethrow;
    }
  }

  /// Execute [action] and return whether it was still current when it
  /// completed.
  Future<bool> latestVoid(Future<void> Function() action) async {
    if (_disposed) {
      return false;
    }

    final currentGeneration = next();

    try {
      await action();
    } catch (_) {
      if (!isCurrent(currentGeneration)) {
        return false;
      }

      rethrow;
    }

    return isCurrent(currentGeneration);
  }

  /// Execute an operation with an explicit generation.
  ///
  /// This is useful when an operation consists of several asynchronous
  /// stages.
  int begin() {
    return next();
  }

  /// Check whether an operation can continue.
  bool canContinue(int operationGeneration) {
    return isCurrent(operationGeneration);
  }

  /// Dispose the gate and invalidate all operations.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    ++_generation;
  }
}

/// Prevents concurrent execution of the same asynchronous operation.
///
/// While an operation is running, subsequent calls return the same Future.
///
/// Example:
/// ```dart
/// final gate = StreamSingleFlight<String>();
///
/// final a = gate.run('channel', resolveUrl);
/// final b = gate.run('channel', resolveUrl);
///
/// // a and b share the same in-flight operation.
/// ```
class StreamSingleFlight<T> {
  final Map<String, Future<T>> _running = <String, Future<T>>{};

  /// Number of currently running operations.
  int get length => _running.length;

  /// Whether an operation with [key] is currently running.
  bool isRunning(String key) {
    return _running.containsKey(key);
  }

  /// Run [action] for [key].
  ///
  /// If the same key is already running, the existing Future is returned.
  Future<T> run(String key, Future<T> Function() action) {
    final existing = _running[key];

    if (existing != null) {
      return existing;
    }

    final future = _execute(key, action);

    _running[key] = future;

    return future;
  }

  Future<T> _execute(String key, Future<T> Function() action) async {
    try {
      return await action();
    } finally {
      // `remove` hands back this very operation, which is completing right now;
      // the caller's own chain owns its result. Naming that keeps the line from
      // reading like a callback that was dropped on the floor.
      final finished = _running.remove(key);

      if (finished != null) {
        unawaited(finished);
      }
    }
  }

  /// Cancel tracking for [key].
  ///
  /// This does not cancel the underlying Future. Dart Futures generally
  /// cannot be cancelled directly.
  ///
  /// The abandoned operation's failure is set aside on purpose: a caller that
  /// forgets a key has said it will not read the answer, and an error from a
  /// future nobody is waiting on any more would surface through the zone's
  /// handler as an unhandled async exception.
  void forget(String key) {
    _running.remove(key)?.ignore();
  }

  /// Clear all tracked operations.
  ///
  /// Underlying Futures continue running, and like [forget] their results are no
  /// longer anybody's to read, so their failures are set aside rather than left
  /// to reach the top level.
  void clear() {
    for (final future in _running.values) {
      future.ignore();
    }

    _running.clear();
  }
}

/// A simple concurrency limiter.
///
/// Useful when a large number of independent async operations need to be
/// processed without overwhelming the network or CPU.
///
/// Example:
/// ```dart
/// final limiter = StreamConcurrencyLimiter(3);
///
/// final result = await limiter.run(() async {
///   return await loadEpg();
/// });
/// ```
class StreamConcurrencyLimiter {
  /// Limits to [maxConcurrent] in-flight operations, optionally refusing to
  /// queue more than [queueLimit] waiting ones; a `null` [queueLimit] lets the
  /// queue grow without bound.
  StreamConcurrencyLimiter(this.maxConcurrent, {this.queueLimit})
    : assert(maxConcurrent > 0, 'maxConcurrent must be positive');

  /// Maximum number of operations executed at the same time.
  final int maxConcurrent;

  /// Upper bound on queued operations, or `null` for an unbounded queue.
  final int? queueLimit;

  int _active = 0;
  final List<_QueuedOperation<dynamic>> _queue = <_QueuedOperation<dynamic>>[];

  /// Number of currently running operations.
  int get activeCount => _active;

  /// Number of operations waiting in the queue.
  int get queuedCount => _queue.length;

  /// Schedule [action].
  Future<T> run<T>(Future<T> Function() action) {
    if (_active < maxConcurrent) {
      return _execute(action);
    }

    final limit = queueLimit;

    if (limit != null && _queue.length >= limit) {
      return Future<T>.error(StateError('StreamConcurrencyLimiter queue is full.'));
    }

    final operation = _QueuedOperation<T>(action);
    _queue.add(operation);

    return operation.future;
  }

  Future<T> _execute<T>(Future<T> Function() action) async {
    _active++;

    try {
      return await action();
    } finally {
      _active--;
      _drain();
    }
  }

  void _drain() {
    while (_active < maxConcurrent && _queue.isNotEmpty) {
      final operation = _queue.removeAt(0);

      // The queued operation's own completer is the hand-off point, so the
      // future returned by `then` is intentionally not awaited here.
      unawaited(_execute(operation.action).then(operation.complete, onError: operation.completeError));
    }
  }

  /// Clear operations that are still waiting.
  ///
  /// Already-running operations are not affected.
  void clearQueue() {
    final pending = List<_QueuedOperation<dynamic>>.from(_queue);
    _queue.clear();

    for (final operation in pending) {
      operation.completeError(StateError('Operation was removed from the queue.'));
    }
  }
}

class _QueuedOperation<T> {
  _QueuedOperation(this.action);

  final Future<T> Function() action;

  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  void complete(T value) {
    if (_completer.isCompleted) {
      return;
    }

    _completer.complete(value);
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) {
      return;
    }

    _completer.completeError(error, stackTrace);
  }
}
