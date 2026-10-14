import 'dart:async';

import 'package:media_core/geometry/video_orientation.dart';
import 'package:media_core/presentation/floating_controller.dart';
import 'package:media_core/presentation/fullscreen_controller.dart';
import 'package:media_core/presentation/pip_controller.dart';
import 'package:media_core/presentation/presentation_controller.dart';
import 'package:media_core/presentation/presentation_mode.dart';
import 'package:media_core/presentation/presentation_request.dart';
import 'package:media_core/presentation/presentation_snapshot.dart';
import 'package:media_core/presentation/presentation_state.dart';

/// High level presentation manager.
///
/// Public entry point for player presentation.
///
/// Responsibilities:
///
/// - expose presentation API
/// - provide unified presentation state
/// - provide snapshot
/// - simplify player integration
///
/// Does not:
///
/// - call native APIs
/// - manage windows
/// - render UI
///
/// Nothing in the package constructs this manager; it is a host-facing facade
/// over a host-supplied [PresentationController]. It stays inert until a host
/// wires one in.
final class PresentationManager {
  /// Wraps [controller], optionally exposing the per-mode controllers alongside it.
  PresentationManager({
    required PresentationController controller,
    FullscreenController? fullscreenController,
    PipController? pipController,
    FloatingController? floatingController,
  }) : _controller = controller,
       _fullscreenController = fullscreenController,
       _pipController = pipController,
       _floatingController = floatingController {
    _subscription = _controller.state.listen((state) {
      _latestState = state;
    });
  }

  final PresentationController _controller;

  final FullscreenController? _fullscreenController;

  final PipController? _pipController;

  final FloatingController? _floatingController;

  late final StreamSubscription<PresentationState> _subscription;

  PresentationState _latestState = PresentationState.initial();

  bool _disposed = false;

  /// Presentation state stream.
  Stream<PresentationState> get state => _controller.state;

  /// Current snapshot.
  PresentationSnapshot get snapshot {
    final state = _latestState;

    return PresentationSnapshot(
      mode: state.mode,
      targetMode: state.targetMode,
      capabilities: state.capabilities,
      transitioning: state.transitioning,
      enabled: state.enabled,
      generation: state.generation,
      error: state.error,
    );
  }

  /// Whether this manager has been disposed.
  bool get isDisposed => _disposed;

  /// Current active mode.
  PresentationMode get mode => _latestState.mode;

  /// Target mode during transition.
  PresentationMode? get targetMode => _latestState.targetMode;

  /// Whether transition is running.
  bool get isTransitioning => _latestState.transitioning;

  /// Whether fullscreen active.
  bool get isFullscreen => mode == PresentationMode.fullscreen;

  /// Whether PiP active.
  bool get isPip => mode == PresentationMode.pip;

  /// Whether floating active.
  bool get isFloating => mode == PresentationMode.floating;

  /// Whether normal mode.
  bool get isNormal => mode == PresentationMode.normal;

  /// Whether switching to fullscreen.
  bool get isTransitioningToFullscreen => snapshot.isTransitioningToFullscreen;

  /// Whether window-level fullscreen is active.
  bool get isWindowFullscreen => snapshot.isWindowFullscreen;

  /// Whether either fullscreen variant is active.
  bool get isAnyFullscreen => snapshot.isAnyFullscreen;

  /// Whether switching to window-level fullscreen.
  bool get isTransitioningToWindowFullscreen => snapshot.isTransitioningToWindowFullscreen;

  /// Whether switching to PiP.
  bool get isTransitioningToPip => snapshot.isTransitioningToPip;

  /// Whether switching to floating.
  bool get isTransitioningToFloating => snapshot.isTransitioningToFloating;

  /// Updates the media orientation the presentation describes.
  void updateOrientation(VideoOrientation orientation) {
    _ensureNotDisposed();

    _controller.updateOrientation(orientation);
  }

  /// Orientation of the media currently being presented.
  VideoOrientation get orientation => _latestState.orientation;

  /// Requests presentation change.
  Future<void> request(PresentationRequest request) {
    _ensureNotDisposed();

    return _controller.request(request);
  }

  /// Enter fullscreen.
  Future<void> enterFullscreen() {
    return request(PresentationRequest.fullscreen());
  }

  /// Exit fullscreen.
  Future<void> exitFullscreen() {
    if (!isFullscreen) {
      return Future.value();
    }

    return exit();
  }

  /// Enter window-level fullscreen.
  ///
  /// Fills the application window; the system-fullscreen variant is
  /// [enterFullscreen]. The two are separate so a host can offer both without
  /// one silently implying the other.
  Future<void> enterWindowFullscreen() {
    return request(PresentationRequest.windowFullscreen());
  }

  /// Exit window-level fullscreen.
  Future<void> exitWindowFullscreen() {
    if (!isWindowFullscreen) {
      return Future.value();
    }

    return exit();
  }

  /// Enter PiP.
  Future<void> enterPip() {
    return request(PresentationRequest.pip());
  }

  /// Exit PiP.
  Future<void> exitPip() {
    if (!isPip) {
      return Future.value();
    }

    return exit();
  }

  /// Enter floating mode.
  Future<void> enterFloating() {
    return request(PresentationRequest.floating());
  }

  /// Exit current presentation mode.
  Future<void> exit() {
    return request(PresentationRequest.normal());
  }

  /// Change mode.
  Future<void> setMode(PresentationMode mode) {
    return request(PresentationRequest(mode: mode));
  }

  /// Toggle fullscreen.
  Future<void> toggleFullscreen() {
    if (isFullscreen) {
      return exitFullscreen();
    }

    return enterFullscreen();
  }

  /// Toggle window-level fullscreen.
  Future<void> toggleWindowFullscreen() {
    if (isWindowFullscreen) {
      return exitWindowFullscreen();
    }

    return enterWindowFullscreen();
  }

  /// Toggle PiP.
  Future<void> togglePip() {
    if (isPip) {
      return exitPip();
    }

    return enterPip();
  }

  /// Native fullscreen controller.
  FullscreenController? get fullscreenController => _fullscreenController;

  /// Native PiP controller.
  PipController? get pipController => _pipController;

  /// Native floating controller.
  FloatingController? get floatingController => _floatingController;

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PresentationManager has already been disposed.');
    }
  }

  /// Releases resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _subscription.cancel();

    await _controller.dispose();
  }
}
