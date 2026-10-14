import 'package:flutter/widgets.dart';
import 'package:media_core/media_core.dart' show VideoOrientation;

import 'package:media_core_presentation/src/media_core_presentation.dart';
import 'package:media_core_presentation/src/presentation_capability_config.dart';
import 'package:media_core_presentation/src/widgets/player_overlay.dart';

/// Orientation-aware fullscreen stage for one player.
///
/// Composes the orientation-aware video layout with the generic
/// [MediaPlayerOverlay] layer system — whatever the app wants on
/// top of the video (danmaku, subtitles, controls, badges,
/// watermarks...) goes in as a [PlayerOverlayLayer]:
///
/// ```text
/// ┌──────────────────────────────┐
/// │ orientation-aware video slot │  landscape → straight
/// │   (fit / fill / rotate)      │  portrait  → strategy
/// │ + arbitrary overlay layers   │  (top/center/bottom/corners)
/// └──────────────────────────────┘
/// ```
///
/// ```dart
/// PresentationStage(
///   presentation: presentation,
///   videoBuilder: (context, orientation) => MediaKitVideoView(adapter: a),
///   layers: [
///     PlayerOverlayLayer(
///       slot: PlayerOverlaySlot.bottom,
///       visibility: PlayerOverlayVisibility.withControls,
///       builder: (_) => MyControlBar(),
///     ),
///     PlayerOverlayLayer(
///       slot: PlayerOverlaySlot.center,
///       ignorePointer: true,
///       builder: (_) => DanmakuView(...),   // or subtitles, art...
///     ),
///   ],
/// )
/// ```
class PresentationStage extends StatelessWidget {
  /// Creates the stage.
  const PresentationStage({
    required this.presentation,
    required this.videoBuilder,
    super.key,
    this.orientation,
    this.layers = const <PlayerOverlayLayer>[],
    this.onTap,
    this.visible,
  });

  /// The presentation capability providing orientation and hover
  /// behaviour.
  final MediaCorePresentation presentation;

  /// Builds the video surface.
  ///
  /// Receives the current video orientation so the app can pick
  /// the right surface (e.g. rotated vs straight).
  final Widget Function(BuildContext context, VideoOrientation orientation) videoBuilder;

  /// Forced video orientation override.
  ///
  /// Null falls back to the presentation's tracked orientation
  /// (fed from adapter events via `observeKernel`).
  final VideoOrientation? orientation;

  /// Arbitrary overlay layers above the video.
  final List<PlayerOverlayLayer> layers;

  /// Tap callback on the video area.
  final VoidCallback? onTap;

  /// Forced visibility of withControls layers.
  final bool? visible;

  @override
  Widget build(BuildContext context) {
    final config = presentation.config;
    final orientation = this.orientation ?? presentation.orientation;

    final Widget video;
    switch (orientation) {
      case VideoOrientation.landscape:
        video = videoBuilder(context, orientation);
      case VideoOrientation.portrait:
        video = switch (config.portraitFullscreenStrategy) {
          PortraitFullscreenStrategy.fill => _Filled(video: videoBuilder(context, orientation)),
          PortraitFullscreenStrategy.rotate => _Rotated(video: videoBuilder(context, orientation)),
          PortraitFullscreenStrategy.fit => Center(
            child: AspectRatio(aspectRatio: 9 / 16, child: videoBuilder(context, orientation)),
          ),
        };
      case VideoOrientation.square:
        video = Center(child: AspectRatio(aspectRatio: 1, child: videoBuilder(context, orientation)));
      case VideoOrientation.unknown:
        video = Center(child: videoBuilder(context, orientation));
    }

    return MediaPlayerOverlay(
      hoverMode: presentation.overlayHoverMode,
      hoverAutoHideDelay: config.overlayAutoHideDelay,
      layers: layers,
      onTap: onTap,
      visible: visible,
      child: ColoredBox(color: const Color(0xFF000000), child: video),
    );
  }
}

class _Filled extends StatelessWidget {
  const _Filled({required this.video});

  final Widget video;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FittedBox(fit: BoxFit.cover, child: video),
    );
  }
}

class _Rotated extends StatelessWidget {
  const _Rotated({required this.video});

  final Widget video;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(quarterTurns: 1, child: SizedBox.expand(child: video));
  }
}
