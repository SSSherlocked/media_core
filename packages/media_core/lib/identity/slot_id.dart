import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/library.dart' show GenerationId, OperationId, PlayerId, SessionId, SourceId;

/// Unique identifier of a player slot.
///
/// A [SlotId] identifies a logical slot managed by the player pool.
///
/// A slot represents a resource position that can be assigned to a player
/// session. The slot itself is not a player, session, or media source.
///
/// Typical relationship:
///
/// ```text
/// PlayerPool
///   ├── SlotId
///   │    └── PlayerId
///   │         └── SessionId
///   │
///   ├── SlotId
///   │    └── PlayerId
///   │         └── SessionId
///   │
///   └── SlotId
/// ```
///
/// A [SlotId] is different from:
///
/// - [PlayerId]: identifies a logical player.
/// - [SessionId]: identifies a playback session.
/// - [SourceId]: identifies a media source.
/// - [OperationId]: identifies one operation.
/// - [GenerationId]: identifies one generation.
///
/// A [SlotId] is immutable and value-based.
///
/// Two [SlotId] instances with the same [value] are considered equal
/// and can safely be used as keys in [Map] and [Set].
final class SlotId extends Equatable implements Comparable<SlotId> {
  /// Creates a [SlotId] from an existing non-empty value.
  ///
  /// The value is trimmed before validation.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory SlotId(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Slot ID must not be empty.');
    }

    return SlotId._(normalized);
  }

  /// Creates a new unique runtime slot identifier.
  ///
  /// `clock.now()` is used instead of [DateTime.now] so slot ID generation
  /// can be controlled in tests.
  factory SlotId.generate() {
    final timestamp = clock.now().microsecondsSinceEpoch;
    final counter = _counter++;

    return SlotId._('slot_${timestamp}_$counter');
  }

  const SlotId._(this.value);

  /// Parses an existing slot identifier.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory SlotId.parse(String value) => SlotId(value);

  /// Creates a [SlotId] from its JSON representation.
  ///
  /// The JSON representation is simply the raw string value.
  factory SlotId.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('SlotId JSON value must be a String.');
    }

    return SlotId(json);
  }

  static int _counter = 0;

  /// The raw identifier value.
  final String value;

  /// Returns the raw identifier value.
  String get rawValue => value;

  /// Returns whether this identifier is empty.
  ///
  /// A valid [SlotId] is never empty.
  bool get isEmpty => value.isEmpty;

  /// Returns whether this identifier is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns whether [value] can be used as a valid slot identifier.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Converts this identifier to its JSON representation.
  String toJson() => value;

  /// Returns whether this identifier is equal to [other].
  bool isSameAs(SlotId other) {
    return this == other;
  }

  /// Returns whether this identifier is different from [other].
  bool isDifferentFrom(SlotId other) {
    return this != other;
  }

  /// Compares this identifier with [other].
  ///
  /// Ordering is based on the raw identifier value.
  @override
  int compareTo(SlotId other) {
    return value.compareTo(other.value);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}
