import 'dart:async';
import 'package:media_core/presentation/fullscreen_state.dart';
import 'package:rxdart/rxdart.dart';

/// Controls fullscreen lifecycle.
///
/// This controller only manages logical fullscreen state.
///
/// It does not:
///
/// - change system UI mode
/// - lock orientation
/// - call native fullscreen APIs
///
/// Platform adapters are responsible for applying
/// fullscreen operations.
final class FullscreenController {
  /// Creates fullscreen controller.
  FullscreenController();

  final BehaviorSubject<FullscreenState> _stateSubject = BehaviorSubject<FullscreenState>.seeded(
    FullscreenState.initial(),
  );

  Future<void> _operation = Future<void>.value();

  bool _disposed = false;

  int _generation = 0;

  /// Current fullscreen state stream.
  ValueStream<FullscreenState> get state => _stateSubject.stream;

  /// Current fullscreen state.
  FullscreenState get current => _stateSubject.value;

  /// Whether controller disposed.
  bool get isDisposed => _disposed;

  /// Whether fullscreen active.
  bool get isFullscreen => current.active;

  /// Current lifecycle generation.
  int get generation => _generation;

  /// Requests entering fullscreen.
  ///
  /// Actual fullscreen operation is handled
  /// by platform adapter.
  Future<void> enter() {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!current.canEnter) {
        return;
      }

      final generation = ++_generation;

      _stateSubject.add(current.copyWith(transitioning: true, generation: generation, error: null));
    });
  }

  /// Requests exiting fullscreen.
  ///
  /// Actual exit operation is handled
  /// by platform adapter.
  Future<void> exit() {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!current.canExit) {
        return;
      }

      final generation = ++_generation;

      _stateSubject.add(current.copyWith(transitioning: true, generation: generation, error: null));
    });
  }

  /// Toggle fullscreen.
  Future<void> toggle() {
    if (isFullscreen) {
      return exit();
    }

    return enter();
  }

  /// Updates state from platform adapter.
  ///
  /// Older generations are ignored.
  void update(FullscreenState state) {
    _ensureNotDisposed();

    // Generation 0 means the update is not tied to a request — the platform
    // reporting its own state — and is always accepted.
    if (state.generation != 0 && state.generation < _generation) {
      return;
    }

    if (state.generation > _generation) {
      _generation = state.generation;
    }

    _stateSubject.add(state);
  }

  /// Updates fullscreen availability.
  void updateAvailability({required bool available}) {
    _ensureNotDisposed();

    _stateSubject.add(current.copyWith(available: available));
  }

  /// Serializes operations.
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _operation.then((_) => action());

    _operation = next.catchError((_) {});

    return next;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('FullscreenController has already been disposed.');
    }
  }

  /// Releases resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _operation;

    await _stateSubject.close();
  }
}
