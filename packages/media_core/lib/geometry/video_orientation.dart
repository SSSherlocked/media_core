import 'package:equatable/equatable.dart';

/// Logical video orientation.
///
/// Describes the natural orientation of video content.
///
/// Does not:
///
/// - rotate pixels
/// - transform renderer
/// - modify decoder output
enum VideoOrientation {
  /// Orientation has not been determined yet.
  unknown,

  /// Wider than tall.
  landscape,

  /// Taller than wide.
  portrait,

  /// Equally wide and tall.
  square;

  /// Whether the orientation has not been determined.
  bool get isUnknown {
    return this == VideoOrientation.unknown;
  }

  /// Whether the content is wider than tall.
  bool get isLandscape {
    return this == VideoOrientation.landscape;
  }

  /// Whether the content is taller than wide.
  bool get isPortrait {
    return this == VideoOrientation.portrait;
  }

  /// Whether the content is equally wide and tall.
  bool get isSquare {
    return this == VideoOrientation.square;
  }

  /// Creates orientation from dimensions.
  static VideoOrientation fromSize(int width, int height) {
    if (width <= 0 || height <= 0) {
      return VideoOrientation.unknown;
    }

    if (width == height) {
      return VideoOrientation.square;
    }

    if (height > width) {
      return VideoOrientation.portrait;
    }

    return VideoOrientation.landscape;
  }
}

/// Full orientation metadata.
///
/// Contains:
///
/// - logical orientation
/// - rotation
/// - mirrored state
///
/// Used by:
///
/// - GeometryController
/// - Renderer
/// - PlayerIdentity snapshot
final class VideoOrientationInfo extends Equatable {
  /// Creates orientation metadata from explicit values.
  ///
  /// [rotation] is taken as given; the parsing entry points normalize it to
  /// a quarter turn.
  const VideoOrientationInfo({required this.orientation, this.rotation = 0, this.mirrored = false});

  /// Restores orientation metadata from a map produced by [toMap].
  ///
  /// An unrecognized or missing orientation name yields
  /// [VideoOrientation.unknown].
  factory VideoOrientationInfo.fromMap(Map<String, dynamic> map) {
    final name = map['orientation'] as String?;

    final orientation = VideoOrientation.values.firstWhere(
      (item) => item.name == name,
      orElse: () => VideoOrientation.unknown,
    );

    return VideoOrientationInfo(
      orientation: orientation,
      rotation: _normalize(map['rotation'] as int? ?? 0),
      mirrored: map['mirrored'] as bool? ?? false,
    );
  }

  /// Empty orientation.
  const VideoOrientationInfo.unknown() : orientation = VideoOrientation.unknown, rotation = 0, mirrored = false;

  /// Creates from video dimensions.
  factory VideoOrientationInfo.fromSize(int width, int height) {
    return VideoOrientationInfo(orientation: VideoOrientation.fromSize(width, height));
  }

  /// Logical orientation.
  final VideoOrientation orientation;

  /// Clockwise rotation.
  ///
  /// Usually:
  ///
  /// 0
  /// 90
  /// 180
  /// 270
  final int rotation;

  /// Whether horizontally mirrored.
  final bool mirrored;

  /// Whether the logical orientation has not been determined.
  bool get isUnknown {
    return orientation.isUnknown;
  }

  /// Whether the logical orientation is wider than tall.
  bool get isLandscape {
    return orientation.isLandscape;
  }

  /// Whether the logical orientation is taller than wide.
  bool get isPortrait {
    return orientation.isPortrait;
  }

  /// Whether the logical orientation is equally wide and tall.
  bool get isSquare {
    return orientation.isSquare;
  }

  /// Whether rotation changes geometry.
  bool get hasRotation {
    final value = rotation % 360;

    return value != 0;
  }

  /// Whether width and height swap.
  bool get swapsAspectRatio {
    final value = rotation % 360;

    return value == 90 || value == 270;
  }

  /// Effective orientation after rotation.
  VideoOrientation get effectiveOrientation {
    final value = rotation % 360;

    if (value == 90 || value == 270) {
      if (orientation == VideoOrientation.landscape) {
        return VideoOrientation.portrait;
      }

      if (orientation == VideoOrientation.portrait) {
        return VideoOrientation.landscape;
      }
    }

    return orientation;
  }

  /// Apply rotation.
  VideoOrientationInfo rotate(int degrees) {
    return VideoOrientationInfo(orientation: orientation, rotation: _normalize(rotation + degrees), mirrored: mirrored);
  }

  /// Apply mirror.
  VideoOrientationInfo mirror() {
    return VideoOrientationInfo(orientation: orientation, rotation: rotation, mirrored: !mirrored);
  }

  /// Converts to a simple map.
  Map<String, dynamic> toMap() {
    return {'orientation': orientation.name, 'rotation': rotation, 'mirrored': mirrored};
  }

  static int _normalize(int value) {
    final result = value % 360;

    if (result < 0) {
      return result + 360;
    }

    return result;
  }

  @override
  List<Object?> get props => [orientation, rotation, mirrored];

  @override
  String toString() {
    return 'VideoOrientationInfo('
        'orientation=$orientation, '
        'rotation=$rotation, '
        'mirrored=$mirrored)';
  }
}
