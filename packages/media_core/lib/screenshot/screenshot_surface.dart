import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Handle on the rendered surface of one player widget.
///
/// Most engines decode into a Flutter texture and offer no frame-capture API
/// of their own, so the only way to get an image out of them is to capture the
/// layer the texture is painted into. The widget that renders a player
/// (`MediaPlayerView`) creates one of these, wraps its video in a
/// [RepaintBoundary] with [boundaryKey], and attaches it to the handle.
///
/// Responsibilities:
///
/// - resolve the repaint boundary of a live widget
/// - encode what that boundary paints
///
/// It does not:
///
/// - own the widget (the widget attaches and detaches itself)
/// - decide which route a capture takes
/// - keep the resulting bytes
///
/// Those belong to:
///
/// - MediaPlayerView
/// - ScreenshotManager
/// - PlayerScreenshot
final class ScreenshotSurface {
  /// Creates a surface handle for [boundaryKey].
  ScreenshotSurface({required this.boundaryKey, this.devicePixelRatio});

  /// Key of the [RepaintBoundary] that wraps the video.
  final GlobalKey boundaryKey;

  /// Scale used when a capture does not name one.
  ///
  /// Owned by the widget, which refreshes it from `MediaQuery` whenever the
  /// dependencies change, so a window moved between displays captures at the
  /// new density.
  double? devicePixelRatio;

  /// Whether the boundary is currently mounted.
  bool get isAttached {
    final context = boundaryKey.currentContext;

    return context != null && context.mounted;
  }

  /// Captures the boundary as PNG.
  ///
  /// Returns null when the widget is gone or its layer cannot be read.
  ///
  /// Flutter's engine encodes PNG only, so a caller that asked for JPEG is
  /// served PNG and is told so through `PlayerScreenshot.format`.
  Future<Uint8List?> capturePng({double? pixelRatio}) async {
    final boundary = _resolveBoundary();

    if (boundary == null) {
      return null;
    }

    // A boundary whose paint is still pending throws from `toImage`. Waiting
    // for the frame that is already scheduled turns "captured during a resize"
    // into a slightly later capture instead of a failure. `debugNeedsPaint` is
    // only readable in debug builds, hence the assert-wrapped read.
    if (_needsPaint(boundary)) {
      await WidgetsBinding.instance.endOfFrame;

      if (_needsPaint(boundary) || !_isUsable(boundary)) {
        return null;
      }
    }

    final image = await boundary.toImage(pixelRatio: pixelRatio ?? devicePixelRatio ?? 1.0);

    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);

      final bytes = data?.buffer.asUint8List();

      if (bytes == null || bytes.isEmpty) {
        return null;
      }

      return bytes;
    } finally {
      image.dispose();
    }
  }

  /// Size this surface would capture at [pixelRatio], in device pixels.
  ///
  /// Null while the widget is gone or has not been laid out.
  Size? captureSize({double? pixelRatio}) {
    final boundary = _resolveBoundary();

    if (boundary == null || !boundary.hasSize) {
      return null;
    }

    return boundary.size * (pixelRatio ?? devicePixelRatio ?? 1.0);
  }

  RenderRepaintBoundary? _resolveBoundary() {
    final context = boundaryKey.currentContext;

    if (context == null) {
      return null;
    }

    final object = context.findRenderObject();

    if (object is RenderRepaintBoundary && _isUsable(object)) {
      return object;
    }

    return null;
  }

  /// Whether [boundary] can still be read.
  ///
  /// A detached or never-laid-out boundary has nothing to composite, and
  /// asking for an image of it is an error rather than an empty result.
  bool _isUsable(RenderRepaintBoundary boundary) {
    return boundary.attached && boundary.hasSize;
  }

  bool _needsPaint(RenderRepaintBoundary boundary) {
    var needsPaint = false;

    // debugNeedsPaint is a debug-only accessor, so the read lives inside an
    // assert and stays compiled out of release builds.
    assert(() {
      needsPaint = boundary.debugNeedsPaint;

      return true;
    }(), 'RenderRepaintBoundary.debugNeedsPaint is readable only in debug mode.');

    return needsPaint;
  }
}
