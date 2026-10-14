import 'package:equatable/equatable.dart';

/// Render display size.
///
/// Represents output surface dimensions.
///
/// Immutable value object.
///
/// Does not:
///
/// - resize Flutter widget
/// - control renderer
/// - modify video source
///
/// Used by:
///
/// - GeometryController
/// - Renderer
/// - PlayerIdentity snapshot
final class DisplaySize extends Equatable {
  /// Creates a display size from explicit surface dimensions.
  const DisplaySize({required this.width, required this.height});

  /// Restores a display size from a map produced by [toMap].
  factory DisplaySize.fromMap(Map<String, dynamic> map) {
    return DisplaySize(
      width: (map['width'] as num?)?.toDouble() ?? 0,

      height: (map['height'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Empty display size.
  const DisplaySize.zero() : width = 0, height = 0;

  /// Creates from double dimensions.
  factory DisplaySize.fromDouble(double width, double height) {
    return DisplaySize(width: width, height: height);
  }

  /// Display width.
  final double width;

  /// Display height.
  final double height;

  /// Whether size is valid.
  bool get isValid {
    return width > 0 && height > 0;
  }

  /// Whether size is empty.
  bool get isEmpty {
    return !isValid;
  }

  /// Display aspect ratio.
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

  /// Area.
  double get area {
    return width * height;
  }

  /// Longest edge.
  double get maxDimension {
    return width > height ? width : height;
  }

  /// Shortest edge.
  double get minDimension {
    return width < height ? width : height;
  }

  /// Creates scaled display size.
  DisplaySize scale(double factor) {
    if (!isValid || factor <= 0) {
      return const DisplaySize.zero();
    }

    return DisplaySize(width: width * factor, height: height * factor);
  }

  /// Fit inside container.
  ///
  /// Keeps aspect ratio.
  DisplaySize fitInside(DisplaySize container) {
    if (!isValid || !container.isValid) {
      return const DisplaySize.zero();
    }

    final widthScale = container.width / width;

    final heightScale = container.height / height;

    final scale = widthScale < heightScale ? widthScale : heightScale;

    return DisplaySize(width: width * scale, height: height * scale);
  }

  /// Fill container.
  ///
  /// Keeps aspect ratio.
  DisplaySize cover(DisplaySize container) {
    if (!isValid || !container.isValid) {
      return const DisplaySize.zero();
    }

    final widthScale = container.width / width;

    final heightScale = container.height / height;

    final scale = widthScale > heightScale ? widthScale : heightScale;

    return DisplaySize(width: width * scale, height: height * scale);
  }

  /// Creates integer size.
  DisplaySize round() {
    return DisplaySize(width: width.roundToDouble(), height: height.roundToDouble());
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
