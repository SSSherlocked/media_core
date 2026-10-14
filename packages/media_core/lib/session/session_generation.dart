import 'package:equatable/equatable.dart';
import 'package:media_core/identity/generation_id.dart';

/// Represents a playback generation inside a session.
///
/// A session can contain multiple generations when:
///
/// - source changes
/// - player recreates
/// - retry happens
/// - fallback switches backend
///
/// Older generations must not affect newer ones.
final class SessionGeneration extends Equatable implements Comparable<SessionGeneration> {
  /// Creates a session generation.
  const SessionGeneration({required this.id, required this.number});

  /// Creates the first generation.
  factory SessionGeneration.initial() {
    return SessionGeneration(id: GenerationId.generate(), number: 0);
  }

  /// Generation identity.
  final GenerationId id;

  /// Increasing generation number.
  final int number;

  /// Whether this is the initial generation.
  bool get isInitial {
    return number == 0;
  }

  /// Creates the next generation.
  SessionGeneration next() {
    return SessionGeneration(id: GenerationId.generate(), number: number + 1);
  }

  /// Whether another generation is newer.
  bool isNewerThan(SessionGeneration other) {
    return number > other.number;
  }

  /// Whether another generation is older.
  bool isOlderThan(SessionGeneration other) {
    return number < other.number;
  }

  /// Checks generation equality.
  bool isSameAs(SessionGeneration other) {
    return this == other;
  }

  /// Compares generations.
  @override
  int compareTo(SessionGeneration other) {
    return number.compareTo(other.number);
  }

  @override
  List<Object?> get props => [id, number];

  @override
  String toString() {
    return 'SessionGeneration('
        'id=$id, '
        'number=$number'
        ')';
  }
}
