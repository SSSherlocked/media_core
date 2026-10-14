import 'package:equatable/equatable.dart';
import 'package:media_core/geometry/aspect_ratio.dart';
import 'package:media_core/geometry/display_size.dart';
import 'package:media_core/geometry/pixel_ratio.dart';
import 'package:media_core/geometry/video_orientation.dart';
import 'package:media_core/geometry/video_rotation.dart';
import 'package:media_core/geometry/video_size.dart';

/// Complete video geometry information.
///
/// Immutable value object.
///
/// Contains:
///
/// - source video dimension
/// - display output dimension
/// - aspect ratio
/// - orientation
/// - rotation metadata
/// - pixel ratio
///
/// Used by:
///
/// - GeometryController
/// - Renderer
/// - PlayerSnapshot
///
/// Does not:
///
/// - perform layout
/// - resize surface
/// - control renderer
final class VideoGeometry extends Equatable {
  /// Creates geometry with every field supplied explicitly.
  ///
  /// [VideoGeometry.derived] is the variant that recalculates [aspectRatio]
  /// and [orientation] from [videoSize] and [rotation]; this constructor
  /// trusts what it is given, so a caller passing a raw pixel grid plus a
  /// 90° rotation gets ratio and orientation that disagree with the layout.
  const VideoGeometry({
    required this.videoSize,
    required this.displaySize,
    required this.aspectRatio,
    required this.orientation,
    required this.rotation,
    required this.pixelRatio,
  });

  /// Restores geometry from a map produced by [toMap].
  factory VideoGeometry.fromMap(Map<String, dynamic> map) {
    return VideoGeometry(
      videoSize: VideoSize.fromMap(map['videoSize'] as Map<String, dynamic>),
      displaySize: DisplaySize.fromMap(map['displaySize'] as Map<String, dynamic>),
      aspectRatio: AspectRatioValue(map['aspectRatio'] as double? ?? 0),
      orientation: VideoOrientationInfo.fromMap(map['orientation'] as Map<String, dynamic>),
      rotation: VideoRotationInfo.fromMap(map['rotation'] as Map<String, dynamic>),
      pixelRatio: PixelRatioValue(map['pixelRatio'] as double? ?? 1),
    );
  }

  /// Empty geometry.
  const VideoGeometry.empty()
    : videoSize = const VideoSize.zero(),
      displaySize = const DisplaySize.zero(),
      aspectRatio = const AspectRatioValue.zero(),
      orientation = const VideoOrientationInfo(orientation: VideoOrientation.unknown),
      rotation = const VideoRotationInfo.none(),
      pixelRatio = const PixelRatioValue.one();

  /// Builds geometry whose derived values describe what is displayed.
  ///
  /// Every entry point that changes the video size or the rotation funnels
  /// through here. A phone recording pairs a landscape pixel grid with a 90°
  /// rotation, so a ratio or orientation derived from the raw grid would
  /// contradict [effectiveAspectRatio], the orientation accessors and the
  /// layout the renderer has to produce.
  factory VideoGeometry.derived({
    required VideoSize videoSize,
    required DisplaySize displaySize,
    required VideoRotationInfo rotation,
    required PixelRatioValue pixelRatio,
  }) {
    final displayed = _displaySize(videoSize, rotation);

    return VideoGeometry(
      videoSize: videoSize,
      displaySize: displaySize,
      aspectRatio: AspectRatioValue.fromSize(displayed),
      orientation: VideoOrientationInfo.fromSize(displayed.width, displayed.height),
      rotation: rotation,
      pixelRatio: pixelRatio,
    );
  }

  /// Source media size.
  final VideoSize videoSize;

  /// Render target size.
  final DisplaySize displaySize;

  /// Video aspect ratio.
  final AspectRatioValue aspectRatio;

  /// Video orientation metadata.
  final VideoOrientationInfo orientation;

  /// Rotation metadata.
  final VideoRotationInfo rotation;

  /// Device pixel density.
  final PixelRatioValue pixelRatio;

  /// Video size as displayed, i.e. after [rotation] is applied.
  ///
  /// A 90°/270° rotation swaps width and height.
  static VideoSize _displaySize(VideoSize size, VideoRotationInfo rotation) {
    if (!rotation.swapsAspectRatio) {
      return size;
    }

    return VideoSize(width: size.height, height: size.width);
  }

  /// Whether video size is valid.
  bool get hasVideo {
    return videoSize.isValid;
  }

  /// Whether display size is valid.
  bool get hasDisplay {
    return displaySize.isValid;
  }

  /// Whether geometry can be rendered.
  bool get canRender {
    return hasVideo && hasDisplay && aspectRatio.isValid;
  }

  /// Width after rotation.
  double get effectiveWidth {
    if (rotation.swapsAspectRatio) {
      return videoSize.height.toDouble();
    }

    return videoSize.width.toDouble();
  }

  /// Height after rotation.
  double get effectiveHeight {
    if (rotation.swapsAspectRatio) {
      return videoSize.width.toDouble();
    }

    return videoSize.height.toDouble();
  }

  /// Effective aspect ratio after rotation.
  double get effectiveAspectRatio {
    final height = effectiveHeight;

    if (height <= 0) {
      return 0;
    }

    return effectiveWidth / height;
  }

  /// Orientation as displayed, i.e. after [rotation] is applied.
  ///
  /// Derived from the effective dimensions rather than from the stored
  /// [orientation], so the answer cannot disagree with the ratio the renderer
  /// lays out.
  VideoOrientation get displayOrientation {
    return VideoOrientation.fromSize(effectiveWidth.round(), effectiveHeight.round());
  }

  /// Whether portrait.
  bool get isPortrait {
    return displayOrientation == VideoOrientation.portrait;
  }

  /// Whether landscape.
  bool get isLandscape {
    return displayOrientation == VideoOrientation.landscape;
  }

  /// Whether square.
  bool get isSquare {
    return displayOrientation == VideoOrientation.square;
  }

  /// Whether rotated.
  bool get isRotated {
    return rotation.swapsAspectRatio;
  }

  /// Whether mirrored.
  bool get isMirrored {
    return orientation.mirrored;
  }

  /// Creates geometry with new video size.
  VideoGeometry copyWithVideoSize(VideoSize size) {
    return VideoGeometry.derived(videoSize: size, displaySize: displaySize, rotation: rotation, pixelRatio: pixelRatio);
  }

  /// Creates geometry with new display size.
  VideoGeometry copyWithDisplaySize(DisplaySize size) {
    return VideoGeometry.derived(videoSize: videoSize, displaySize: size, rotation: rotation, pixelRatio: pixelRatio);
  }

  /// Creates geometry with new rotation.
  VideoGeometry copyWithRotation(VideoRotationInfo value) {
    return VideoGeometry.derived(
      videoSize: videoSize,
      displaySize: displaySize,
      rotation: value,
      pixelRatio: pixelRatio,
    );
  }

  /// Creates geometry with new pixel ratio.
  VideoGeometry copyWithPixelRatio(PixelRatioValue value) {
    return VideoGeometry(
      videoSize: videoSize,
      displaySize: displaySize,
      aspectRatio: aspectRatio,
      orientation: orientation,
      rotation: rotation,
      pixelRatio: value,
    );
  }

  /// Creates geometry with all values recalculated.
  VideoGeometry copyWith({
    VideoSize? videoSize,
    DisplaySize? displaySize,
    VideoRotationInfo? rotation,
    PixelRatioValue? pixelRatio,
  }) {
    return VideoGeometry.derived(
      videoSize: videoSize ?? this.videoSize,
      displaySize: displaySize ?? this.displaySize,
      rotation: rotation ?? this.rotation,
      pixelRatio: pixelRatio ?? this.pixelRatio,
    );
  }

  /// Debug serialization.
  Map<String, dynamic> toMap() {
    return {
      'videoSize': videoSize.toMap(),
      'displaySize': displaySize.toMap(),
      'aspectRatio': aspectRatio.value,
      'orientation': orientation.toMap(),
      'rotation': rotation.toMap(),
      'pixelRatio': pixelRatio.value,
    };
  }

  @override
  List<Object?> get props => [videoSize, displaySize, aspectRatio, orientation, rotation, pixelRatio];

  @override
  String toString() {
    return 'VideoGeometry('
        'video=$videoSize, '
        'display=$displaySize, '
        'orientation=$orientation, '
        'rotation=$rotation'
        ')';
  }
}
