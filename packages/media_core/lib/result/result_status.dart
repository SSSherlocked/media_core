import 'package:equatable/equatable.dart';
import 'package:media_core/result/result.dart' show Result;

/// Describes the terminal status of a [Result].
///
/// A [Result] represents a completed operation, therefore its status is
/// limited to:
///
/// - [success] — the operation completed successfully.
/// - [failure] — the operation completed with an error.
///
/// Asynchronous lifecycle states such as loading or running belong to
/// `AsyncResult`, not [ResultStatus].
///
/// A [ResultStatus] is immutable and value-based.
///
/// Two [ResultStatus] instances with the same [value] are considered equal.
final class ResultStatus extends Equatable {
  const ResultStatus._(this.value, this.name);

  /// Creates a custom result status.
  ///
  /// Custom statuses are supported for interoperability, but built-in
  /// statuses should be preferred whenever possible.
  factory ResultStatus.custom(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Result status must not be empty.');
    }

    return ResultStatus._(normalized, normalized);
  }

  /// Operation completed successfully.
  static const ResultStatus success = ResultStatus._('success', 'success');

  /// Operation completed with an error.
  static const ResultStatus failure = ResultStatus._('failure', 'failure');

  /// Machine-readable status value.
  final String value;

  /// Human-readable status name.
  final String name;

  /// Returns `true` when this is a built-in status.
  bool get isBuiltIn => _builtInStatuses.contains(value);

  /// Returns `true` when this is a custom status.
  bool get isCustom => !isBuiltIn;

  /// Returns `true` when this status represents success.
  bool get isSuccess => value == success.value;

  /// Returns `true` when this status represents failure.
  bool get isFailure => value == failure.value;

  /// Returns all built-in result statuses.
  static List<ResultStatus> get values {
    return List<ResultStatus>.unmodifiable(_builtInValues);
  }

  /// Resolves a built-in status from its machine-readable [value].
  ///
  /// Unknown values are mapped to [failure] rather than creating a custom
  /// status implicitly.
  ///
  /// Use [ResultStatus.custom] when custom status preservation is required.
  static ResultStatus fromValue(String value) {
    final normalized = value.trim();

    for (final status in _builtInValues) {
      if (status.value == normalized) {
        return status;
      }
    }

    return ResultStatus.failure;
  }

  /// Creates a result status from its JSON representation.
  ///
  /// JSON values are expected to be strings.
  ///
  /// Unknown values are resolved to [failure], matching [fromValue].
  static ResultStatus fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('ResultStatus JSON value must be a String.');
    }

    return fromValue(json);
  }

  /// Converts this status to its JSON representation.
  String toJson() => value;

  /// Returns whether [value] is a built-in result status.
  static bool isBuiltInValue(String value) {
    return _builtInStatuses.contains(value.trim());
  }

  /// Returns a copy of this status with optionally replaced fields.
  ///
  /// This is primarily useful for custom statuses.
  ResultStatus copyWith({String? value, String? name}) {
    final nextValue = (value ?? this.value).trim();
    final nextName = (name ?? this.name).trim();

    if (nextValue.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Result status must not be empty.');
    }

    if (nextName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Result status name must not be empty.');
    }

    return ResultStatus._(nextValue, nextName);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}

const List<ResultStatus> _builtInValues = <ResultStatus>[ResultStatus.success, ResultStatus.failure];

final Set<String> _builtInStatuses = <String>{for (final status in _builtInValues) status.value};
