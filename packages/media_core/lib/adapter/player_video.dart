import 'package:flutter/widgets.dart';
import 'package:media_core/adapter/player_adapter.dart' show PlayerAdapter;

/// Provides video rendering for a [PlayerAdapter].
///
/// This interface is intentionally separated from [PlayerAdapter] so the
/// playback abstraction does not require every adapter to expose a Flutter
/// widget.
///
/// Video-capable adapters may implement this interface, while audio-only,
/// background, test, or headless adapters do not need to provide video
/// rendering.
abstract interface class PlayerVideo {
  /// Whether video rendering is currently available.
  bool get available;

  /// Applies the viewport fit for the current source.
  ///
  /// Part of the presentation contract: every video-capable adapter owns
  /// a fit notifier its surface listens to, so a host drives the fit
  /// through here instead of reaching into adapter-specific config.
  void setVideoFit(BoxFit fit);

  /// Builds the video rendering widget.
  ///
  /// The returned widget is owned by the adapter and should be inserted into
  /// the application's widget tree by the outer UI layer.
  Widget build();

  /// Attaches the video renderer to the active playback surface.
  ///
  /// This is useful for engines such as SurfaceTexture / PlatformView based
  /// players where the rendering surface has an explicit lifecycle.
  Future<void> attach();

  /// Detaches the video renderer from the active playback surface.
  Future<void> detach();
}
