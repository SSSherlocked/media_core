import 'dart:async';
import 'dart:collection';

/// An asynchronous semaphore.
///
/// Limits the number of concurrent operations.
///
/// Example:
/// ```dart
/// final semaphore = AsyncSemaphore(3);
///
/// await semaphore.withPermit(() async {
///   await download();
/// });
/// ```
class AsyncSemaphore {
  /// Creates a semaphore that hands out at most [maxPermits] permits.
  AsyncSemaphore(this.maxPermits) : assert(maxPermits > 0, 'maxPermits must be positive');

  /// Maximum number of simultaneous holders.
  final int maxPermits;

  int _availablePermits = 0;

  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  bool _initialized = false;

  void _ensureInitialized() {
    if (_initialized) {
      return;
    }

    _availablePermits = maxPermits;
    _initialized = true;
  }

  /// Number of currently available permits.
  int get available {
    _ensureInitialized();
    return _availablePermits;
  }

  /// Number of waiting tasks.
  int get waitingCount => _waiters.length;

  /// Number of active holders.
  int get activeCount {
    _ensureInitialized();
    return maxPermits - _availablePermits;
  }

  /// Acquires one permit.
  Future<void> acquire() async {
    _ensureInitialized();

    if (_availablePermits > 0) {
      _availablePermits--;
      return;
    }

    final waiter = Completer<void>();
    _waiters.add(waiter);

    await waiter.future;
  }

  /// Releases one permit.
  void release() {
    _ensureInitialized();

    if (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();

      if (!waiter.isCompleted) {
        waiter.complete();
      }

      return;
    }

    if (_availablePermits < maxPermits) {
      _availablePermits++;
    }
  }

  /// Runs [action] with one permit.
  Future<T> withPermit<T>(Future<T> Function() action) async {
    await acquire();

    try {
      return await action();
    } finally {
      release();
    }
  }

  /// Clears pending waiters.
  ///
  /// Existing operations are not affected.
  void clearWaiters() {
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();

      if (!waiter.isCompleted) {
        waiter.completeError(StateError('Semaphore was cleared'));
      }
    }
  }
}
