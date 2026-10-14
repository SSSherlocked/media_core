import 'dart:async';
import 'package:media_core/presentation/floating_state.dart';
import 'package:rxdart/rxdart.dart';

/// Controls floating presentation lifecycle.
///
/// This controller only manages logical floating state.
///
/// It does not:
///
/// - create overlay windows
/// - manage window position
/// - call native APIs
///
/// Platform adapters are responsible for applying
/// floating operations.
///
/// Nothing in the package constructs this controller: floating window support
/// was superseded by system picture-in-picture (`native_picture_in_picture`),
/// so this is a logical-only controller left for a host that still drives the
/// legacy floating path. It does nothing until a host instantiates it and feeds
/// adapter results through [update].
final class FloatingController {
  /// Creates a controller seeded with the initial floating state.
  FloatingController();

  final BehaviorSubject<FloatingState> _stateSubject = BehaviorSubject<FloatingState>.seeded(FloatingState.initial());

  Future<void> _operation = Future<void>.value();

  bool _disposed = false;

  int _generation = 0;

  /// Current state stream.
  ValueStream<FloatingState> get state => _stateSubject.stream;

  /// Current state.
  FloatingState get current => _stateSubject.value;

  /// Current generation.
  int get generation => _generation;

  /// Whether disposed.
  bool get isDisposed => _disposed;

  /// Whether floating active.
  bool get isFloating => current.active;

  /// Requests entering floating mode.
  ///
  /// Actual platform operation is handled
  /// by PresentationAdapter.
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

  /// Requests leaving floating mode.
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

  /// Toggle floating.
  Future<void> toggle() {
    if (isFloating) {
      return exit();
    }

    return enter();
  }

  /// Updates state from platform adapter.
  ///
  /// Old generations are ignored.
  void update(FloatingState state) {
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

  /// Updates platform availability.
  void updateAvailability({required bool available}) {
    _ensureNotDisposed();

    _stateSubject.add(current.copyWith(available: available));
  }

  /// Updates user/application enable state.
  void updateEnabled({required bool enabled}) {
    _ensureNotDisposed();

    _stateSubject.add(current.copyWith(enabled: enabled));
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _operation.then((_) => action());

    _operation = next.catchError((_) {});

    return next;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('FloatingController has already been disposed.');
    }
  }

  /// Releases resources; further calls to this controller throw.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _operation;

    await _stateSubject.close();
  }
}
