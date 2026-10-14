import 'dart:async';
import 'package:media_core/presentation/pip_state.dart';
import 'package:rxdart/rxdart.dart';

/// Controls picture-in-picture lifecycle.
///
/// This controller only manages logical PiP state.
///
/// It does not:
///
/// - call Android PiP API
/// - call iOS AVPictureInPictureController
/// - manage windows
///
/// Platform adapters are responsible for applying
/// native PiP operations and reporting results.
final class PipController {
  /// Creates PiP controller.
  PipController();

  final BehaviorSubject<PipState> _stateSubject = BehaviorSubject<PipState>.seeded(PipState.initial());

  Future<void> _operation = Future<void>.value();

  bool _disposed = false;

  int _generation = 0;

  /// Current PiP state stream.
  ValueStream<PipState> get state => _stateSubject.stream;

  /// Current PiP state.
  PipState get current => _stateSubject.value;

  /// Whether controller disposed.
  bool get isDisposed => _disposed;

  /// Current lifecycle generation.
  int get generation => _generation;

  /// Whether PiP active.
  bool get isPip => current.active;

  /// Whether PiP available.
  bool get available => current.available;

  /// Requests entering PiP.
  ///
  /// Actual native PiP operation is performed
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

  /// Requests leaving PiP.
  ///
  /// Actual native exit operation is performed
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

  /// Toggle PiP.
  Future<void> toggle() {
    if (isPip) {
      return exit();
    }

    return enter();
  }

  /// Updates PiP state from platform adapter.
  ///
  /// Old generation callbacks are ignored.
  void update(PipState state) {
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

  /// Updates PiP availability.
  void updateAvailability({required bool available}) {
    _ensureNotDisposed();

    _stateSubject.add(current.copyWith(available: available));
  }

  /// Enables or disables PiP.
  void updateEnabled({required bool enabled}) {
    _ensureNotDisposed();

    _stateSubject.add(current.copyWith(enabled: enabled));
  }

  /// Serializes PiP operations.
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _operation.then((_) => action());

    _operation = next.catchError((_) {});

    return next;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PipController has already been disposed.');
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
