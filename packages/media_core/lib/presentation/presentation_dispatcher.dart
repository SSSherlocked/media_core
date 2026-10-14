import 'package:media_core/presentation/floating_controller.dart';
import 'package:media_core/presentation/fullscreen_controller.dart';
import 'package:media_core/presentation/pip_controller.dart';
import 'package:media_core/presentation/presentation_mode.dart';
import 'package:media_core/presentation/presentation_request.dart';

/// Dispatches presentation requests.
///
/// Responsibilities:
///
/// - route fullscreen requests
/// - route PiP requests
/// - route floating requests
///
/// Does not:
///
/// - own presentation state
/// - manage lifecycle
/// - decide availability
/// - call native APIs directly
///
/// Native operations are implemented by:
///
/// - FullscreenController
/// - PipController
/// - FloatingController
///
/// Nothing in the package constructs this dispatcher; it is a host-facing
/// helper that routes requests to the three logical controllers above. Those
/// controllers are likewise built by the host, so the whole path is inert until
/// a host wires it.
final class PresentationDispatcher {
  /// Creates a dispatcher over the controllers it routes to.
  const PresentationDispatcher({this.fullscreenController, this.pipController, this.floatingController});

  /// Fullscreen controller, or `null` when fullscreen is not wired.
  final FullscreenController? fullscreenController;

  /// PiP controller, or `null` when PiP is not wired.
  final PipController? pipController;

  /// Floating controller, or `null` when floating is not wired.
  final FloatingController? floatingController;

  /// Dispatch request.
  Future<void> dispatch(PresentationRequest request) async {
    switch (request.mode) {
      case PresentationMode.normal:
        await exit();

      case PresentationMode.fullscreen:
      case PresentationMode.windowFullscreen:
        // Both variants serialize through the fullscreen controller; which one
        // is active is the state machine's business (PresentationState.mode)
        // and reaches the platform driver through the request.
        await enterFullscreen();

      case PresentationMode.pip:
        await enterPip();

      case PresentationMode.floating:
        await enterFloating();
    }
  }

  /// Enter fullscreen.
  Future<void> enterFullscreen() async {
    final controller = fullscreenController;

    if (controller == null) {
      throw StateError('Fullscreen controller unavailable.');
    }

    await controller.enter();
  }

  /// Exit fullscreen.
  Future<void> exitFullscreen() async {
    final controller = fullscreenController;

    if (controller == null) {
      return;
    }

    await controller.exit();
  }

  /// Enter PiP.
  Future<void> enterPip() async {
    final controller = pipController;

    if (controller == null) {
      throw StateError('PiP controller unavailable.');
    }

    await controller.enter();
  }

  /// Exit PiP.
  Future<void> exitPip() async {
    final controller = pipController;

    if (controller == null) {
      return;
    }

    await controller.exit();
  }

  /// Enter floating.
  Future<void> enterFloating() async {
    final controller = floatingController;

    if (controller == null) {
      throw StateError('Floating controller unavailable.');
    }

    await controller.enter();
  }

  /// Exit floating.
  Future<void> exitFloating() async {
    final controller = floatingController;

    if (controller == null) {
      return;
    }

    await controller.exit();
  }

  /// Exit all presentation modes.
  ///
  /// Order:
  ///
  /// 1. PiP
  /// 2. Floating
  /// 3. Fullscreen
  ///
  /// Because fullscreen usually owns
  /// the player surface.
  Future<void> exit() async {
    await exitPip();

    await exitFloating();

    await exitFullscreen();
  }
}
