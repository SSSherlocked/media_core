import 'dart:async';
import 'package:media_core/reactive/stream_mutex.dart' show StreamMutex;

/// A serial asynchronous task queue.
///
/// Tasks are executed strictly in the order they are added.
///
/// Unlike [StreamMutex], this class is designed around an explicit queue:
/// tasks can be added without waiting for the previous task to finish.
///
/// Example:
/// ```dart
/// final queue = StreamQueue<void>();
///
/// queue.add(() async {
///   await stopPlayer();
/// });
///
/// queue.add(() async {
///   await openPlayer(url);
/// });
///
/// queue.add(() async {
///   await play();
/// });
///
/// await queue.idle;
/// ```
class StreamQueue<T> {
  final List<_QueueTask<T>> _queue = <_QueueTask<T>>[];

  bool _running = false;
  bool _disposed = false;

  Completer<void>? _idleCompleter;

  /// Whether this queue has been disposed.
  bool get isDisposed => _disposed;

  /// Whether the queue can still accept tasks.
  bool get isAlive => !_disposed;

  /// Whether a task is currently executing.
  bool get isRunning => _running;

  /// Number of tasks waiting or currently executing.
  int get length => _queue.length + (_running ? 1 : 0);

  /// Number of tasks waiting to execute.
  int get pendingCount => _queue.length;

  /// Whether the queue currently has no work.
  bool get isIdle => !_running && _queue.isEmpty;

  /// Future that completes when all currently queued work is finished.
  Future<void> get idle {
    if (isIdle) {
      return Future<void>.value();
    }

    return (_idleCompleter ??= Completer<void>()).future;
  }

  /// Add a task to the end of the queue.
  ///
  /// The returned Future completes with the task's result.
  Future<R> add<R>(Future<R> Function() action) {
    if (_disposed) {
      return Future<R>.error(StateError('StreamQueue has been disposed.'));
    }

    final task = _QueueTask<R>(action);

    _queue.add(task as _QueueTask<T>);

    _startNext();

    return task.future;
  }

  /// Add a task and ignore its result.
  Future<void> addVoid(Future<void> Function() action) {
    return add<void>(action);
  }

  /// Remove all tasks that have not started yet.
  ///
  /// The currently running task is not cancelled.
  void clear() {
    if (_queue.isEmpty) {
      return;
    }

    final tasks = List<_QueueTask<T>>.from(_queue);
    _queue.clear();

    for (final task in tasks) {
      if (!task.completer.isCompleted) {
        task.completer.completeError(StateError('Task was removed from the queue.'));
      }
    }

    _completeIdleIfNeeded();
  }

  /// Wait until the queue becomes idle.
  Future<void> wait() {
    return idle;
  }

  /// Dispose the queue.
  ///
  /// The currently running task is allowed to finish.
  /// Pending tasks are discarded.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    clear();
  }

  void _startNext() {
    if (_running || _disposed || _queue.isEmpty) {
      _completeIdleIfNeeded();
      return;
    }

    _running = true;

    final task = _queue.removeAt(0);

    // The task's own completer is how its result reaches the caller of `add`;
    // `_execute` chains the next task itself, so nothing awaits it here.
    unawaited(_execute(task));
  }

  Future<void> _execute(_QueueTask<T> task) async {
    try {
      final result = await task.action();

      if (!task.completer.isCompleted) {
        task.completer.complete(result);
      }
    } catch (error, stackTrace) {
      if (!task.completer.isCompleted) {
        task.completer.completeError(error, stackTrace);
      }
    } finally {
      _running = false;

      if (_disposed) {
        _completeIdleIfNeeded();
      } else {
        _startNext();
      }
    }
  }

  void _completeIdleIfNeeded() {
    if (!isIdle) {
      return;
    }

    final completer = _idleCompleter;

    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    _idleCompleter = null;
  }
}

class _QueueTask<T> {
  _QueueTask(this.action);

  final Future<T> Function() action;

  final Completer<T> completer = Completer<T>();

  Future<T> get future => completer.future;
}

/// A queue specifically designed for fire-and-forget operations.
///
/// Useful when callers do not need individual task results.
class StreamTaskQueue {
  final StreamQueue<void> _queue = StreamQueue<void>();

  /// Whether the wrapped queue has been disposed.
  bool get isDisposed => _queue.isDisposed;

  /// Whether [add] and [schedule] still accept work.
  bool get isAlive => _queue.isAlive;

  /// Whether an operation is currently executing.
  bool get isRunning => _queue.isRunning;

  /// Whether no operation is running or waiting.
  bool get isIdle => _queue.isIdle;

  /// Number of operations waiting plus the running one.
  int get length => _queue.length;

  /// Number of operations waiting to start.
  int get pendingCount => _queue.pendingCount;

  /// Future that completes once the current backlog is drained.
  Future<void> get idle => _queue.idle;

  /// Add an operation to the queue.
  ///
  /// Errors are still delivered through the returned Future.
  Future<void> add(Future<void> Function() action) {
    return _queue.add(action);
  }

  /// Add an operation without awaiting it.
  void schedule(Future<void> Function() action) {
    unawaited(_queue.add(action));
  }

  /// Remove all pending operations.
  void clear() {
    _queue.clear();
  }

  /// Wait until all operations are finished.
  Future<void> wait() {
    return _queue.wait();
  }

  /// Dispose the queue.
  void dispose() {
    _queue.dispose();
  }
}
