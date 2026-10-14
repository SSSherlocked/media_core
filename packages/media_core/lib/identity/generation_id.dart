import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/library.dart' show OperationId, PlayerId, RequestId, SessionId, SlotId, SourceId;

/// Unique identifier of a player generation.
///
/// A [GenerationId] identifies one generation of a player or session
/// lifecycle.
///
/// A player or session may go through multiple generations during its
/// lifetime.
///
/// For example:
///
/// ```text
/// PlayerId
///   │
///   ├── GenerationId #1
///   │     └── open source A
///   │
///   ├── GenerationId #2
///   │     └── switch to source B
///   │
///   └── GenerationId #3
///         └── recover / reinitialize
/// ```
///
/// A generation is especially useful for protecting the player core from
/// stale asynchronous results.
///
/// Example:
///
/// ```text
/// Generation 1
///     │
///     └── async open()
///
/// Generation 2
///     │
///     └── new open()
///
/// Generation 1 result arrives
///     │
///     └── ignored because it is stale
/// ```
///
/// [GenerationId] is different from:
///
/// - [PlayerId]: identifies a logical player.
/// - [SessionId]: identifies a playback session.
/// - [SlotId]: identifies a player pool slot.
/// - [SourceId]: identifies a media source.
/// - [OperationId]: identifies a logical operation.
/// - [RequestId]: identifies one concrete request.
///
/// A [GenerationId] is immutable and value-based.
///
/// Two [GenerationId] instances with the same [value] are considered equal
/// and can safely be used as keys in [Map] and [Set].
final class GenerationId extends Equatable implements Comparable<GenerationId> {
  /// Creates a [GenerationId] from an existing non-empty value.
  ///
  /// The value is trimmed before validation.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory GenerationId(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Generation ID must not be empty.');
    }

    return GenerationId._(normalized);
  }

  /// Creates a new unique runtime generation identifier.
  ///
  /// `clock.now()` is intentionally used instead of [DateTime.now] so the
  /// identifier can be deterministic in tests.
  factory GenerationId.generate() {
    final timestamp = clock.now().microsecondsSinceEpoch;
    final counter = _counter++;

    return GenerationId._('generation_${timestamp}_$counter');
  }

  const GenerationId._(this.value);

  /// Parses an existing generation identifier.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory GenerationId.parse(String value) => GenerationId(value);

  /// Creates a [GenerationId] from JSON.
  ///
  /// The JSON representation is simply the raw string value.
  factory GenerationId.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('GenerationId JSON value must be a String.');
    }

    return GenerationId(json);
  }

  static int _counter = 0;

  /// Raw identifier value.
  final String value;

  /// Returns the raw identifier value.
  String get rawValue => value;

  /// Returns whether this identifier is empty.
  ///
  /// A valid [GenerationId] is never empty.
  bool get isEmpty => value.isEmpty;

  /// Returns whether this identifier is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns whether [value] is a valid generation identifier value.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Converts this identifier to its JSON representation.
  String toJson() => value;

  /// Returns whether this generation is the same as [other].
  bool isSameAs(GenerationId other) {
    return this == other;
  }

  /// Returns whether this generation is different from [other].
  bool isDifferentFrom(GenerationId other) {
    return this != other;
  }

  /// Compares this generation identifier with [other].
  ///
  /// Ordering is based on the raw identifier value.
  @override
  int compareTo(GenerationId other) {
    return value.compareTo(other.value);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}
