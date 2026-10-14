/// Presentation capability for media_core.
///
/// Provides the orientation-aware presentation widgets and the desktop
/// window driver:
///
/// - landscape video → landscape fullscreen
/// - portrait video → portrait fullscreen (or rotated as configured)
/// - Windows / macOS / Linux: window_manager fullscreen plus an
///   always-on-top small window
/// - overlay layer (danmaku / controls) with hover-based visibility
///   on desktop and always-visible behaviour on touch devices
///
/// The application-owned floating window has been removed from this
/// project: picture-in-picture is native now (media_core_pip, on
/// native_picture_in_picture), and background playback/pause is owned by
/// `PlayerKernel`. What is still served here is the orientation geometry
/// and the overlay layer system.
///
/// Attach to a kernel:
///
/// ```dart
/// final presentation = MediaCorePresentation();
/// await presentation.initialize();
/// kernel.presentationDriver = presentation;
/// presentation.observeKernel(kernel);
/// await kernel.enterFullscreen(playerId);
/// ```
library;

export 'package:media_core_presentation/src/kernel_presentation_adapter.dart';
export 'package:media_core_presentation/src/media_core_presentation.dart';
export 'package:media_core_presentation/src/presentation_capability_config.dart';
export 'package:media_core_presentation/src/video_presentation_geometry.dart';
export 'package:media_core_presentation/src/widgets/player_overlay.dart';
export 'package:media_core_presentation/src/widgets/presentation_stage.dart';
