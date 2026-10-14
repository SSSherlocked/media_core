import 'dart:async';

/// Lifecycle states used by stream-based services and controllers.
enum StreamLifecycleState {
  /// Built but not initialized yet.
  created,

  /// An initialization operation is in flight.
  initializing,

  /// Initialization succeeded and the service is usable.
  ready,

  /// In use, for example a visible page or an attached player.
  active,

  /// Temporarily out of use but still restorable.
  inactive,

  /// Teardown has begun; new operations are no longer accepted.
  disposing,

  /// Teardown finished and the instance may never be reused.
  disposed,
}

/// Lightweight lifecycle manager.
///
/// It provides:
/// - lifecycle state
/// - generation tracking
/// - safe async execution
/// - initialization protection
/// - disposal protection
class StreamLifecycle {
  /// Starts in [initialState], by default [StreamLifecycleState.created].
  StreamLifecycle({StreamLifecycleState initialState = StreamLifecycleState.created}) : _state = initialState;

  StreamLifecycleState _state;

  int _generation = 0;
  bool _disposed = false;
  bool _initializing = false;

  /// Current lifecycle state.
  StreamLifecycleState get state => _state;

  /// Generation the running operations were started in.
  int get generation => _generation;

  /// Whether nothing has been initialized yet.
  bool get isCreated => _state == StreamLifecycleState.created;

  /// Whether an initialization operation is in flight.
  bool get isInitializing => _state == StreamLifecycleState.initializing;

  /// Whether initialization finished and the service is usable.
  bool get isReady => _state == StreamLifecycleState.ready;

  /// Whether the lifecycle is currently in use.
  bool get isActive => _state == StreamLifecycleState.active;

  /// Whether the lifecycle is temporarily out of use.
  bool get isInactive => _state == StreamLifecycleState.inactive;

  /// Whether teardown has begun.
  bool get isDisposing => _state == StreamLifecycleState.disposing;

  /// Whether teardown finished.
  bool get isDisposed => _state == StreamLifecycleState.disposed;

  /// Whether operations may still be started.
  bool get isAlive => !_disposed;

  /// Whether an operation may run right now.
  ///
  /// [StreamLifecycleState.disposing] is excluded because a service that is
  /// winding down must not accept work it cannot finish cleanly.
  bool get canOperate => !_disposed && _state != StreamLifecycleState.disposing;

  /// Move to a new lifecycle state.
  void transition(StreamLifecycleState newState) {
    if (_disposed && newState != StreamLifecycleState.disposed) {
      return;
    }

    _state = newState;

    if (newState == StreamLifecycleState.disposed) {
      _disposed = true;
    }
  }

  /// Start a new generation.
  ///
  /// Any asynchronous operation using the previous generation becomes stale.
  int nextGeneration() {
    if (_disposed) {
      throw StateError('StreamLifecycle has been disposed.');
    }

    return ++_generation;
  }

  /// Invalidate all currently running generations.
  int invalidate() {
    if (_disposed) {
      return _generation;
    }

    return ++_generation;
  }

  /// Check whether [generation] is still valid.
  bool isCurrent(int generation) {
    return !_disposed && generation == _generation;
  }

  /// Run an operation only when the lifecycle is alive.
  Future<T> run<T>(Future<T> Function() action) async {
    _ensureAlive();

    return await action();
  }

  /// Run an operation and ensure that its generation is still current
  /// before returning the result.
  Future<T?> runLatest<T>(Future<T> Function() action) async {
    _ensureAlive();

    final generation = _generation;

    final result = await action();

    if (!isCurrent(generation)) {
      return null;
    }

    return result;
  }

  /// Initialize the lifecycle once.
  ///
  /// Multiple concurrent callers share the same initialization Future.
  Future<void> initialize(FutureOr<void> Function() action) {
    if (_disposed) {
      return Future<void>.error(StateError('StreamLifecycle has been disposed.'));
    }

    if (_initializing) {
      return _initializationFuture ?? Future<void>.error(StateError('Initialization state is invalid.'));
    }

    if (isReady || isActive) {
      return Future<void>.value();
    }

    _initializing = true;
    transition(StreamLifecycleState.initializing);

    final future = _initializeInternal(action);

    _initializationFuture = future;

    return future;
  }

  Future<void>? _initializationFuture;

  Future<void> _initializeInternal(FutureOr<void> Function() action) async {
    try {
      await action();

      if (_disposed) {
        return;
      }

      transition(StreamLifecycleState.ready);
    } catch (_) {
      if (!_disposed) {
        transition(StreamLifecycleState.created);
      }

      rethrow;
    } finally {
      _initializing = false;
    }
  }

  /// Mark the lifecycle as active.
  void activate() {
    if (!_disposed) {
      transition(StreamLifecycleState.active);
    }
  }

  /// Mark the lifecycle as inactive.
  void deactivate() {
    if (!_disposed) {
      transition(StreamLifecycleState.inactive);
    }
  }

  /// Mark the lifecycle as ready.
  void markReady() {
    if (!_disposed) {
      transition(StreamLifecycleState.ready);
    }
  }

  /// Dispose the lifecycle.
  ///
  /// Running Futures cannot be forcibly cancelled.
  /// They are invalidated through generation tracking.
  void dispose() {
    if (_disposed) {
      return;
    }

    _generation++;
    _state = StreamLifecycleState.disposing;

    _disposed = true;
    _state = StreamLifecycleState.disposed;
  }

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('StreamLifecycle has been disposed.');
    }
  }
}

/// Lifecycle scope that automatically owns cleanup callbacks.
class StreamLifecycleScope {
  /// Creates a live scope with an empty cleanup list.
  StreamLifecycleScope();

  /// Lifecycle this scope drives; cleanups run when it is disposed.
  final StreamLifecycle lifecycle = StreamLifecycle();

  final List<FutureOr<void> Function()> _cleanups = <FutureOr<void> Function()>[];

  /// Whether the scope still accepts work and cleanups.
  bool get isAlive => lifecycle.isAlive;

  /// Whether [dispose] already ran.
  bool get isDisposed => lifecycle.isDisposed;

  /// Current state of the owned [lifecycle].
  StreamLifecycleState get state => lifecycle.state;

  /// Generation the owned [lifecycle] is on, used to detect stale results.
  int get generation => lifecycle.generation;

  /// Register a cleanup callback.
  void addCleanup(FutureOr<void> Function() cleanup) {
    if (isDisposed) {
      return;
    }

    _cleanups.add(cleanup);
  }

  /// Execute an operation with the current generation.
  Future<T?> latest<T>(Future<T> Function() action) {
    return lifecycle.runLatest(action);
  }

  /// Invalidate the current operation generation.
  void invalidate() {
    lifecycle.invalidate();
  }

  /// Dispose the scope and execute cleanups.
  Future<void> dispose() async {
    if (isDisposed) {
      return;
    }

    lifecycle.dispose();

    final cleanups = List<FutureOr<void> Function()>.from(_cleanups);

    _cleanups.clear();

    Object? firstError;
    StackTrace? firstStackTrace;

    for (final cleanup in cleanups.reversed) {
      try {
        await cleanup();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}
