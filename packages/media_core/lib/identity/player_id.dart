import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';

/// Unique identifier of a player instance.
///
/// A [PlayerId] identifies the logical player managed by `media_core`.
///
/// It does not identify:
///
/// - a playback session;
/// - a player slot;
/// - a media source;
/// - an adapter/backend.
///
/// Those concepts have their own identity types.
///
/// A [PlayerId] is immutable and value-based.
///
/// Two [PlayerId] instances with the same [value] are considered equal
/// and can safely be used as keys in [Map] and [Set].
final class PlayerId extends Equatable implements Comparable<PlayerId> {
  /// Creates a [PlayerId] from an existing non-empty value.
  ///
  /// The value is trimmed before validation.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory PlayerId(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'PlayerIdentity ID must not be empty.');
    }

    return PlayerId._(normalized);
  }

  /// Creates a new unique runtime player identifier.
  ///
  /// `clock.now()` is used instead of [DateTime.now] so the identifier
  /// generation can be controlled in tests.
  factory PlayerId.generate() {
    final timestamp = clock.now().microsecondsSinceEpoch;
    final counter = _counter++;

    return PlayerId._('player_${timestamp}_$counter');
  }

  const PlayerId._(this.value);

  /// Parses an existing player identifier.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory PlayerId.parse(String value) => PlayerId(value);

  /// Creates a [PlayerId] from its JSON representation.
  ///
  /// The JSON representation is simply the raw string value.
  factory PlayerId.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('PlayerId JSON value must be a String.');
    }

    return PlayerId(json);
  }

  static int _counter = 0;

  /// The raw identifier value.
  final String value;

  /// Returns the raw identifier value.
  String get rawValue => value;

  /// Returns whether the identifier is empty.
  ///
  /// A valid [PlayerId] is never empty.
  bool get isEmpty => value.isEmpty;

  /// Returns whether the identifier is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns whether [value] can be used as a valid player identifier.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Converts this identifier to its JSON representation.
  String toJson() => value;

  /// Returns whether this identifier is equal to [other].
  bool isSameAs(PlayerId other) {
    return this == other;
  }

  /// Returns whether this identifier is different from [other].
  bool isDifferentFrom(PlayerId other) {
    return this != other;
  }

  /// Compares this identifier with [other].
  ///
  /// Ordering is based on the raw identifier value.
  @override
  int compareTo(PlayerId other) {
    return value.compareTo(other.value);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}
