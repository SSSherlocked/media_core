import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/geometry/geometry_event.dart';
import 'package:media_core/geometry/video_geometry.dart';
import 'package:media_core/geometry/video_orientation.dart';

/// Current geometry state.
///
/// Owns runtime geometry information.
///
/// This is mutable lifecycle state owned by:
///
/// - GeometryController
///
/// Does not:
///
/// - calculate layout
/// - resize renderer
/// - call platform APIs
final class GeometryState extends Equatable {
  /// Creates geometry state from explicit values.
  const GeometryState({
    required this.geometry,
    required this.generation,
    required this.initialized,
    required this.updatedAt,
  });

  /// Initial empty state.
  const GeometryState.initial()
    : geometry = const VideoGeometry.empty(),
      generation = 0,
      initialized = false,
      updatedAt = null;

  /// Current video geometry.
  final VideoGeometry geometry;

  /// Geometry lifecycle generation.
  ///
  /// Used to discard stale async updates.
  final int generation;

  /// Whether geometry has received
  /// valid source information.
  final bool initialized;

  /// Last update timestamp.
  final DateTime? updatedAt;

  /// Whether video exists.
  bool get hasVideo {
    return geometry.hasVideo;
  }

  /// Whether display exists.
  bool get hasDisplay {
    return geometry.hasDisplay;
  }

  /// Whether renderer can consume geometry.
  bool get canRender {
    return geometry.canRender;
  }

  /// Current orientation.
  VideoOrientationInfo get orientation {
    return geometry.orientation;
  }

  /// Current aspect ratio.
  double get aspectRatio {
    return geometry.aspectRatio.value;
  }

  /// Apply geometry update.
  GeometryState updateGeometry(VideoGeometry value, {int? generation}) {
    return GeometryState(
      geometry: value,
      generation: generation ?? this.generation,
      initialized: true,
      updatedAt: clock.now(),
    );
  }

  /// Clear geometry.
  GeometryState clear({int? generation}) {
    return GeometryState(
      geometry: const VideoGeometry.empty(),
      generation: generation ?? this.generation,
      initialized: false,
      updatedAt: clock.now(),
    );
  }

  /// Same geometry under another generation.
  GeometryState withGeneration(int value) {
    return GeometryState(geometry: geometry, generation: value, initialized: initialized, updatedAt: updatedAt);
  }

  /// Increment generation.
  GeometryState nextGeneration() {
    return withGeneration(generation + 1);
  }

  /// Reduce event.
  GeometryState reduce(GeometryEvent event) {
    switch (event) {
      case GeometryChanged():
        if (event.generation < generation) {
          return this;
        }

        return updateGeometry(event.geometry, generation: event.generation);

      case GeometryReset():
        if (event.generation < generation) {
          return this;
        }

        return clear(generation: event.generation);
    }
  }

  @override
  List<Object?> get props => [geometry, generation, initialized, updatedAt];

  @override
  String toString() {
    return 'GeometryState('
        'geometry=$geometry, '
        'generation=$generation, '
        'initialized=$initialized)';
  }
}
