import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/library.dart' show GenerationId, OperationId, PlayerId, SessionId, SlotId, SourceId;

/// Unique identifier of a request.
///
/// A [RequestId] identifies one concrete request performed during a player
/// operation.
///
/// An operation may create one or more requests.
///
/// For example:
///
/// ```text
/// OperationId: operation-001
///   ├── RequestId: request-001
///   ├── RequestId: request-002
///   └── RequestId: request-003
/// ```
///
/// This distinction is useful when one operation involves multiple
/// asynchronous requests, retries, source resolution steps, or backend
/// interactions.
///
/// A [RequestId] is different from:
///
/// - [PlayerId]: identifies a logical player.
/// - [SessionId]: identifies a playback session.
/// - [SlotId]: identifies a player pool slot.
/// - [SourceId]: identifies a media source.
/// - [OperationId]: identifies a logical operation.
/// - [GenerationId]: identifies a player generation.
///
/// A [RequestId] is immutable and value-based.
///
/// Two [RequestId] instances with the same [value] are considered equal
/// and can safely be used as keys in [Map] and [Set].
final class RequestId extends Equatable implements Comparable<RequestId> {
  /// Creates a [RequestId] from an existing non-empty value.
  ///
  /// The value is trimmed before validation.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory RequestId(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Request ID must not be empty.');
    }

    return RequestId._(normalized);
  }

  /// Creates a new unique runtime request identifier.
  ///
  /// `clock.now()` is used instead of [DateTime.now] so request ID generation
  /// can be controlled in tests.
  factory RequestId.generate() {
    final timestamp = clock.now().microsecondsSinceEpoch;
    final counter = _counter++;

    return RequestId._('request_${timestamp}_$counter');
  }

  const RequestId._(this.value);

  /// Parses an existing request identifier.
  ///
  /// Throws [ArgumentError] when [value] is empty.
  factory RequestId.parse(String value) => RequestId(value);

  /// Creates a [RequestId] from its JSON representation.
  ///
  /// The JSON representation is simply the raw string value.
  factory RequestId.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('RequestId JSON value must be a String.');
    }

    return RequestId(json);
  }

  static int _counter = 0;

  /// The raw identifier value.
  final String value;

  /// Returns the raw identifier value.
  String get rawValue => value;

  /// Returns whether this identifier is empty.
  ///
  /// A valid [RequestId] is never empty.
  bool get isEmpty => value.isEmpty;

  /// Returns whether this identifier is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns whether [value] can be used as a valid request identifier.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Converts this identifier to its JSON representation.
  String toJson() => value;

  /// Returns whether this identifier is equal to [other].
  bool isSameAs(RequestId other) {
    return this == other;
  }

  /// Returns whether this identifier is different from [other].
  bool isDifferentFrom(RequestId other) {
    return this != other;
  }

  /// Compares this identifier with [other].
  ///
  /// Ordering is based on the raw identifier value.
  @override
  int compareTo(RequestId other) {
    return value.compareTo(other.value);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}
