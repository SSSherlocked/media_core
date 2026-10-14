import 'package:flutter/widgets.dart';

/// Zoom and pan applied to one rendered video surface.
///
/// A video is magnified by transforming the surface, not by asking the engine
/// to scale: the transform is engine independent, costs one composited layer,
/// and survives a backend swap. The controller owns the numbers so a host can
/// read them, reset them, or drive them from something other than a gesture
/// (a slider, a remembered value for a feed item, a picture-in-picture window
/// that keeps the inline zoom).
///
/// ### Coordinate space
///
/// The transform maps *content* points to *view* points:
///
/// ```text
/// view = content * scale + translation
/// ```
///
/// Both are view-local pixels — the surface box the video is rendered into,
/// which is the box the enclosing `ClipRect` crops. The caller therefore has to
/// pass that box's size to every operation: it is what the clamping is derived
/// from.
///
/// ### Rest, and why clamping lives here
///
/// Scale 1 is the *rest* state: the video at its natural size, filling a box
/// that already matches its aspect ratio. [reset] returns there, and
/// [isZoomed] compares against it — a host may allow shrinking by setting
/// [minScale] below 1, but "zoomed in" still means "bigger than natural".
///
/// Zooming a video has one hard requirement: the picture must keep covering the
/// view. Allowing the translation to drift means black bars appear while the
/// user drags, which reads as "the video broke" rather than "I reached the
/// edge". [_clamp] enforces it for every mutation, so no caller has to know the
/// rule.
///
/// Responsibilities:
///
/// - hold scale and translation
/// - zoom around a focal point
/// - pan within the allowed range
/// - produce the transform matrix
///
/// It does not:
///
/// - handle gestures (the widget that renders the video does)
/// - know about playback, engines or sources
/// - animate
///
/// Those belong to:
///
/// - MediaPlayerView
/// - PlayerRuntime / PlayerHandle
/// - the host's animation of choice
final class VideoZoomController extends ChangeNotifier {
  /// Creates a controller.
  ///
  /// [minScale] is 1.0 by default: the video already fills its box at 1x, so
  /// zooming out would only reveal empty space. A host that wants a rubber
  /// band — pinch below natural size, snap back on release — lowers it and
  /// gets [settle] to do the snapping.
  VideoZoomController({
    this.minScale = 1.0,
    this.maxScale = 5.0,
    this.doubleTapScale = 2.0,
    this.snapBackTolerance = 0.05,
  }) : assert(minScale > 0, 'minScale must be positive'),
       assert(maxScale >= minScale, 'maxScale must not be below minScale'),
       assert(doubleTapScale >= minScale, 'doubleTapScale must not be below minScale'),
       assert(snapBackTolerance >= 0, 'snapBackTolerance must not be negative');

  /// Scale of the natural, unzoomed picture.
  static const double restScale = 1;

  /// Smallest allowed scale.
  final double minScale;

  /// Largest allowed scale.
  ///
  /// Bounded because magnifying a decoded texture adds no detail and a very
  /// large scale turns a small drag into a huge jump.
  final double maxScale;

  /// Scale a double tap zooms to.
  final double doubleTapScale;

  /// How far from the rest scale a released pinch may be before it snaps back.
  final double snapBackTolerance;

  double _scale = restScale;
  Offset _translation = Offset.zero;

  /// Current scale.
  double get scale => _scale;

  /// Current translation in view pixels.
  Offset get translation => _translation;

  /// The scale [reset] returns to, clamped into the allowed range.
  double get restingScale => restScale.clamp(minScale, maxScale);

  /// Whether the picture is magnified beyond its natural size.
  bool get isZoomed => _scale > restingScale + _epsilon;

  /// Whether applying [matrix] would change anything.
  ///
  /// A renderer uses this to skip the clip/transform layers entirely while the
  /// surface is at rest, which is the common case for video.
  bool get isActive => (_scale - restingScale).abs() > _epsilon || _translation.distance > _epsilon;

  /// Transform from content pixels to view pixels.
  Matrix4 get matrix {
    return Matrix4.identity()
      ..translateByDouble(_translation.dx, _translation.dy, 0, 1)
      ..scaleByDouble(_scale, _scale, 1, 1);
  }

  /// Returns to the natural, unzoomed state.
  void reset() {
    final rest = restingScale;

    if (_scale == rest && _translation == Offset.zero) {
      return;
    }

    _scale = rest;
    _translation = Offset.zero;

    notifyListeners();
  }

  /// Multiplies the scale by [factor], keeping [focalPoint] under the finger.
  ///
  /// Keeping the focal point fixed is what makes a pinch feel attached to the
  /// fingers: the content point under them stays put while everything else
  /// moves away. A naive `scale += delta` implementation drifts, most visibly
  /// when the user pinches near an edge.
  void scaleBy(double factor, Offset focalPoint, Size viewSize) {
    if (!factor.isFinite || factor <= 0 || viewSize.isEmpty) {
      return;
    }

    final next = (_scale * factor).clamp(minScale, maxScale);

    if (next == _scale) {
      return;
    }

    // Solve `focal = next * content + translation'` for translation', where
    // `content = (focal - translation) / _scale` is the point under the finger.
    final ratio = next / _scale;
    final translation = focalPoint - (focalPoint - _translation) * ratio;

    _scale = next;
    _translation = _clamp(translation, next, viewSize);

    notifyListeners();
  }

  /// Moves the surface by [delta] view pixels.
  ///
  /// A pan while unzoomed is ignored: there is nothing to reveal, and moving
  /// the picture would expose the empty space the clamp exists to prevent.
  void panBy(Offset delta, Size viewSize) {
    if (!isZoomed || viewSize.isEmpty || delta == Offset.zero) {
      return;
    }

    final translation = _clamp(_translation + delta, _scale, viewSize);

    if (translation == _translation) {
      return;
    }

    _translation = translation;

    notifyListeners();
  }

  /// Toggles between the unzoomed state and [doubleTapScale], around
  /// [focalPoint].
  void toggleAt(Offset focalPoint, Size viewSize) {
    if (isZoomed) {
      reset();

      return;
    }

    scaleBy(doubleTapScale / _scale, focalPoint, viewSize);
  }

  /// Sets an absolute [scale], keeping [focalPoint] under the finger.
  ///
  /// For hosts that drive the zoom from something other than a gesture.
  void zoomTo(double scale, Offset focalPoint, Size viewSize) {
    if (!scale.isFinite || scale <= 0) {
      return;
    }

    scaleBy(scale / _scale, focalPoint, viewSize);
  }

  /// Re-applies the clamping after the view changed size.
  ///
  /// Rotation, entering fullscreen and a split-screen resize all move the
  /// bounds the translation was clamped against; without this, a picture
  /// zoomed in portrait can end up hanging off the edge in landscape.
  void reclamp(Size viewSize) {
    if (viewSize.isEmpty) {
      return;
    }

    final translation = _clamp(_translation, _scale, viewSize);

    if (translation == _translation) {
      return;
    }

    _translation = translation;

    notifyListeners();
  }

  /// Resolves a gesture that ended, in place.
  ///
  /// A pinch that barely moved should not leave the picture imperceptibly
  /// enlarged (or shrunk, for a host that allows it), so a scale within
  /// [snapBackTolerance] of the rest scale returns there. Everything else is
  /// re-clamped, because the gesture may have ended against an edge.
  void settle(Size viewSize) {
    final rest = restingScale;

    if (_scale != rest && (_scale - rest).abs() <= snapBackTolerance) {
      reset();

      return;
    }

    reclamp(viewSize);
  }

  /// Clamps [translation] so the scaled picture still covers the view.
  ///
  /// The picture spans `[t, t + scale * size]`; covering `[0, size]` requires
  /// `(1 - scale) * size <= t <= 0` on each axis.
  Offset _clamp(Offset translation, double scale, Size viewSize) {
    final minX = (1 - scale) * viewSize.width;
    final minY = (1 - scale) * viewSize.height;

    return Offset(translation.dx.clamp(minX, 0.0), translation.dy.clamp(minY, 0.0));
  }

  static const double _epsilon = 0.001;

  @override
  String toString() {
    return 'VideoZoomController('
        'scale: ${_scale.toStringAsFixed(3)}, '
        'translation: ${_translation.dx.toStringAsFixed(1)},${_translation.dy.toStringAsFixed(1)}'
        ')';
  }
}
