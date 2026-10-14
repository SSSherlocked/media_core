import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/geometry/geometry_snapshot.dart';
import 'package:media_core/geometry/video_geometry.dart';

/// Geometry lifecycle session.
///
/// Represents one continuous geometry lifecycle.
///
/// A new session is created when:
///
/// - new player instance starts
/// - new media source starts
/// - renderer surface is recreated
///
/// Does not:
///
/// - control playback
/// - modify geometry
/// - perform layout
final class GeometrySession extends Equatable {
  /// Creates a session from explicit lifecycle values.
  const GeometrySession({required this.id, required this.generation, required this.snapshot, required this.createdAt});

  /// Creates new session.
  factory GeometrySession.create({required int id, GeometrySnapshot snapshot = const GeometrySnapshot.empty()}) {
    return GeometrySession(id: id, generation: snapshot.generation, snapshot: snapshot, createdAt: clock.now());
  }

  /// Restores a session from a map produced by [toMap].
  factory GeometrySession.fromMap(Map<String, dynamic> map) {
    return GeometrySession(
      id: map['id'] as int? ?? 0,
      generation: map['generation'] as int? ?? 0,
      snapshot: GeometrySnapshot.fromMap(map['snapshot'] as Map<String, dynamic>),
      createdAt: map['createdAt'] == null ? null : DateTime.tryParse(map['createdAt'] as String),
    );
  }

  /// Empty session.
  const GeometrySession.empty() : id = 0, generation = 0, snapshot = const GeometrySnapshot.empty(), createdAt = null;

  /// Session identifier.
  ///
  /// Increases when geometry lifecycle restarts.
  final int id;

  /// Geometry generation.
  final int generation;

  /// Session snapshot.
  final GeometrySnapshot snapshot;

  /// Creation time.
  final DateTime? createdAt;

  /// Whether session is valid.
  bool get isValid {
    return id > 0;
  }

  /// Whether session contains geometry.
  bool get hasGeometry {
    return snapshot.initialized;
  }

  /// Current geometry.
  VideoGeometry get geometry {
    return snapshot.geometry;
  }

  /// Updates snapshot.
  GeometrySession update(GeometrySnapshot snapshot) {
    return GeometrySession(id: id, generation: snapshot.generation, snapshot: snapshot, createdAt: createdAt);
  }

  /// Checks whether snapshot belongs
  /// to this session.
  bool accepts(GeometrySnapshot snapshot) {
    return snapshot.generation >= generation;
  }

  /// Creates next generation session.
  GeometrySession next() {
    return GeometrySession(id: id, generation: generation + 1, snapshot: snapshot, createdAt: createdAt);
  }

  /// Converts to a simple map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'generation': generation,
      'snapshot': snapshot.toMap(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, generation, snapshot, createdAt];

  @override
  String toString() {
    return 'GeometrySession('
        'id=$id, '
        'generation=$generation, '
        'valid=$isValid)';
  }
}
