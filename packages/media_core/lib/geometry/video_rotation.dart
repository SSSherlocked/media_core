import 'package:equatable/equatable.dart';

/// Video rotation metadata.
///
/// Describes how video pixels should be interpreted.
///
/// Does not:
///
/// - rotate actual frames
/// - modify decoder output
/// - control renderer transform
///
/// Renderer decides how to apply this information.
final class VideoRotationInfo extends Equatable {
  /// Creates rotation metadata for an explicit [angle].
  ///
  /// The [angle] is stored as given; [VideoRotationInfo.fromDegrees] and the
  /// parsing entry points are the ones that normalize it to a quarter turn.
  const VideoRotationInfo({required this.angle});

  /// Restores rotation metadata from a map produced by [toMap].
  factory VideoRotationInfo.fromMap(Map<String, dynamic> map) {
    return VideoRotationInfo(angle: _normalize(map['angle'] as int? ?? 0));
  }

  /// No rotation.
  const VideoRotationInfo.none() : angle = 0;

  /// Creates rotation information.
  ///
  /// Supported values:
  ///
  /// 0
  /// 90
  /// 180
  /// 270
  factory VideoRotationInfo.fromDegrees(int degrees) {
    return VideoRotationInfo(angle: _normalize(degrees));
  }

  /// Clockwise rotation degrees.
  ///
  /// Always normalized:
  ///
  /// 0
  /// 90
  /// 180
  /// 270
  final int angle;

  /// Whether no rotation exists.
  bool get isNone {
    return angle == 0;
  }

  /// Whether rotated 90 degrees.
  bool get is90 {
    return angle == 90;
  }

  /// Whether rotated 180 degrees.
  bool get is180 {
    return angle == 180;
  }

  /// Whether rotated 270 degrees.
  bool get is270 {
    return angle == 270;
  }

  /// Whether rotation changes width and height.
  ///
  /// 90/270 degree rotation swaps aspect ratio.
  bool get swapsAspectRatio {
    return angle == 90 || angle == 270;
  }

  /// Whether rotation exists.
  bool get hasRotation {
    return angle != 0;
  }

  /// Clockwise quarter turns.
  int get quarterTurns {
    return angle ~/ 90;
  }

  /// Opposite rotation.
  VideoRotationInfo get inverse {
    return VideoRotationInfo(angle: _normalize(360 - angle));
  }

  /// Adds rotation.
  VideoRotationInfo add(int degrees) {
    return VideoRotationInfo(angle: _normalize(angle + degrees));
  }

  /// Creates copy.
  VideoRotationInfo copyWith(int angle) {
    return VideoRotationInfo(angle: _normalize(angle));
  }

  /// Converts to a simple map.
  Map<String, dynamic> toMap() {
    return {'angle': angle};
  }

  static int _normalize(int degrees) {
    var value = degrees % 360;

    if (value < 0) {
      value += 360;
    }

    switch (value) {
      case 0:
        return 0;

      case 90:
        return 90;

      case 180:
        return 180;

      case 270:
        return 270;

      default:
        //
        // Some containers may report
        // non-standard values.
        //
        // Round to nearest valid
        // video rotation.
        //
        final normalized = (value / 90).round() * 90;

        return normalized % 360;
    }
  }

  @override
  List<Object?> get props => [angle];

  @override
  String toString() {
    return 'VideoRotationInfo(angle=$angle)';
  }
}
