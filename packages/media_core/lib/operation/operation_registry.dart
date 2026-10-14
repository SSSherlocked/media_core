import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/operation/operation.dart';
import 'package:media_core/operation/operation_state.dart';

/// Stores and manages currently registered operations.
///
/// [OperationRegistry] is responsible only for operation registration and
/// lookup. It does not:
///
/// - execute operations;
/// - schedule operations;
/// - cancel operations;
/// - apply timeout policies;
/// - perform retry/recovery/fallback.
///
/// The registry represents the authoritative set of operations known to the
/// operation layer.
final class OperationRegistry {
  final Map<OperationId, Operation> _operations = <OperationId, Operation>{};

  bool _disposed = false;

  /// Whether this registry has been disposed.
  bool get isDisposed => _disposed;

  /// Whether the registry can accept new operations.
  bool get isActive => !_disposed;

  /// Number of registered operations.
  int get length => _operations.length;

  /// Whether no operations are registered.
  bool get isEmpty => _operations.isEmpty;

  /// Whether at least one operation is registered.
  bool get isNotEmpty => _operations.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  /// Returns all currently registered operations.
  List<Operation> get all {
    return List<Operation>.unmodifiable(_operations.values);
  }

  /// Returns all registered operation IDs.
  List<OperationId> get ids {
    return List<OperationId>.unmodifiable(_operations.keys);
  }

  /// Finds an operation by ID.
  ///
  /// Returns `null` when the operation is not registered.
  Operation? find(OperationId id) {
    return _operations[id];
  }

  /// Whether an operation with [id] is registered.
  bool contains(OperationId id) {
    return _operations.containsKey(id);
  }

  /// Returns a registered operation or throws [StateError].
  Operation require(OperationId id) {
    final operation = _operations[id];

    if (operation == null) {
      throw StateError('Operation "${id.value}" is not registered.');
    }

    return operation;
  }

  /// Returns all operations matching [predicate].
  List<Operation> where(bool Function(Operation operation) predicate) {
    return List<Operation>.unmodifiable(_operations.values.where(predicate));
  }

  /// Returns all operations in [state].
  List<Operation> byState(OperationState state) {
    return where((operation) => operation.state == state);
  }

  /// Returns all active operations.
  List<Operation> get active {
    return where((operation) => operation.isRunning);
  }

  /// Returns all pending operations.
  List<Operation> get pending {
    return where((operation) => operation.isPending);
  }

  /// Returns all terminal operations.
  List<Operation> get terminal {
    return where((operation) => operation.isTerminal);
  }

  /// Returns all successfully completed operations.
  List<Operation> get completed {
    return where((operation) => operation.isCompleted);
  }

  /// Returns all failed operations.
  List<Operation> get failed {
    return where((operation) => operation.isFailed);
  }

  /// Returns all cancelled operations.
  List<Operation> get cancelled {
    return where((operation) => operation.isCancelled);
  }

  /// Number of active operations.
  int get activeCount => active.length;

  /// Number of pending operations.
  int get pendingCount => pending.length;

  /// Number of terminal operations.
  int get terminalCount => terminal.length;

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Registers [operation].
  ///
  /// Throws [StateError] when:
  ///
  /// - the registry has been disposed;
  /// - another operation with the same ID is already registered.
  void register(Operation operation) {
    _checkNotDisposed();

    final existing = _operations[operation.id];

    if (existing != null) {
      throw StateError('Operation "${operation.id.value}" is already registered.');
    }

    _operations[operation.id] = operation;
  }

  /// Registers [operation], replacing an existing operation with the same ID.
  void registerOrReplace(Operation operation) {
    _checkNotDisposed();

    _operations[operation.id] = operation;
  }

  /// Registers multiple operations.
  ///
  /// The operation set is validated before modifying the registry, preventing
  /// partial registration when duplicate IDs are present in the input.
  void registerAll(Iterable<Operation> operations) {
    _checkNotDisposed();

    final incoming = <OperationId, Operation>{};

    for (final operation in operations) {
      if (incoming.containsKey(operation.id)) {
        throw StateError(
          'Duplicate operation ID "${operation.id.value}" '
          'in registration batch.',
        );
      }

      if (_operations.containsKey(operation.id)) {
        throw StateError('Operation "${operation.id.value}" is already registered.');
      }

      incoming[operation.id] = operation;
    }

    _operations.addAll(incoming);
  }

  /// Registers multiple operations, replacing existing entries.
  void registerOrReplaceAll(Iterable<Operation> operations) {
    _checkNotDisposed();

    for (final operation in operations) {
      _operations[operation.id] = operation;
    }
  }

  // ---------------------------------------------------------------------------
  // Updating
  // ---------------------------------------------------------------------------

  /// Replaces the currently registered operation with [operation].
  ///
  /// The operation must already be registered.
  void update(Operation operation) {
    _checkNotDisposed();

    if (!_operations.containsKey(operation.id)) {
      throw StateError('Operation "${operation.id.value}" is not registered.');
    }

    _operations[operation.id] = operation;
  }

  /// Updates an operation using [transform].
  ///
  /// Throws [StateError] when the operation is not registered.
  Operation updateWith(OperationId id, Operation Function(Operation operation) transform) {
    _checkNotDisposed();

    final current = require(id);
    final updated = transform(current);

    if (updated.id != id) {
      throw StateError(
        'Operation update cannot change its ID: '
        '"${id.value}" -> "${updated.id.value}".',
      );
    }

    _operations[id] = updated;

    return updated;
  }

  /// Applies [operation] to the registry.
  ///
  /// If the operation is already registered, it is replaced. Otherwise it is
  /// registered.
  void upsert(Operation operation) {
    _checkNotDisposed();

    _operations[operation.id] = operation;
  }

  // ---------------------------------------------------------------------------
  // Removal
  // ---------------------------------------------------------------------------

  /// Removes an operation by ID.
  ///
  /// Returns the removed operation, or `null` when it was not registered.
  Operation? remove(OperationId id) {
    if (_disposed) {
      return null;
    }

    return _operations.remove(id);
  }

  /// Removes an operation only when it is terminal.
  ///
  /// Returns `true` when an operation was removed.
  bool removeTerminal(OperationId id) {
    if (_disposed) {
      return false;
    }

    final operation = _operations[id];

    if (operation == null || !operation.isTerminal) {
      return false;
    }

    _operations.remove(id);
    return true;
  }

  /// Removes all terminal operations.
  ///
  /// Returns the number of removed operations.
  int removeTerminalOperations() {
    if (_disposed) {
      return 0;
    }

    final idsToRemove =
        _operations.values
            .where((operation) => operation.isTerminal)
            .map((operation) => operation.id)
            .toList(growable: false)
          ..forEach(_operations.remove);

    return idsToRemove.length;
  }

  /// Removes operations matching [predicate].
  ///
  /// Returns the number of removed operations.
  int removeWhere(bool Function(Operation operation) predicate) {
    if (_disposed) {
      return 0;
    }

    final idsToRemove = <OperationId>[];

    for (final operation in _operations.values) {
      if (predicate(operation)) {
        idsToRemove.add(operation.id);
      }
    }

    idsToRemove.forEach(_operations.remove);

    return idsToRemove.length;
  }

  /// Clears all registered operations.
  void clear() {
    if (_disposed) {
      return;
    }

    _operations.clear();
  }

  // ---------------------------------------------------------------------------
  // State queries
  // ---------------------------------------------------------------------------

  /// Whether at least one operation is currently running.
  bool get hasActiveOperations => _operations.values.any((operation) => operation.isRunning);

  /// Whether at least one operation is pending.
  bool get hasPendingOperations => _operations.values.any((operation) => operation.isPending);

  /// Whether at least one operation is terminal.
  bool get hasTerminalOperations => _operations.values.any((operation) => operation.isTerminal);

  /// Returns the first active operation, if any.
  Operation? get firstActive {
    for (final operation in _operations.values) {
      if (operation.isRunning) {
        return operation;
      }
    }

    return null;
  }

  /// Returns the first pending operation, if any.
  Operation? get firstPending {
    for (final operation in _operations.values) {
      if (operation.isPending) {
        return operation;
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Resets the registry by removing all operations.
  ///
  /// This does not mutate the operations themselves.
  void reset() {
    if (_disposed) {
      return;
    }

    _operations.clear();
  }

  /// Disposes the registry.
  ///
  /// Disposing the registry does not cancel, fail, or otherwise mutate
  /// registered operations. It only releases the registry's ownership of
  /// them.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _operations.clear();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('OperationRegistry has been disposed.');
    }
  }

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  @override
  String toString() {
    return 'OperationRegistry('
        'count: ${_operations.length}, '
        'active: $activeCount, '
        'pending: $pendingCount, '
        'terminal: $terminalCount, '
        'disposed: $_disposed'
        ')';
  }
}
