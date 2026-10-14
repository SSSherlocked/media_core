import 'package:equatable/equatable.dart';

/// Source video size.
///
/// Immutable value object.
///
/// Represents decoded media dimensions.
///
/// Does not:
///
/// - control renderer size
/// - perform scaling
/// - modify video stream
///
/// Used by:
///
/// - GeometryController
/// - Renderer
/// - PlayerIdentity snapshot
final class VideoSize extends Equatable {
  /// Creates a size from explicit pixel dimensions.
  const VideoSize({required this.width, required this.height});

  /// Restores a size from a map produced by [toMap].
  factory VideoSize.fromMap(Map<String, dynamic> map) {
    return VideoSize(width: map['width'] as int? ?? 0, height: map['height'] as int? ?? 0);
  }

  /// Empty size.
  const VideoSize.zero() : width = 0, height = 0;

  /// Creates from integer dimensions.
  factory VideoSize.fromInt(int width, int height) {
    return VideoSize(width: width, height: height);
  }

  /// Video width in pixels.
  final int width;

  /// Video height in pixels.
  final int height;

  /// Whether size is valid.
  bool get isValid {
    return width > 0 && height > 0;
  }

  /// Whether size is empty.
  bool get isEmpty {
    return width <= 0 || height <= 0;
  }

  /// Aspect ratio.
  double get aspectRatio {
    if (!isValid) {
      return 0;
    }

    return width / height;
  }

  /// Whether portrait.
  bool get isPortrait {
    return height > width;
  }

  /// Whether landscape.
  bool get isLandscape {
    return width > height;
  }

  /// Whether square.
  bool get isSquare {
    return width == height && isValid;
  }

  /// Total pixels.
  int get pixels {
    return width * height;
  }

  /// Longest edge.
  int get maxDimension {
    return width > height ? width : height;
  }

  /// Shortest edge.
  int get minDimension {
    return width < height ? width : height;
  }

  /// Scale factor.
  ///
  /// Example:
  ///
  /// 1920x1080 -> 960x540
  ///
  double scaleTo(VideoSize target) {
    if (!isValid || !target.isValid) {
      return 0;
    }

    final widthScale = target.width / width;

    final heightScale = target.height / height;

    return widthScale < heightScale ? widthScale : heightScale;
  }

  /// Creates scaled size.
  VideoSize scale(double factor) {
    if (!isValid || factor <= 0) {
      return const VideoSize.zero();
    }

    return VideoSize(width: (width * factor).round(), height: (height * factor).round());
  }

  /// Creates size with width.
  ///
  /// Keeps aspect ratio.
  VideoSize fitWidth(int value) {
    if (!isValid || value <= 0) {
      return const VideoSize.zero();
    }

    final height = value / aspectRatio;

    return VideoSize(width: value, height: height.round());
  }

  /// Creates size with height.
  ///
  /// Keeps aspect ratio.
  VideoSize fitHeight(int value) {
    if (!isValid || value <= 0) {
      return const VideoSize.zero();
    }

    final width = value * aspectRatio;

    return VideoSize(width: width.round(), height: value);
  }

  /// Swaps width and height.
  ///
  /// Used for:
  ///
  /// - rotation 90
  /// - rotation 270
  VideoSize transpose() {
    return VideoSize(width: height, height: width);
  }

  /// Converts to a simple map.
  Map<String, dynamic> toMap() {
    return {'width': width, 'height': height};
  }

  @override
  List<Object?> get props => [width, height];

  @override
  String toString() {
    return '${width}x$height';
  }
}
