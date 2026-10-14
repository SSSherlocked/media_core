import 'package:media_core/fallback/backend_fallback_state.dart';

/// Coordinates fallback between media backends.
///
/// This class owns only backend candidate selection and lifecycle state.
///
/// It does not:
///
/// - create a backend
/// - initialize a decoder
/// - open media
/// - control playback
/// - perform platform-specific operations
final class BackendFallback {
  /// Creates a backend fallback coordinator, optionally seeded with [initialState].
  BackendFallback({BackendFallbackState initialState = const BackendFallbackState.initial()}) : _state = initialState;

  BackendFallbackState _state;

  bool _disposed = false;

  /// The current backend fallback lifecycle state.
  BackendFallbackState get state => _state;

  /// The backend currently being attempted, or `null` before one is selected.
  String? get currentBackend => _state.currentBackend;

  /// The ordered backend candidates this coordinator may fall back through.
  List<String> get candidates => _state.candidates;

  /// Whether another backend candidate is still available to fall back to.
  bool get canFallback => _state.canFallback;

  /// Starts a new backend fallback lifecycle.
  void start(List<String> backends, {String? currentBackend}) {
    _ensureNotDisposed();

    _state = _state.start(candidates: backends, currentBackend: currentBackend);
  }

  /// Selects the next backend.
  ///
  /// Returns `null` when no candidate is available.
  String? next() {
    _ensureNotDisposed();

    final backend = _state.nextBackend;

    if (backend == null) {
      _state = _state.exhaust();
      return null;
    }

    _state = _state.select(backend);

    return backend;
  }

  /// Marks the current backend attempt as failed.
  void markFailed() {
    _ensureNotDisposed();

    _state = _state.markFailed();
  }

  /// Marks the selected backend as successfully completed.
  void complete() {
    _ensureNotDisposed();

    _state = _state.complete();
  }

  /// Marks backend fallback as exhausted.
  void exhaust() {
    _ensureNotDisposed();

    _state = _state.exhaust();
  }

  /// Resets backend fallback.
  void reset() {
    _ensureNotDisposed();

    _state = _state.reset();
  }

  /// Releases this fallback coordinator.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('BackendFallback has been disposed.');
    }
  }
}
