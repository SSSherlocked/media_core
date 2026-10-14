import 'package:media_core/media_core.dart' show VideoOrientation;

/// Strategy for presenting portrait videos in fullscreen.
enum PortraitFullscreenStrategy {
  /// Fill the screen, cropping the video horizontally.
  ///
  /// Standard shorts / TikTok behaviour on portrait screens.
  fill,

  /// Fit inside the screen with letterbox bars.
  ///
  /// Standard long-form behaviour (a portrait video on a desktop
  /// monitor gets black bars left and right).
  fit,

  /// Rotate the video 90° to use the full landscape screen.
  ///
  /// Users holding the phone sideways to watch a portrait video.
  /// Rotation is applied by the presentation layer, not by the
  /// backend.
  rotate,
}

/// Strategy for presenting landscape videos on portrait screens.
enum LandscapeOnPortraitStrategy {
  /// Letterbox the video (standard).
  fit,

  /// Crop vertically to fill a portrait screen.
  fill,
}

/// Configuration for the presentation capability.
final class PresentationCapabilityConfig {
  /// Creates the configuration.
  const PresentationCapabilityConfig({
    this.portraitFullscreenStrategy = PortraitFullscreenStrategy.fit,
    this.landscapeOnPortraitStrategy = LandscapeOnPortraitStrategy.fit,
    this.rotatePortraitFullscreen = false,
    this.fallbackOrientation = VideoOrientation.landscape,
    this.pipWidth = 320,
    this.pipHeight = 180,
    this.pipCornerSpacing = 16,
    this.pipSkipTaskbar = false,
    this.pipTitle = 'media_core PiP',
    this.exitPipRestoresWindow = true,
    this.overlayHoverMode = true,
    this.overlayAutoHideDelay = const Duration(seconds: 3),
    this.overlayDanmakuSafeZoneTop = 0.12,
    this.overlayDanmakuSafeZoneBottom = 0.22,
  });

  /// How a portrait video is presented in fullscreen.
  final PortraitFullscreenStrategy portraitFullscreenStrategy;

  /// How a landscape video is presented on a portrait screen.
  final LandscapeOnPortraitStrategy landscapeOnPortraitStrategy;

  /// Rotates portrait videos 90° in fullscreen regardless of the
  /// screen orientation.
  ///
  /// Only meaningful with
  /// [PortraitFullscreenStrategy.rotate].
  final bool rotatePortraitFullscreen;

  /// Fallback orientation when the video size is unknown.
  final VideoOrientation fallbackOrientation;

  /// Width of the floating PiP window (logical pixels).
  final double pipWidth;

  /// Height of the floating PiP window (logical pixels).
  ///
  /// Ignored when the video aspect ratio should be preserved
  /// (the driver adjusts height from the actual video size).
  final double pipHeight;

  /// Spacing between the PiP window and screen corners.
  final double pipCornerSpacing;

  /// Whether the PiP window hides from the taskbar.
  final bool pipSkipTaskbar;

  /// Window title of the PiP window.
  final String pipTitle;

  /// Whether exiting PiP restores the window to its pre-PiP state.
  final bool exitPipRestoresWindow;

  /// Whether overlays use hover-based show/hide (desktop) instead
  /// of always-visible (touch devices).
  ///
  /// Overridden automatically on touch-primary devices.
  final bool overlayHoverMode;

  /// Delay before overlays auto-hide while hovering idly.
  final Duration overlayAutoHideDelay;

  /// Top fraction of the video reserved for danmaku (0.0–1.0).
  ///
  /// Controls inside this zone stay below it.
  final double overlayDanmakuSafeZoneTop;

  /// Bottom fraction of the video reserved for controls.
  ///
  /// Danmaku does not enter this zone.
  final double overlayDanmakuSafeZoneBottom;

  /// Creates a copy with modifications.
  PresentationCapabilityConfig copyWith({
    PortraitFullscreenStrategy? portraitFullscreenStrategy,
    LandscapeOnPortraitStrategy? landscapeOnPortraitStrategy,
    bool? rotatePortraitFullscreen,
    VideoOrientation? fallbackOrientation,
    double? pipWidth,
    double? pipHeight,
    double? pipCornerSpacing,
    bool? pipSkipTaskbar,
    String? pipTitle,
    bool? exitPipRestoresWindow,
    bool? overlayHoverMode,
    Duration? overlayAutoHideDelay,
    double? overlayDanmakuSafeZoneTop,
    double? overlayDanmakuSafeZoneBottom,
  }) {
    return PresentationCapabilityConfig(
      portraitFullscreenStrategy: portraitFullscreenStrategy ?? this.portraitFullscreenStrategy,
      landscapeOnPortraitStrategy: landscapeOnPortraitStrategy ?? this.landscapeOnPortraitStrategy,
      rotatePortraitFullscreen: rotatePortraitFullscreen ?? this.rotatePortraitFullscreen,
      fallbackOrientation: fallbackOrientation ?? this.fallbackOrientation,
      pipWidth: pipWidth ?? this.pipWidth,
      pipHeight: pipHeight ?? this.pipHeight,
      pipCornerSpacing: pipCornerSpacing ?? this.pipCornerSpacing,
      pipSkipTaskbar: pipSkipTaskbar ?? this.pipSkipTaskbar,
      pipTitle: pipTitle ?? this.pipTitle,
      exitPipRestoresWindow: exitPipRestoresWindow ?? this.exitPipRestoresWindow,
      overlayHoverMode: overlayHoverMode ?? this.overlayHoverMode,
      overlayAutoHideDelay: overlayAutoHideDelay ?? this.overlayAutoHideDelay,
      overlayDanmakuSafeZoneTop: overlayDanmakuSafeZoneTop ?? this.overlayDanmakuSafeZoneTop,
      overlayDanmakuSafeZoneBottom: overlayDanmakuSafeZoneBottom ?? this.overlayDanmakuSafeZoneBottom,
    );
  }
}
