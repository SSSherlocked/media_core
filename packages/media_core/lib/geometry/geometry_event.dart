import 'package:media_core/geometry/video_geometry.dart';

/// Geometry lifecycle event.
sealed class GeometryEvent {
  const GeometryEvent({required this.generation});

  /// Geometry changed.
  const factory GeometryEvent.changed(VideoGeometry geometry, int generation) = GeometryChanged;

  /// Geometry reset.
  const factory GeometryEvent.reset(int generation) = GeometryReset;

  /// Event generation.
  final int generation;
}

/// Geometry update event.
final class GeometryChanged extends GeometryEvent {
  /// Creates an event reporting [geometry] for the given [generation].
  const GeometryChanged(this.geometry, int generation) : super(generation: generation);

  /// Reported geometry.
  final VideoGeometry geometry;
}

/// Geometry clear event.
final class GeometryReset extends GeometryEvent {
  /// Creates an event that resets geometry at the given [generation].
  const GeometryReset(int generation) : super(generation: generation);
}
