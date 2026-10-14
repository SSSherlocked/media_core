import 'package:equatable/equatable.dart';

import 'package:media_core/screenshot/screenshot_format.dart';

/// Route a capture is allowed to take.
///
/// Most engines decode into a Flutter texture and expose no frame-capture API,
/// so there are two routes and the caller decides how strict to be about which
/// one is used.
enum ScreenshotRoute {
  /// The engine's own capture when the attached backend supports it, the
  /// rendered surface otherwise.
  auto,

  /// Only the engine's own capture: the decoded frame, without the app's
  /// overlays and without the surface's fit/scaling. Produces nothing when the
  /// backend cannot capture or cannot encode the requested format.
  engine,

  /// Only the rendered surface: exactly the pixels the user sees in the
  /// player's box, at screen resolution. Encodes PNG.
  surface;

  /// Whether this route produces the engine's decoded frame.
  bool get isEngine => this == ScreenshotRoute.engine;

  /// Whether this route captures the on-screen surface.
  bool get isSurface => this == ScreenshotRoute.surface;
}

/// Options for one frame capture.
///
/// The options describe what the caller wants, not what it can get: a capture
/// reports the format it actually produced and the route that produced it.
final class ScreenshotOptions extends Equatable {
  /// Creates capture options.
  const ScreenshotOptions({
    this.format = ScreenshotFormat.png,
    this.quality = 90,
    this.pixelRatio,
    this.route = ScreenshotRoute.auto,
    this.includeSubtitles = false,
    this.timeout = const Duration(seconds: 5),
  });

  /// Lossless PNG at screen resolution, engine capture first.
  static const ScreenshotOptions defaults = ScreenshotOptions();

  /// Prefer a small JPEG, for example to attach to a share sheet.
  static const ScreenshotOptions shareFriendly = ScreenshotOptions(
    format: ScreenshotFormat.jpeg,
    quality: 85,
    route: ScreenshotRoute.surface,
  );

  /// Requested image format.
  ///
  /// Honoured by engines that encode both formats. A surface capture can only
  /// encode PNG, and an engine that cannot encode the request returns nothing
  /// so the next route gets a chance — the produced format is reported on the
  /// result either way.
  final ScreenshotFormat format;

  /// JPEG quality in the 1–100 range; ignored for PNG.
  final int quality;

  /// Scale of a surface capture.
  ///
  /// `null` uses the device pixel ratio, so the image has the resolution of
  /// the screen. `1.0` captures logical pixels. Ignored by engine captures,
  /// which return the decoded frame's own resolution.
  final double? pixelRatio;

  /// Which route may be used.
  final ScreenshotRoute route;

  /// Whether subtitles rendered by the engine should be burned into the image.
  ///
  /// Only engines with an internal subtitle renderer can do this; the surface
  /// route always includes whatever the engine paints, and never includes the
  /// application's own overlay widgets because the capture boundary wraps the
  /// video only.
  final bool includeSubtitles;

  /// Upper bound on a single capture.
  ///
  /// A capture is usually triggered by a user action (a menu item, a button),
  /// and a decoder that never answers must not leave that action pending
  /// forever.
  final Duration timeout;

  /// [quality] clamped to the range engines accept.
  int get effectiveQuality => quality.clamp(1, 100);

  /// Creates modified options.
  ScreenshotOptions copyWith({
    ScreenshotFormat? format,
    int? quality,
    double? pixelRatio,
    ScreenshotRoute? route,
    bool? includeSubtitles,
    Duration? timeout,
  }) {
    return ScreenshotOptions(
      format: format ?? this.format,
      quality: quality ?? this.quality,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      route: route ?? this.route,
      includeSubtitles: includeSubtitles ?? this.includeSubtitles,
      timeout: timeout ?? this.timeout,
    );
  }

  @override
  List<Object?> get props => [format, quality, pixelRatio, route, includeSubtitles, timeout];

  @override
  String toString() {
    return 'ScreenshotOptions('
        'format: ${format.name}, '
        'quality: $quality, '
        'pixelRatio: $pixelRatio, '
        'route: ${route.name}, '
        'includeSubtitles: $includeSubtitles, '
        'timeout: ${timeout.inMilliseconds}ms)';
  }
}
