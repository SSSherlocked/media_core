import 'dart:async';
import 'dart:collection';

/// Executes asynchronous tasks sequentially.
///
/// Tasks are queued and executed one by one in FIFO order.
///
/// Useful for:
/// - player command queue
/// - database writes
/// - file operations
/// - state mutations
///
/// Example:
/// ```dart
/// final executor = SerialExecutor();
///
/// executor.execute(() async {
///   await saveData();
/// });
/// ```
class SerialExecutor {
  final Queue<_SerialTask<dynamic>> _queue = Queue<_SerialTask<dynamic>>();

  bool _running = false;

  /// Whether executor is currently processing tasks.
  bool get running => _running;

  /// Number of waiting tasks.
  int get pendingCount => _queue.length;

  /// Adds a task to the queue.
  ///
  /// Tasks are executed in insertion order.
  Future<T> execute<T>(Future<T> Function() action) {
    final task = _SerialTask<T>(action);

    _queue.add(task);

    // The queue drives itself; callers await the task's completer instead so a
    // slow head-of-queue task cannot block enqueueing.
    unawaited(_process());

    return task.completer.future;
  }

  Future<void> _process() async {
    if (_running) {
      return;
    }

    _running = true;

    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeFirst();

        try {
          final result = await task.action();

          task.completer.complete(result);
        } catch (error, stackTrace) {
          task.completer.completeError(error, stackTrace);
        }
      }
    } finally {
      _running = false;
    }
  }

  /// Clears all pending tasks.
  ///
  /// The currently running task is not cancelled.
  void clear() {
    while (_queue.isNotEmpty) {
      final task = _queue.removeFirst();

      task.completer.completeError(StateError('Task removed from executor queue'));
    }
  }

  /// Waits until all tasks finish.
  Future<void> drain() async {
    while (_running || _queue.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class _SerialTask<T> {
  _SerialTask(this.action);

  final Future<T> Function() action;

  final Completer<T> completer = Completer<T>();
}

/// A keyed serial executor.
///
/// Each key owns an independent queue.
///
/// Example:
/// ```dart
/// final executor = KeyedSerialExecutor<String>();
///
/// executor.execute(
///   'player-1',
///   () async {
///     await reload();
///   },
/// );
/// ```
class KeyedSerialExecutor<K> {
  final Map<K, SerialExecutor> _executors = {};

  /// Executes [action] sequentially for [key].
  Future<T> execute<T>(K key, Future<T> Function() action) async {
    final executor = _executors.putIfAbsent(key, SerialExecutor.new);

    try {
      return await executor.execute(action);
    } finally {
      if (!executor.running && executor.pendingCount == 0) {
        _executors.remove(key);
      }
    }
  }

  /// Number of active queues.
  int get length => _executors.length;

  /// Removes idle queues.
  void cleanup() {
    _executors.removeWhere((_, executor) => !executor.running && executor.pendingCount == 0);
  }

  /// Clears all queues.
  ///
  /// Running operations are not interrupted.
  void clear() {
    for (final executor in _executors.values) {
      executor.clear();
    }

    _executors.clear();
  }
}
