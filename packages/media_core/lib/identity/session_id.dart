import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/library.dart' show GenerationId, OperationId, PlayerId, SlotId, SourceId;

/// Unique identifier of a player session.
///
/// A [SessionId] identifies one logical playback session.
///
/// A player can have multiple sessions during its lifetime:
///
/// ```text
/// PlayerId
///   ├── SessionId #1
///   ├── SessionId #2
///   └── SessionId #3
/// ```
///
/// A [SessionId] is different from:
///
/// - [PlayerId]: identifies the logical player instance.
/// - [SlotId]: identifies a player slot.
/// - [SourceId]: identifies a media source.
/// - [OperationId]: identifies one operation.
/// - [GenerationId]: identifies one generation of a session.
///
/// A [SessionId] is immutable and value-based.
///
/// Two [SessionId] instances with the same [value] are considered equal
/// and can safely be used as keys in [Map] and [Set].
final class SessionId extends Equatable implements Comparable<SessionId> {
  /// Creates a [SessionId] from an existing non-empty value.
  ///
  /// The value is trimmed before validation.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory SessionId(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Session ID must not be empty.');
    }

    return SessionId._(normalized);
  }

  /// Creates a new unique runtime session identifier.
  ///
  /// `clock.now()` is used instead of [DateTime.now] so session ID generation
  /// can be controlled in tests.
  factory SessionId.generate() {
    final timestamp = clock.now().microsecondsSinceEpoch;
    final counter = _counter++;

    return SessionId._('session_${timestamp}_$counter');
  }

  const SessionId._(this.value);

  /// Parses an existing session identifier.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory SessionId.parse(String value) => SessionId(value);

  /// Creates a [SessionId] from its JSON representation.
  ///
  /// The JSON representation is simply the raw string value.
  factory SessionId.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('SessionId JSON value must be a String.');
    }

    return SessionId(json);
  }

  static int _counter = 0;

  /// The raw identifier value.
  final String value;

  /// Returns the raw identifier value.
  String get rawValue => value;

  /// Returns whether this identifier is empty.
  ///
  /// A valid [SessionId] is never empty.
  bool get isEmpty => value.isEmpty;

  /// Returns whether this identifier is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns whether [value] can be used as a valid session identifier.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Converts this identifier to its JSON representation.
  String toJson() => value;

  /// Returns whether this identifier is equal to [other].
  bool isSameAs(SessionId other) {
    return this == other;
  }

  /// Returns whether this identifier is different from [other].
  bool isDifferentFrom(SessionId other) {
    return this != other;
  }

  /// Compares this identifier with [other].
  ///
  /// Ordering is based on the raw identifier value.
  @override
  int compareTo(SessionId other) {
    return value.compareTo(other.value);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}
