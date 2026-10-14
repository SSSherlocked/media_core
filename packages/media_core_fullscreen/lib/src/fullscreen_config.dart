import 'package:media_core/media_core.dart' show FullscreenFitStrategy, VideoOrientation;

/// Tunables for fullscreen, including how each orientation is presented.
///
/// The strategy knobs exist because "fullscreen" is not one layout: a portrait
/// stream on a portrait phone fills the screen, the same stream on a landscape
/// monitor is letterboxed (or rotated), and a landscape stream on a portrait
/// phone is either letterboxed or cropped. Encoding the two answers here keeps
/// the decision out of every host widget.
final class FullscreenConfig {
  /// Creates a fullscreen configuration with the given fit strategies.
  const FullscreenConfig({
    this.restorePreviousBounds = true,
    this.portraitStrategy = FullscreenFitStrategy.fit,
    this.landscapeStrategy = FullscreenFitStrategy.fit,
    this.fallbackOrientation = VideoOrientation.landscape,
  });

  /// Caller-accepted defaults.
  static const FullscreenConfig defaults = FullscreenConfig();

  /// Whether leaving system fullscreen restores the previous window bounds.
  ///
  /// Desktop only: the platform restores nothing on its own, and a window that
  /// stays maximised after fullscreen is a visible bug.
  final bool restorePreviousBounds;

  /// How a portrait video is fitted when the presentation surface is not the
  /// same shape.
  final FullscreenFitStrategy portraitStrategy;

  /// How a landscape video is fitted.
  final FullscreenFitStrategy landscapeStrategy;

  /// Orientation assumed when the video size is unknown.
  final VideoOrientation fallbackOrientation;

  /// Returns a copy of this config with the supplied fields replaced.
  FullscreenConfig copyWith({
    bool? restorePreviousBounds,
    FullscreenFitStrategy? portraitStrategy,
    FullscreenFitStrategy? landscapeStrategy,
    VideoOrientation? fallbackOrientation,
  }) {
    return FullscreenConfig(
      restorePreviousBounds: restorePreviousBounds ?? this.restorePreviousBounds,
      portraitStrategy: portraitStrategy ?? this.portraitStrategy,
      landscapeStrategy: landscapeStrategy ?? this.landscapeStrategy,
      fallbackOrientation: fallbackOrientation ?? this.fallbackOrientation,
    );
  }
}
