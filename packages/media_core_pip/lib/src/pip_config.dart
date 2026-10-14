import 'package:media_core/media_core.dart' show VideoOrientation;

/// Tunables for the picture-in-picture feature.
///
/// One object covers both platform families, because the knobs are the same
/// intent expressed twice: how big the small window is, how close to the
/// screen edge it sits, and whether leaving it restores what was there before.
final class PipConfig {
  /// Sets the small window's shape, corner gap and restore behaviour.
  ///
  /// Every argument has a default, so a host that only cares about one knob
  /// still gets a workable window: the defaults are the sizes this feature
  /// ships with, not placeholders.
  const PipConfig({
    this.width = 320,
    this.height = 180,
    this.minWidth = 140,
    this.minHeight = 90,
    this.cornerSpacing = 16,
    this.skipTaskbar = false,
    this.title = 'media_core PiP',
    this.restoreWindowOnExit = true,
    this.lockAspectRatio = true,
    this.fallbackOrientation = VideoOrientation.landscape,
    this.requestSourceRectHint = true,
  });

  /// Caller-accepted defaults.
  static const PipConfig defaults = PipConfig();

  /// Width of the desktop small window, in logical pixels.
  final double width;

  /// Smallest width the compact window may reach, in logical pixels.
  final double minWidth;

  /// Smallest height the compact window may reach, in logical pixels.
  final double minHeight;

  /// Height of the desktop small window.
  ///
  /// Used as-is only when the video size is unknown; otherwise the height
  /// follows the video's aspect ratio.
  final double height;

  /// Distance between the small window and the screen corner it snaps to.
  final double cornerSpacing;

  /// Whether the desktop small window hides from the taskbar.
  final bool skipTaskbar;

  /// Window title while in picture-in-picture.
  final String title;

  /// Whether leaving picture-in-picture restores the previous window state
  /// (size, position, always-on-top, resizable, title).
  final bool restoreWindowOnExit;

  /// Whether the desktop small window is locked to the video's shape.
  ///
  /// On by default: a small window that shows the video's actual shape wastes
  /// no area on letterbox bars. Turn it off to let the viewer pick any shape —
  /// the picture is then fitted into the window and gains bars on whichever
  /// side the shape does not match.
  final bool lockAspectRatio;

  /// Orientation assumed when the video size is unknown.
  final VideoOrientation fallbackOrientation;

  /// Whether the video widget's rectangle is passed to the platform as the
  /// picture-in-picture source hint.
  ///
  /// Mobile only, and purely cosmetic: it drives the entrance animation.
  final bool requestSourceRectHint;

  /// Returns a copy with the named knobs replaced, leaving the rest as-is.
  ///
  /// The config is immutable and the driver holds it by value, so a host
  /// changing one setting builds from this rather than mutating the object a
  /// running transition may be reading.
  PipConfig copyWith({
    double? width,
    double? height,
    double? minWidth,
    double? minHeight,
    double? cornerSpacing,
    bool? skipTaskbar,
    String? title,
    bool? restoreWindowOnExit,
    bool? lockAspectRatio,
    VideoOrientation? fallbackOrientation,
    bool? requestSourceRectHint,
  }) {
    return PipConfig(
      width: width ?? this.width,
      height: height ?? this.height,
      minWidth: minWidth ?? this.minWidth,
      minHeight: minHeight ?? this.minHeight,
      cornerSpacing: cornerSpacing ?? this.cornerSpacing,
      skipTaskbar: skipTaskbar ?? this.skipTaskbar,
      title: title ?? this.title,
      restoreWindowOnExit: restoreWindowOnExit ?? this.restoreWindowOnExit,
      lockAspectRatio: lockAspectRatio ?? this.lockAspectRatio,
      fallbackOrientation: fallbackOrientation ?? this.fallbackOrientation,
      requestSourceRectHint: requestSourceRectHint ?? this.requestSourceRectHint,
    );
  }
}
