import 'package:media_core/identity/player_id.dart';
import 'package:media_core/kernel/player_kernel.dart' show PlayerKernel;
import 'package:media_core/presentation/presentation_request.dart';

/// Driver interface for presentation capability packages.
///
/// A [KernelPresentationDriver] is attached to a [PlayerKernel]
/// by assigning [PlayerKernel.presentationDriver] and performs platform
/// presentation transitions for a player: fullscreen, picture-in-picture and
/// floating windows.
///
/// The kernel owns which player requests a transition; the driver
/// owns the platform mechanics (window manager, system PiP APIs).
///
/// Implementations:
///
/// - `media_core_presentation` (window_manager: fullscreen and an
///   always-on-top small window on Windows, macOS and Linux)
/// - `media_core_presentation_mobile` (Android/iOS: system
///   picture-in-picture and a host-owned small window)
///
/// It does not:
///
/// - decide which presentation mode to use
/// - own presentation state
///
/// Those belong to:
///
/// - the application
/// - presentation module (PresentationController)
abstract interface class KernelPresentationDriver {
  /// Applies a presentation transition for [playerId].
  ///
  /// [request] carries the target mode and options. Drivers that
  /// cannot serve a mode should throw [UnsupportedError].
  Future<void> apply(PlayerId playerId, PresentationRequest request);

  /// Releases driver resources.
  Future<void> dispose();
}
