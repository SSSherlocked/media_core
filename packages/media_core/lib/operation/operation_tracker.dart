import 'dart:async';
import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/operation/operation.dart';
import 'package:media_core/operation/operation_registry.dart' show OperationRegistry;
import 'package:media_core/operation/operation_state.dart';
import 'package:rxdart/rxdart.dart';

/// Tracks operation lifecycle changes.
///
/// [OperationTracker] observes and records the latest lifecycle state of
/// operations.
///
/// The tracker is responsible for:
///
/// - tracking the latest operation snapshot;
/// - recording operation lifecycle history;
/// - exposing reactive lifecycle updates;
/// - querying tracked operations.
///
/// The tracker does not:
///
/// - execute operations;
/// - schedule operations;
/// - own operation cancellation;
/// - apply timeout policy;
/// - perform retry;
/// - perform recovery;
/// - perform fallback;
/// - own the authoritative operation registry.
///
/// [OperationRegistry] manages operation registration and lookup, while
/// [OperationTracker] focuses on lifecycle observation and history.
///
/// Example:
///
/// ```dart
/// final tracker = OperationTracker();
///
/// tracker.track(operation);
///
/// final subscription = tracker.operations.listen((operation) {
///   print(operation.state);
/// });
///
/// final started = operation.start();
/// tracker.update(started);
///
/// await subscription.cancel();
/// tracker.dispose();
/// ```
final class OperationTracker {
  /// Creates an operation tracker.
  ///
  /// [maxHistory] controls the maximum number of lifecycle snapshots retained
  /// by the tracker.
  OperationTracker({int maxHistory = 1000})
    : assert(maxHistory > 0, 'maxHistory must be greater than zero.'),
      _maxHistory = maxHistory;

  final int _maxHistory;

  final Map<OperationId, Operation> _latest = <OperationId, Operation>{};

  final List<Operation> _history = <Operation>[];

  final BehaviorSubject<Operation?> _currentSubject = BehaviorSubject<Operation?>();

  final PublishSubject<Operation> _operationSubject = PublishSubject<Operation>();

  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------

  /// Whether this tracker has been disposed.
  bool get isDisposed => _disposed;

  /// Whether this tracker can accept lifecycle updates.
  bool get isActive => !_disposed;

  /// Maximum number of history records retained by the tracker.
  int get maxHistory => _maxHistory;

  /// Number of currently tracked operations.
  int get trackedCount => _latest.length;

  /// Number of historical operation snapshots.
  int get historyCount => _history.length;

  /// Whether no operations are currently tracked.
  bool get isEmpty => _latest.isEmpty;

  /// Whether at least one operation is currently tracked.
  bool get isNotEmpty => _latest.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Reactive streams
  // ---------------------------------------------------------------------------

  /// Emits every operation snapshot recorded by the tracker.
  ///
  /// This stream does not replay historical values.
  Stream<Operation> get operations => _operationSubject.stream;

  /// Emits the latest operation snapshot.
  ///
  /// Subscribers receive the latest value when one exists.
  Stream<Operation?> get current => _currentSubject.stream;

  /// Returns the latest operation snapshot emitted by the tracker.
  Operation? get currentOperation => _currentSubject.valueOrNull;

  // ---------------------------------------------------------------------------
  // Current operation lookup
  // ---------------------------------------------------------------------------

  /// Returns the latest snapshot for [id].
  ///
  /// Returns `null` when the operation is not tracked.
  Operation? find(OperationId id) {
    return _latest[id];
  }

  /// Returns the latest snapshot for [id].
  ///
  /// Throws [StateError] when the operation is not tracked.
  Operation require(OperationId id) {
    final operation = _latest[id];

    if (operation == null) {
      throw StateError('Operation "${id.value}" is not being tracked.');
    }

    return operation;
  }

  /// Returns whether [id] is currently tracked.
  bool contains(OperationId id) {
    return _latest.containsKey(id);
  }

  /// Returns all currently tracked operation snapshots.
  List<Operation> get trackedOperations {
    return List<Operation>.unmodifiable(_latest.values);
  }

  /// Returns all currently tracked operation IDs.
  List<OperationId> get trackedIds {
    return List<OperationId>.unmodifiable(_latest.keys);
  }

  // ---------------------------------------------------------------------------
  // Current state queries
  // ---------------------------------------------------------------------------

  /// Returns all currently running operations.
  List<Operation> get running {
    return List<Operation>.unmodifiable(_latest.values.where((operation) => operation.isRunning));
  }

  /// Returns all pending operations.
  List<Operation> get pending {
    return List<Operation>.unmodifiable(_latest.values.where((operation) => operation.isPending));
  }

  /// Returns all terminal operations.
  List<Operation> get terminal {
    return List<Operation>.unmodifiable(_latest.values.where((operation) => operation.isTerminal));
  }

  /// Returns all successfully completed operations.
  List<Operation> get completed {
    return List<Operation>.unmodifiable(_latest.values.where((operation) => operation.isCompleted));
  }

  /// Returns all failed operations.
  List<Operation> get failed {
    return List<Operation>.unmodifiable(_latest.values.where((operation) => operation.isFailed));
  }

  /// Returns all cancelled operations.
  List<Operation> get cancelled {
    return List<Operation>.unmodifiable(_latest.values.where((operation) => operation.isCancelled));
  }

  /// Returns the number of currently running operations.
  int get runningCount => running.length;

  /// Returns the number of pending operations.
  int get pendingCount => pending.length;

  /// Returns the number of terminal operations.
  int get terminalCount => terminal.length;

  /// Whether at least one operation is running.
  bool get hasRunningOperations => running.isNotEmpty;

  /// Whether at least one operation is pending.
  bool get hasPendingOperations => pending.isNotEmpty;

  /// Whether at least one operation is terminal.
  bool get hasTerminalOperations => terminal.isNotEmpty;

  /// Returns the first running operation.
  Operation? get firstRunning {
    for (final operation in _latest.values) {
      if (operation.isRunning) {
        return operation;
      }
    }

    return null;
  }

  /// Returns the first pending operation.
  Operation? get firstPending {
    for (final operation in _latest.values) {
      if (operation.isPending) {
        return operation;
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // State filtering
  // ---------------------------------------------------------------------------

  /// Returns currently tracked operations matching [predicate].
  List<Operation> where(bool Function(Operation operation) predicate) {
    return List<Operation>.unmodifiable(_latest.values.where(predicate));
  }

  /// Returns currently tracked operations in [state].
  List<Operation> byState(OperationState state) {
    return where((operation) => operation.state == state);
  }

  // ---------------------------------------------------------------------------
  // Tracking
  // ---------------------------------------------------------------------------

  /// Starts tracking [operation].
  ///
  /// If an operation with the same ID already exists, its latest snapshot is
  /// replaced.
  void track(Operation operation) {
    _checkNotDisposed();

    _record(operation);
  }

  /// Tracks [operation], replacing an existing snapshot with the same ID.
  void trackOrReplace(Operation operation) {
    _checkNotDisposed();

    _record(operation);
  }

  /// Updates an already tracked operation.
  ///
  /// Throws [StateError] when [operation] is not currently tracked.
  void update(Operation operation) {
    _checkNotDisposed();

    if (!_latest.containsKey(operation.id)) {
      throw StateError('Operation "${operation.id.value}" is not being tracked.');
    }

    _record(operation);
  }

  /// Tracks multiple operations.
  void trackAll(Iterable<Operation> operations) {
    _checkNotDisposed();

    operations.forEach(_record);
  }

  /// Updates multiple already tracked operations.
  ///
  /// Throws [StateError] when any operation is not currently tracked.
  ///
  /// No operation is recorded when validation fails.
  void updateAll(Iterable<Operation> operations) {
    _checkNotDisposed();

    final updates = operations.toList(growable: false);

    for (final operation in updates) {
      if (!_latest.containsKey(operation.id)) {
        throw StateError('Operation "${operation.id.value}" is not being tracked.');
      }
    }

    updates.forEach(_record);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle tracking
  // ---------------------------------------------------------------------------

  /// Records an operation as started.
  ///
  /// Returns the updated immutable operation snapshot.
  Operation markStarted(Operation operation) {
    _checkNotDisposed();

    final updated = operation.start();

    _record(updated);

    return updated;
  }

  /// Records an operation as completed.
  ///
  /// The completion timestamp can optionally be supplied.
  Operation markCompleted(Operation operation, {DateTime? completedAt}) {
    _checkNotDisposed();

    final updated = operation.complete(completedAt: completedAt);

    _record(updated);

    return updated;
  }

  /// Records an operation as failed.
  ///
  /// The completion timestamp can optionally be supplied.
  Operation markFailed(Operation operation, {DateTime? completedAt}) {
    _checkNotDisposed();

    final updated = operation.fail(completedAt: completedAt);

    _record(updated);

    return updated;
  }

  /// Records an operation as cancelled.
  ///
  /// The completion timestamp can optionally be supplied.
  Operation markCancelled(Operation operation, {DateTime? completedAt}) {
    _checkNotDisposed();

    final updated = operation.cancel(completedAt: completedAt);

    _record(updated);

    return updated;
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  /// Returns all historical snapshots for [id].
  List<Operation> historyFor(OperationId id) {
    return List<Operation>.unmodifiable(_history.where((operation) => operation.id == id));
  }

  /// Returns the first historical snapshot for [id].
  Operation? firstHistoryFor(OperationId id) {
    for (final operation in _history) {
      if (operation.id == id) {
        return operation;
      }
    }

    return null;
  }

  /// Returns the latest historical snapshot for [id].
  Operation? latestHistoryFor(OperationId id) {
    for (var index = _history.length - 1; index >= 0; index--) {
      final operation = _history[index];

      if (operation.id == id) {
        return operation;
      }
    }

    return null;
  }

  /// Returns all historical snapshots matching [predicate].
  List<Operation> whereHistory(bool Function(Operation operation) predicate) {
    return List<Operation>.unmodifiable(_history.where(predicate));
  }

  /// Returns all recorded lifecycle snapshots.
  List<Operation> get history {
    return List<Operation>.unmodifiable(_history);
  }

  /// Clears all historical snapshots.
  ///
  /// Currently tracked operations are preserved.
  void clearHistory() {
    if (_disposed) {
      return;
    }

    _history.clear();
  }

  /// Clears historical snapshots for [id].
  ///
  /// The currently tracked operation is preserved.
  void clearHistoryFor(OperationId id) {
    if (_disposed) {
      return;
    }

    _history.removeWhere((operation) => operation.id == id);
  }

  // ---------------------------------------------------------------------------
  // Untracking
  // ---------------------------------------------------------------------------

  /// Stops tracking [id].
  ///
  /// Historical snapshots are preserved.
  ///
  /// Returns the removed latest snapshot, or `null` when not tracked.
  Operation? untrack(OperationId id) {
    if (_disposed) {
      return null;
    }

    final removed = _latest.remove(id);

    if (_latest.isEmpty && !_currentSubject.isClosed) {
      _currentSubject.add(null);
    }

    return removed;
  }

  /// Stops tracking all terminal operations.
  ///
  /// Historical snapshots are preserved.
  ///
  /// Returns the number of removed operations.
  int untrackTerminal() {
    if (_disposed) {
      return 0;
    }

    final ids =
        _latest.values
            .where((operation) => operation.isTerminal)
            .map((operation) => operation.id)
            .toList(growable: false)
          ..forEach(_latest.remove);

    if (_latest.isEmpty && !_currentSubject.isClosed) {
      _currentSubject.add(null);
    }

    return ids.length;
  }

  /// Stops tracking operations matching [predicate].
  ///
  /// Historical snapshots are preserved.
  ///
  /// Returns the number of removed operations.
  int untrackWhere(bool Function(Operation operation) predicate) {
    if (_disposed) {
      return 0;
    }

    final ids = _latest.values.where(predicate).map((operation) => operation.id).toList(growable: false)
      ..forEach(_latest.remove);

    if (_latest.isEmpty && !_currentSubject.isClosed) {
      _currentSubject.add(null);
    }

    return ids.length;
  }

  /// Stops tracking all operations.
  ///
  /// Historical snapshots are preserved.
  void clear() {
    if (_disposed) {
      return;
    }

    _latest.clear();

    if (!_currentSubject.isClosed) {
      _currentSubject.add(null);
    }
  }

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------

  /// Clears current tracking and historical records.
  void reset() {
    if (_disposed) {
      return;
    }

    _latest.clear();
    _history.clear();

    if (!_currentSubject.isClosed) {
      _currentSubject.add(null);
    }
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  /// Disposes the tracker.
  ///
  /// Disposal does not mutate any [Operation]. It only releases the tracker's
  /// internal state and closes its reactive streams.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _latest.clear();
    _history.clear();

    unawaited(_operationSubject.close());

    unawaited(_currentSubject.close());
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _record(Operation operation) {
    _latest[operation.id] = operation;

    _history.add(operation);

    if (_history.length > _maxHistory) {
      final overflow = _history.length - _maxHistory;

      _history.removeRange(0, overflow);
    }

    if (!_operationSubject.isClosed) {
      _operationSubject.add(operation);
    }

    if (!_currentSubject.isClosed) {
      _currentSubject.add(operation);
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('OperationTracker has been disposed.');
    }
  }

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  @override
  String toString() {
    return 'OperationTracker('
        'tracked: $trackedCount, '
        'history: $historyCount, '
        'running: $runningCount, '
        'pending: $pendingCount, '
        'terminal: $terminalCount, '
        'disposed: $_disposed'
        ')';
  }
}
