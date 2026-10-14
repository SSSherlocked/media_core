import 'dart:async';

/// Debounces asynchronous operations.
///
/// When [run] is called repeatedly, only the last call is executed after
/// [delay].
///
/// Example:
/// ```dart
/// final debouncer = StreamDebouncer(
///   delay: const Duration(milliseconds: 300),
/// );
///
/// debouncer.run(() async {
///   await search(keyword);
/// });
/// ```
class StreamDebouncer {
  /// Creates a debouncer that waits [delay] of quiet before running an action.
  StreamDebouncer({required this.delay});

  /// Quiet period that must elapse before the scheduled action is executed.
  final Duration delay;

  Timer? _timer;
  bool _disposed = false;

  int _generation = 0;

  /// Whether this debouncer has been disposed and ignores further actions.
  bool get isDisposed => _disposed;

  /// Whether [run] still schedules actions.
  bool get isAlive => !_disposed;

  /// Whether an operation is currently waiting for the debounce period.
  bool get isPending => _timer != null;

  /// Schedule [action].
  ///
  /// Any previously scheduled action is discarded.
  void run(FutureOr<void> Function() action) {
    if (_disposed) {
      return;
    }

    _timer?.cancel();

    final generation = ++_generation;

    _timer = Timer(delay, () async {
      _timer = null;

      if (_disposed || generation != _generation) {
        return;
      }

      await action();
    });
  }

  /// Cancel the currently scheduled operation.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _generation++;
  }

  /// Dispose the debouncer.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _generation++;
  }
}

/// Debounces asynchronous operations and returns a Future for the latest
/// scheduled operation.
///
/// Unlike [StreamDebouncer], this class allows callers to await the result.
///
/// Example:
/// ```dart
/// final debouncer = AsyncDebouncer<String>(
///   delay: const Duration(milliseconds: 300),
/// );
///
/// final result = await debouncer.run(
///   () => search(keyword),
/// );
/// ```
///
/// When a call is replaced by a newer call, the previous Future completes
/// with `null`.
class AsyncDebouncer<T> {
  /// Creates a debouncer that waits [delay] of quiet before running an action.
  AsyncDebouncer({required this.delay});

  /// Quiet period that must elapse before the scheduled action is executed.
  final Duration delay;

  Timer? _timer;

  _PendingOperation<T>? _pending;

  bool _disposed = false;

  int _generation = 0;

  /// Whether this debouncer has been disposed and answers callers with `null`.
  bool get isDisposed => _disposed;

  /// Whether [run] still schedules actions.
  bool get isAlive => !_disposed;

  /// Whether an operation is waiting for the debounce period with a caller
  /// still awaiting its future.
  bool get isPending => _pending != null;

  /// Schedules [action] and returns the future of the latest caller.
  ///
  /// A call that is replaced before the quiet period ends completes with `null`
  /// so awaiting callers never hang on work that no longer matters.
  Future<T?> run(Future<T> Function() action) {
    if (_disposed) {
      return Future<T?>.value();
    }

    _timer?.cancel();

    final previous = _pending;

    if (previous != null && !previous.completer.isCompleted) {
      previous.completer.complete(null);
    }

    final generation = ++_generation;

    final pending = _PendingOperation<T>();

    _pending = pending;

    _timer = Timer(delay, () async {
      _timer = null;

      if (_disposed || generation != _generation || !identical(_pending, pending)) {
        if (!pending.completer.isCompleted) {
          pending.completer.complete(null);
        }

        return;
      }

      try {
        final result = await action();

        if (!_disposed && generation == _generation && identical(_pending, pending)) {
          if (!pending.completer.isCompleted) {
            pending.completer.complete(result);
          }
        } else {
          if (!pending.completer.isCompleted) {
            pending.completer.complete(null);
          }
        }
      } catch (error, stackTrace) {
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(error, stackTrace);
        }
      } finally {
        if (identical(_pending, pending)) {
          _pending = null;
        }
      }
    });

    return pending.completer.future;
  }

  /// Cancel the pending operation.
  void cancel() {
    _timer?.cancel();
    _timer = null;

    _generation++;

    final pending = _pending;
    _pending = null;

    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(null);
    }
  }

  /// Dispose the debouncer.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _timer?.cancel();
    _timer = null;

    _generation++;

    final pending = _pending;
    _pending = null;

    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(null);
    }
  }
}

class _PendingOperation<T> {
  final Completer<T?> completer = Completer<T?>();
}
