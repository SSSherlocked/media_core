import 'package:equatable/equatable.dart';
import 'package:media_core/geometry/display_size.dart';
import 'package:media_core/geometry/geometry_state.dart';
import 'package:media_core/geometry/pixel_ratio.dart';
import 'package:media_core/geometry/video_geometry.dart';
import 'package:media_core/geometry/video_orientation.dart';
import 'package:media_core/geometry/video_rotation.dart';
import 'package:media_core/geometry/video_size.dart';

/// Immutable geometry snapshot.
///
/// Read-only view of geometry subsystem.
///
/// Used by:
///
/// - UI
/// - Renderer
/// - PlayerIdentity snapshot
/// - Diagnostics
///
/// Does not:
///
/// - mutate geometry
/// - trigger recalculation
/// - call platform APIs
final class GeometrySnapshot extends Equatable {
  /// Creates a snapshot from explicit read-only values.
  const GeometrySnapshot({
    required this.geometry,
    required this.generation,
    required this.initialized,
    required this.timestamp,
  });

  /// Restores a snapshot from a map produced by [toMap].
  factory GeometrySnapshot.fromMap(Map<String, dynamic> map) {
    return GeometrySnapshot(
      geometry: VideoGeometry.fromMap(map['geometry'] as Map<String, dynamic>),
      generation: map['generation'] as int? ?? 0,
      initialized: map['initialized'] as bool? ?? false,
      timestamp: map['timestamp'] == null ? null : DateTime.tryParse(map['timestamp'] as String),
    );
  }

  /// Creates empty snapshot.
  const GeometrySnapshot.empty()
    : geometry = const VideoGeometry.empty(),
      generation = 0,
      initialized = false,
      timestamp = null;

  /// Creates from state.
  factory GeometrySnapshot.fromState(GeometryState state) {
    return GeometrySnapshot(
      geometry: state.geometry,
      generation: state.generation,
      initialized: state.initialized,
      timestamp: state.updatedAt,
    );
  }

  /// Current geometry.
  final VideoGeometry geometry;

  /// Lifecycle generation.
  final int generation;

  /// Whether geometry initialized.
  final bool initialized;

  /// Last update time.
  final DateTime? timestamp;

  /// Whether video information exists.
  bool get hasVideo {
    return geometry.hasVideo;
  }

  /// Whether display information exists.
  bool get hasDisplay {
    return geometry.hasDisplay;
  }

  /// Whether renderer can render.
  bool get canRender {
    return geometry.canRender;
  }

  /// Current source size.
  VideoSize? get videoSize {
    if (!hasVideo) {
      return null;
    }

    return geometry.videoSize;
  }

  /// Current display size.
  DisplaySize? get displaySize {
    if (!hasDisplay) {
      return null;
    }

    return geometry.displaySize;
  }

  /// Current aspect ratio.
  double get aspectRatio {
    return geometry.aspectRatio.value;
  }

  /// Current orientation.
  VideoOrientationInfo get orientation {
    return geometry.orientation;
  }

  /// Current rotation.
  VideoRotationInfo get rotation {
    return geometry.rotation;
  }

  /// Current pixel density.
  PixelRatioValue get pixelRatio {
    return geometry.pixelRatio;
  }

  /// Whether portrait video.
  bool get isPortrait {
    return geometry.isPortrait;
  }

  /// Whether landscape video.
  bool get isLandscape {
    return geometry.isLandscape;
  }

  /// Whether geometry changed.
  bool differsFrom(GeometrySnapshot other) {
    return geometry != other.geometry || generation != other.generation;
  }

  /// Converts to debug map.
  Map<String, dynamic> toMap() {
    return {
      'geometry': geometry.toMap(),
      'generation': generation,
      'initialized': initialized,
      'timestamp': timestamp?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [geometry, generation, initialized, timestamp];

  @override
  String toString() {
    return 'GeometrySnapshot('
        'generation=$generation, '
        'initialized=$initialized, '
        'geometry=$geometry)';
  }
}
