import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/library.dart' show GenerationId, OperationId, PlayerId, SessionId, SlotId;

/// Unique identifier of a media source.
///
/// A [SourceId] identifies a logical media source used by the player core.
///
/// A source represents the identity of a playable media input. The actual
/// source details, such as URL, protocol, headers, format, and metadata,
/// are handled by the `source` layer.
///
/// Typical relationship:
///
/// ```text
/// PlayerIdentity
///   └── Session
///         └── SourceId
///               └── PlayerSource
/// ```
///
/// A [SourceId] is different from:
///
/// - [PlayerId]: identifies a logical player.
/// - [SessionId]: identifies a playback session.
/// - [SlotId]: identifies a player pool slot.
/// - [OperationId]: identifies one operation.
/// - [GenerationId]: identifies one generation.
///
/// A [SourceId] is immutable and value-based.
///
/// Two [SourceId] instances with the same [value] are considered equal
/// and can safely be used as keys in [Map] and [Set].
final class SourceId extends Equatable implements Comparable<SourceId> {
  /// Creates a [SourceId] from an existing non-empty value.
  ///
  /// The value is trimmed before validation.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory SourceId(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Source ID must not be empty.');
    }

    return SourceId._(normalized);
  }

  /// Creates a new unique runtime source identifier.
  ///
  /// `clock.now()` is used instead of [DateTime.now] so source ID generation
  /// can be controlled in tests.
  factory SourceId.generate() {
    final timestamp = clock.now().microsecondsSinceEpoch;
    final counter = _counter++;

    return SourceId._('source_${timestamp}_$counter');
  }

  /// Creates an unknown source identifier.
  ///
  /// Used when source identity is not available.
  ///
  /// This is different from an empty value.
  /// Empty identifiers are invalid.
  ///
  /// Unknown identifiers are useful for:
  ///
  /// - error states
  /// - diagnostics
  /// - temporary objects
  /// - placeholder models
  factory SourceId.unknown() {
    return const SourceId._('unknown');
  }

  const SourceId._(this.value);

  /// Parses an existing source identifier.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory SourceId.parse(String value) => SourceId(value);

  /// Creates a [SourceId] from its JSON representation.
  ///
  /// The JSON representation is simply the raw string value.
  factory SourceId.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('SourceId JSON value must be a String.');
    }

    return SourceId(json);
  }

  static int _counter = 0;

  /// The raw identifier value.
  final String value;

  /// Returns the raw identifier value.
  String get rawValue => value;

  /// Returns whether this identifier is empty.
  ///
  /// A valid [SourceId] is never empty.
  bool get isEmpty => value.isEmpty;

  /// Returns whether this identifier is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns whether this identifier represents unknown source.
  bool get isUnknown {
    return value == 'unknown';
  }

  /// Returns whether [value] can be used as a valid source identifier.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Converts this identifier to its JSON representation.
  String toJson() => value;

  /// Returns whether this identifier is equal to [other].
  bool isSameAs(SourceId other) {
    return this == other;
  }

  /// Returns whether this identifier is different from [other].
  bool isDifferentFrom(SourceId other) {
    return this != other;
  }

  /// Compares this identifier with [other].
  ///
  /// Ordering is based on the raw identifier value.
  @override
  int compareTo(SourceId other) {
    return value.compareTo(other.value);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}
