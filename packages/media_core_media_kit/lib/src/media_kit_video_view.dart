import 'package:flutter/widgets.dart';

import 'package:media_core_media_kit/src/media_kit_player_adapter.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

/// Renders the surface owned by [MediaKitPlayerAdapter].
///
/// This is the reference implementation of a *custom* surface: it does
/// not call `adapter.build()`, it reads `adapter.videoController` and
/// `adapter.fitListenable` directly. That keeps the adapter as the
/// single owner of the mpv surface while letting the app own the widget
/// tree, controls and fullscreen behaviour.
///
/// Every parameter mirrors `mkv.Video`'s own constructor — there is no
/// adapter-side configuration object between the caller and the engine.
///
/// ```dart
/// MediaKitVideoView(adapter: myAdapter)
/// ```
class MediaKitVideoView extends StatelessWidget {
  const MediaKitVideoView({
    super.key,
    required this.adapter,
    this.controls,
    this.width,
    this.height,
    this.fill = const Color(0xFF000000),
    this.alignment = Alignment.center,
    this.aspectRatio,
    this.filterQuality = FilterQuality.low,
  });

  /// The adapter whose surface is rendered.
  final MediaKitPlayerAdapter adapter;

  /// Controls builder; null mounts no controls.
  final mkv.VideoControlsBuilder? controls;

  /// Fixed width of the viewport.
  final double? width;

  /// Fixed height of the viewport.
  final double? height;

  /// Background color behind the video.
  final Color fill;

  /// Alignment of the viewport.
  final Alignment alignment;

  /// Preferred aspect ratio of the viewport.
  final double? aspectRatio;

  /// Filter quality of the video texture.
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final controller = adapter.videoController;

    // The adapter owns the controller; before onInitialize there is no
    // surface to render, so collapse to nothing.
    if (controller == null) {
      return const SizedBox.shrink();
    }

    // fitListenable is the exact same notifier that `adapter.build()`
    // uses, so `adapter.setVideoFit(...)` re-renders this widget too.
    return ValueListenableBuilder<BoxFit>(
      valueListenable: adapter.fitListenable,
      builder: (context, fit, _) {
        return mkv.Video(
          controller: controller,
          fit: fit,
          controls: controls ?? mkv.NoVideoControls,
          // Background playback is the host's call (media_core's lifecycle
          // coordinator). Left on, the widget paused the player whenever the
          // app was paused, and the host resumed it: about a second of
          // silence at every switch away from the app.
          pauseUponEnteringBackgroundMode: false,
          width: width,
          height: height,
          fill: fill,
          alignment: alignment,
          aspectRatio: aspectRatio,
          filterQuality: filterQuality,
        );
      },
    );
  }

  /// No-op: [mkv.Video] owns its own surface lifecycle.
  Future<void> attach() async {}

  /// Symmetric no-op for [attach].
  Future<void> detach() async {}
}
