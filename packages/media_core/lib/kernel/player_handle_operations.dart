part of 'player_handle.dart';

/// Operation records and the serialization/generation guards every
/// backend operation runs through.
///
/// Records are the diagnostic surface for "what did the player actually
/// do, in what order, and what failed"; the guards make sure a stale
/// lifecycle transition can never commit state.
extension PlayerHandleOperations on PlayerHandle {
  /// Live stream of recorded operations.
  Stream<Operation> get onOperation => _operationTracker.operations;

  /// The operation currently in flight, if any.
  Operation? get currentOperation => _currentOperation;

  /// Records the start of an operation of [type].
  ///
  /// A still-running previous operation is cancelled, not abandoned: two
  /// overlapping records would leave one permanently in flight.
  ///
  /// Finished records are pruned as the next one starts — a live session opens
  /// one record per task and the feed one per item, so without a bound the
  /// registry and the tracker keep every operation of the handle's lifetime.
  /// Pruning on start (rather than on completion) keeps the most recent
  /// outcome readable.
  void beginOperation(OperationType type) {
    if (!_canRecordOperations) {
      return;
    }

    _operationRegistry.removeTerminalOperations();
    _operationTracker.untrackTerminal();

    final previous = _currentOperation;

    if (previous != null && !previous.isTerminal) {
      final cancelled = previous.cancel();

      _operationRegistry.update(cancelled);
      _operationTracker.update(cancelled);
    }

    final operation = Operation.created(id: OperationId.generate(), type: type);

    _operationRegistry.register(operation);
    _operationTracker.track(operation);

    final started = operation.start();

    _operationRegistry.update(started);
    _operationTracker.update(started);

    _currentOperation = started;
  }

  /// Records the current operation as completed.
  void completeOperation() {
    final operation = _currentOperation;

    if (operation == null || operation.isTerminal) {
      return;
    }

    _currentOperation = null;

    final completed = operation.complete();

    if (!_canRecordOperations) {
      return;
    }

    _operationRegistry.update(completed);
    _operationTracker.update(completed);
  }

  /// Records the current operation as failed.
  void failOperation() {
    final operation = _currentOperation;

    if (operation == null || operation.isTerminal) {
      return;
    }

    _currentOperation = null;

    final failed = operation.fail();

    if (!_canRecordOperations) {
      return;
    }

    _operationRegistry.update(failed);
    _operationTracker.update(failed);
  }

  /// Whether operation records can still be written.
  ///
  /// [dispose] closes the registry and the tracker from inside its own
  /// operation, so the record written when that operation settles has no
  /// reader left — and writing it throws. Every other operation that was
  /// queued before disposal is in the same position.
  bool get _canRecordOperations {
    return !_operationRegistry.isDisposed && !_operationTracker.isDisposed;
  }

  /// Wraps [future] as a recorded operation of [type].
  ///
  /// The operation opens when [future] starts and closes when it settles,
  /// so consumers listening to [onOperation] see exactly the lifecycle
  /// methods the handle executed, in order, with their outcome.
  Future<T> _record<T>(OperationType type, Future<T> future) {
    beginOperation(type);

    return future.then(
      (value) {
        completeOperation();

        return value;
      },
      onError: (Object error, StackTrace stackTrace) {
        failOperation();

        throw Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Operation lifecycle
  // ---------------------------------------------------------------------------

  /// Invalidates all currently running and queued lifecycle operations.
  ///
  /// This does not attempt to cancel an already running native Future.
  /// Instead, it makes the operation stale so it cannot commit any
  /// state or continue with a follow-up backend command after it
  /// returns.
  int _invalidateOperations() {
    final generation = ++_operationGeneration;

    _cancelActiveOperation(StateError('PlayerIdentity operation superseded by lifecycle generation $generation.'));

    return generation;
  }

  /// Cancels the currently active playback/recovery continuation.
  void _cancelActiveOperation([Object? reason]) {
    final token = _activeCancelToken;

    if (token == null) {
      return;
    }

    _activeCancelToken = null;

    token
      ..cancel(reason ?? StateError('PlayerIdentity operation was cancelled.'))
      ..dispose();
  }

  /// Creates a new cancellation token for a playback/recovery operation.
  OperationCancelToken _createOperationToken() {
    _cancelActiveOperation(StateError('Previous player continuation was superseded.'));

    final token = OperationCancelToken();
    _activeCancelToken = token;

    return token;
  }

  /// Releases an operation token if it is still active.
  void _releaseOperationToken(OperationCancelToken token) {
    if (identical(_activeCancelToken, token)) {
      _activeCancelToken = null;
    }

    token.dispose();
  }

  /// Returns whether [generation] is still the current lifecycle generation.
  bool _isOperationCurrent(int generation) {
    return !_disposed && generation == _operationGeneration;
  }

  /// Returns whether an operation still owns [source].
  bool _isSourceCurrent(PlayerSource source) {
    return !_disposed && _currentSource?.id == source.id;
  }

  /// Returns whether an operation still owns [sourceId].
  bool _isSourceIdCurrent(Object sourceId) {
    return !_disposed && _currentSource?.id == sourceId;
  }

  /// Captures the current operation generation.
  int _captureOperationGeneration() {
    _ensureNotDisposed();
    return _operationGeneration;
  }

  /// Runs [action] after all previously queued operations complete.
  ///
  /// Errors are preserved for the caller while the internal queue
  /// remains usable for subsequent operations.
  Future<T> _enqueue<T>(Future<T> Function() action, {bool allowDisposed = false}) {
    // Not `async`: `.then` flattens the returned Future anyway, so the queue
    // ordering and the error routing are unchanged, and `_ensureNotDisposed`
    // still reaches the caller as a rejected `next`.
    final next = _operation.then<T>((_) {
      if (!allowDisposed) {
        _ensureNotDisposed();
      }

      return action();
    });

    _operation = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});

    return next;
  }

  /// Waits until all currently queued backend operations have settled.
  Future<void> _drainOperations() async {
    try {
      await _operation;
    } on Object catch (_) {
      // The queue itself already preserves later operations.
    }
  }

  /// Ensures the handle is still alive.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PlayerHandle for ${_player.id} has been disposed.');
    }
  }

  /// Ensures a source is currently open.
  void _ensureSource() {
    if (_currentSource == null || !_backendReady) {
      throw StateError('PlayerHandle for ${_player.id} has no open source.');
    }
  }

  /// Ensures the backend is currently ready for playback commands.
  bool _canUseBackend({required int operationGeneration, PlayerSource? source}) {
    if (!_isOperationCurrent(operationGeneration)) {
      return false;
    }

    if (!_backendReady) {
      return false;
    }

    if (source != null && !_isSourceCurrent(source)) {
      return false;
    }

    return true;
  }
}
