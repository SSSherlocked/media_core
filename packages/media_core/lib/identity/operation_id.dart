import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/library.dart' show GenerationId, PlayerId, RequestId, SessionId, SlotId, SourceId;

/// Unique identifier of an operation.
///
/// An [OperationId] identifies one logical operation performed by the
/// media core.
///
/// Examples of operations include:
///
/// ```text
/// open
/// play
/// pause
/// stop
/// seek
/// preload
/// dispose
/// switchSource
/// recover
/// ```
///
/// The operation itself is modeled by the `operation` layer. This class
/// only represents its identity.
///
/// [OperationId] is different from:
///
/// - [PlayerId]: identifies a logical player.
/// - [SessionId]: identifies a playback session.
/// - [SlotId]: identifies a player pool slot.
/// - [SourceId]: identifies a media source.
/// - [GenerationId]: identifies a player generation.
/// - [RequestId]: identifies one concrete request.
///
/// An [OperationId] is immutable and value-based.
///
/// Two [OperationId] instances with the same [value] are considered equal
/// and can safely be used as keys in [Map] and [Set].
final class OperationId extends Equatable implements Comparable<OperationId> {
  /// Creates an [OperationId] from an existing non-empty value.
  ///
  /// The value is trimmed before validation.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory OperationId(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Operation ID must not be empty.');
    }

    return OperationId._(normalized);
  }

  /// Creates a new unique runtime operation identifier.
  ///
  /// `clock.now()` is intentionally used instead of [DateTime.now] so the
  /// identifier can be deterministic in tests.
  factory OperationId.generate() {
    final timestamp = clock.now().microsecondsSinceEpoch;
    final counter = _counter++;

    return OperationId._('operation_${timestamp}_$counter');
  }

  const OperationId._(this.value);

  /// Parses an existing operation identifier.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory OperationId.parse(String value) => OperationId(value);

  /// Creates an [OperationId] from JSON.
  ///
  /// The JSON representation is simply the raw string value.
  factory OperationId.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('OperationId JSON value must be a String.');
    }

    return OperationId(json);
  }

  static int _counter = 0;

  /// Raw identifier value.
  final String value;

  /// Returns the raw identifier value.
  String get rawValue => value;

  /// Returns whether this identifier is empty.
  ///
  /// A valid [OperationId] is never empty.
  bool get isEmpty => value.isEmpty;

  /// Returns whether this identifier is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns whether [value] is a valid operation identifier value.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Converts this identifier to its JSON representation.
  String toJson() => value;

  /// Returns whether this operation is the same as [other].
  bool isSameAs(OperationId other) {
    return this == other;
  }

  /// Returns whether this operation is different from [other].
  bool isDifferentFrom(OperationId other) {
    return this != other;
  }

  /// Compares this operation identifier with [other].
  ///
  /// Ordering is based on the raw identifier value.
  @override
  int compareTo(OperationId other) {
    return value.compareTo(other.value);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}
