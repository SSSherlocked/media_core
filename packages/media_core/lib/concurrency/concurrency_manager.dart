import 'package:media_core/concurrency/concurrency_limit.dart';
import 'package:media_core/concurrency/lock.dart';
import 'package:media_core/concurrency/mutex.dart';
import 'package:media_core/concurrency/serial_executor.dart';

/// Central manager for concurrency primitives.
///
/// Provides shared access to:
///
/// - locks
/// - mutexes
/// - concurrency limits
/// - serial executors
///
/// This class is designed to be used as infrastructure
/// inside a reusable library.
///
/// It does not:
///
/// - define business logic
/// - identify resources
/// - manage task lifecycle
///
/// Resource keys are owned by the caller.
///
/// Example:
///
/// ```dart
/// final manager = ConcurrencyManager();
///
/// await manager.withLock(
///   'resource',
///   () async {
///     await operation();
///   },
/// );
/// ```
final class ConcurrencyManager {
  final Map<Object, AsyncLock> _locks = {};

  final Map<Object, Mutex> _mutexes = {};

  final Map<Object, ConcurrencyLimit> _limits = {};

  final Map<Object, SerialExecutor> _executors = {};

  /// Executes an operation with an async lock.
  ///
  /// Only one operation with the same [key]
  /// can run at the same time.
  Future<T> withLock<T>(Object key, Future<T> Function() action) {
    final lock = _locks.putIfAbsent(key, AsyncLock.new);

    return lock.synchronized(action);
  }

  /// Executes an operation with a mutex.
  ///
  /// A mutex protects a critical section
  /// from concurrent access.
  Future<T> withMutex<T>(Object key, Future<T> Function() action) {
    final mutex = _mutexes.putIfAbsent(key, Mutex.new);

    return mutex.protect(action);
  }

  /// Executes an operation with a concurrency limit.
  ///
  /// [maxConcurrent] defines the maximum number
  /// of operations that may run simultaneously
  /// for the given [key].
  ///
  /// Additional operations wait until a slot
  /// becomes available.
  Future<T> withLimit<T>(Object key, int maxConcurrent, Future<T> Function() action) {
    final limit = _limits.putIfAbsent(key, () => ConcurrencyLimit(maxConcurrent));

    return limit.withPermit(action);
  }

  /// Executes operations sequentially.
  ///
  /// Operations using the same [key]
  /// are executed in FIFO order.
  Future<T> executeSerial<T>(Object key, Future<T> Function() action) {
    final executor = _executors.putIfAbsent(key, SerialExecutor.new);

    return executor.execute(action);
  }

  /// Returns an existing async lock.
  ///
  /// Returns `null` if no resource exists.
  AsyncLock? getLock(Object key) {
    return _locks[key];
  }

  /// Returns an existing mutex.
  ///
  /// Returns `null` if no resource exists.
  Mutex? getMutex(Object key) {
    return _mutexes[key];
  }

  /// Returns an existing concurrency limit.
  ///
  /// Returns `null` if no resource exists.
  ConcurrencyLimit? getLimit(Object key) {
    return _limits[key];
  }

  /// Returns an existing serial executor.
  ///
  /// Returns `null` if no resource exists.
  SerialExecutor? getExecutor(Object key) {
    return _executors[key];
  }

  /// Removes idle resources.
  ///
  /// Running operations are not interrupted.
  void cleanup() {
    _locks.removeWhere((_, lock) => !lock.locked);

    _mutexes.removeWhere((_, mutex) => !mutex.locked);

    _limits.removeWhere((_, limit) => limit.current == 0);

    _executors.removeWhere((_, executor) => !executor.running && executor.pendingCount == 0);
  }

  /// Clears all managed resources.
  ///
  /// Running operations are not cancelled.
  void clear() {
    _locks.clear();
    _mutexes.clear();
    _limits.clear();
    _executors.clear();
  }

  /// Number of managed resources.
  int get resourceCount {
    return _locks.length + _mutexes.length + _limits.length + _executors.length;
  }

  /// Whether no resources are managed.
  bool get isEmpty {
    return resourceCount == 0;
  }
}
