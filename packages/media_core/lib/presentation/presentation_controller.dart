import 'dart:async';

import 'package:media_core/geometry/video_orientation.dart';
import 'package:media_core/presentation/presentation_capabilities.dart';
import 'package:media_core/presentation/presentation_event.dart';
import 'package:media_core/presentation/presentation_mode.dart';
import 'package:media_core/presentation/presentation_reducer.dart';
import 'package:media_core/presentation/presentation_request.dart';
import 'package:media_core/presentation/presentation_state.dart';
import 'package:rxdart/rxdart.dart';

/// Controls presentation lifecycle state.
///
/// PresentationController is the core state machine
/// of presentation subsystem.
///
/// Responsibilities:
///
/// - own presentation state
/// - receive requests
/// - generate lifecycle events
/// - reduce events into state
/// - synchronize generations
///
/// Does not:
///
/// - call native APIs
/// - execute platform operations
/// - manage windows
/// - know Android/iOS/Desktop APIs
///
/// Platform operations are handled by:
///
/// PresentationAdapter
///
final class PresentationController {
  /// Creates a controller with an optional [reducer] and initial [capabilities].
  PresentationController({
    PresentationReducer reducer = const PresentationReducer(),
    PresentationCapabilities capabilities = const PresentationCapabilities(),
  }) : _reducer = reducer,
       _capabilities = capabilities;

  final PresentationReducer _reducer;

  PresentationCapabilities _capabilities;

  final BehaviorSubject<PresentationState> _stateSubject = BehaviorSubject.seeded(PresentationState.initial());

  Future<void> _operation = Future<void>.value();

  bool _disposed = false;

  int _generation = 0;

  // ============================================================
  // State
  // ============================================================

  /// Current presentation state stream.
  ValueStream<PresentationState> get state => _stateSubject.stream;

  /// Current state.
  PresentationState get current => _stateSubject.value;

  /// Current presentation mode.
  PresentationMode get mode => current.mode;

  /// Current capabilities.
  PresentationCapabilities get capabilities => _capabilities;

  /// Whether fullscreen active.
  bool get isFullscreen => current.isFullscreen;

  /// Whether PiP active.
  bool get isPip => current.isPip;

  /// Whether floating active.
  bool get isFloating => current.isFloating;

  // ============================================================
  // Capability
  // ============================================================

  /// Updates platform capabilities.
  ///
  /// Called by PresentationService
  /// when adapter reports changes.
  void updateCapabilities(PresentationCapabilities capabilities) {
    _ensureNotDisposed();

    _capabilities = capabilities;

    _stateSubject.add(current.copyWith(capabilities: capabilities));
  }

  /// Updates the media orientation the presentation describes.
  ///
  /// Called by whoever watches the video's geometry — normally the kernel's
  /// video-size events. Both fullscreen variants present differently per
  /// orientation, so this must be kept current even while no transition is
  /// running: the next fullscreen request reads it to choose a layout.
  ///
  /// A repeated orientation is ignored rather than republished, so a stream of
  /// geometry events does not turn into a stream of presentation states.
  void updateOrientation(VideoOrientation orientation) {
    _ensureNotDisposed();

    if (current.orientation == orientation) {
      return;
    }

    _stateSubject.add(current.copyWith(orientation: orientation));
  }

  // ============================================================
  // Request
  // ============================================================

  /// Accepts a presentation request.
  ///
  /// This only changes logical state.
  ///
  /// Actual platform execution is performed
  /// by PresentationAdapter.
  ///
  /// Returns the generation assigned to the request. Whoever executes it has
  /// to carry that generation back into the events it reports, otherwise the
  /// reducer cannot tell the callback apart from a stale one.
  Future<int> request(PresentationRequest request) {
    return _enqueue(() {
      _ensureNotDisposed();

      final generation = ++_generation;

      handleEvent(PresentationEvent.started(mode: request.mode, generation: generation, source: request.source));

      return generation;
    });
  }

  // ============================================================
  // Events
  // ============================================================

  /// Handles lifecycle events.
  ///
  /// An event with generation `0` is not tied to any request — the platform
  /// reporting its own state change, for example — and is always accepted. A
  /// request-scoped event is accepted only when it is at least as new as the
  /// state it would replace.
  void handleEvent(PresentationEvent event) {
    _ensureNotDisposed();

    if (event.generation != 0 && event.generation < current.generation) {
      return;
    }

    if (event.generation > _generation) {
      _generation = event.generation;
    }

    final next = _reducer.reduce(current, event);

    _stateSubject.add(next);
  }

  /// Force update state.
  ///
  /// Used by:
  ///
  /// - restore
  /// - persistence
  /// - external lifecycle
  void update(PresentationState state) {
    _ensureNotDisposed();

    if (state.generation < _generation) {
      return;
    }

    _generation = state.generation;

    _stateSubject.add(state);
  }

  /// Exit presentation.
  Future<void> exit() {
    return request(PresentationRequest.normal(source: 'controller'));
  }

  // ============================================================
  // Internal
  // ============================================================

  Future<T> _enqueue<T>(FutureOr<T> Function() action) {
    final next = _operation.then((_) => action());

    _operation = next.then((_) {}, onError: (Object _) {});

    return next;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PresentationController has already been disposed.');
    }
  }

  // ============================================================
  // Dispose
  // ============================================================

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
