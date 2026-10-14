import 'package:media_core/concurrency/exclusive_task.dart' show ExclusiveTask;
import 'package:media_core/concurrency/mutex.dart' show Mutex;
import 'package:media_core/concurrency/serial_executor.dart' show SerialExecutor;
import 'package:pool/pool.dart';

/// Controls the maximum number of concurrent executions.
///
/// A [ConcurrencyLimit] represents a single concurrency bucket.
///
/// Examples:
///
/// - decoder can have 2 parallel jobs
/// - network can have 8 parallel requests
/// - recording can have only 1 active task
///
/// Responsibilities:
///
/// - limit concurrent execution count
/// - acquire execution permits
/// - release execution permits
/// - execute protected actions
///
/// It does not:
///
/// - identify tasks
/// - schedule execution order
/// - manage task lifecycle
/// - provide mutual exclusion
///
/// Those belong to:
///
/// - [Mutex]
/// - [SerialExecutor]
/// - [ExclusiveTask]
final class ConcurrencyLimit {
  /// Creates a concurrency limit.
  ///
  /// [maxConcurrent] defines the maximum number
  /// of simultaneous executions.
  ConcurrencyLimit(this.maxConcurrent) {
    if (maxConcurrent <= 0) {
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent', 'Concurrency limit must be greater than zero');
    }

    _pool = Pool(maxConcurrent);
  }

  /// Maximum allowed concurrent executions.
  final int maxConcurrent;

  late final Pool _pool;

  final List<PoolResource> _resources = [];

  /// Current active executions.
  int get current => _resources.length;

  /// Available execution slots.
  int get available => maxConcurrent - current;

  /// Whether all slots are currently occupied.
  bool get isFull => current >= maxConcurrent;

  /// Whether there are available execution slots.
  bool get hasCapacity => available > 0;

  /// Acquires one execution permit.
  ///
  /// Waits when all slots are occupied.
  Future<void> acquire() async {
    final resource = await _pool.request();

    _resources.add(resource);
  }

  /// Releases one execution permit.
  ///
  /// Throws [StateError] if there are no acquired permits.
  void release() {
    if (_resources.isEmpty) {
      throw StateError('Cannot release unused concurrency permit');
    }

    _resources.removeLast().release();
  }

  /// Executes an action while holding a permit.
  ///
  /// The permit is automatically released after
  /// completion.
  Future<T> withPermit<T>(Future<T> Function() action) async {
    await acquire();

    try {
      return await action();
    } finally {
      release();
    }
  }

  /// Returns a diagnostic description.
  @override
  String toString() {
    return 'ConcurrencyLimit('
        'max=$maxConcurrent, '
        'current=$current'
        ')';
  }
}
