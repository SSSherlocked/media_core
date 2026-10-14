import 'package:equatable/equatable.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/result/result.dart';
import 'package:media_core/result/result_error.dart';
import 'package:media_core/result/result_status.dart';

/// Represents the result of a specific player operation.
///
/// [OperationResult] is a lightweight immutable wrapper around [Result]
/// that adds metadata describing the operation which produced the result.
///
/// The relationship is:
///
/// ```text
/// OperationResult<T>
///        │
///        └── Result<T>
///              ├── success
///              └── failure
/// ```
///
/// Operation metadata is kept separate from the actual result value so that
/// callers can identify and diagnose individual player operations.
///
/// Typical metadata includes:
///
/// - [operation] — operation name, such as `open`, `play`, `pause`, or `seek`;
/// - [requestId] — identifier of the individual operation request;
/// - [generationId] — identifier of the current playback generation;
/// - [duration] — time spent executing the operation.
///
/// This class does not:
///
/// - classify errors;
/// - determine retry policy;
/// - determine fallback policy;
/// - perform recovery;
/// - manage asynchronous lifecycle state.
///
/// Those responsibilities belong to the corresponding layers.
final class OperationResult<T> extends Equatable {
  /// Creates an operation result from an existing [Result].
  const OperationResult({required this.result, this.operation, this.requestId, this.generationId, this.duration});

  /// Creates a successful operation result.
  OperationResult.success(
    T value, {
    String? operation,
    RequestId? requestId,
    GenerationId? generationId,
    Duration? duration,
  }) : this(
         result: Result<T>.success(value),
         operation: operation,
         requestId: requestId,
         generationId: generationId,
         duration: duration,
       );

  /// Creates a failed operation result.
  OperationResult.failure(
    ResultError error, {
    String? operation,
    RequestId? requestId,
    GenerationId? generationId,
    Duration? duration,
  }) : this(
         result: Result<T>.failure(error),
         operation: operation,
         requestId: requestId,
         generationId: generationId,
         duration: duration,
       );

  /// Creates an operation result from an existing [Result].
  const OperationResult.fromResult(
    Result<T> result, {
    String? operation,
    RequestId? requestId,
    GenerationId? generationId,
    Duration? duration,
  }) : this(result: result, operation: operation, requestId: requestId, generationId: generationId, duration: duration);

  /// The underlying operation result.
  final Result<T> result;

  /// The name of the operation that produced this result.
  ///
  /// Examples:
  ///
  /// ```text
  /// open
  /// play
  /// pause
  /// stop
  /// seek
  /// setVolume
  /// setPlaybackRate
  /// ```
  final String? operation;

  /// The unique identifier of this operation request.
  final RequestId? requestId;

  /// The playback generation associated with this operation.
  final GenerationId? generationId;

  /// The amount of time spent executing the operation.
  final Duration? duration;

  /// Returns the status of the underlying result.
  ResultStatus get status => result.status;

  /// Returns `true` when the operation completed successfully.
  bool get isSuccess => result.isSuccess;

  /// Returns `true` when the operation failed.
  bool get isFailure => result.isFailure;

  /// Returns the successful value.
  ///
  /// Throws [StateError] when this operation failed.
  T get value => result.value;

  /// Returns the error contained by the failed result.
  ///
  /// Throws [StateError] when this operation succeeded.
  ResultError get error => result.error;

  /// Returns the successful value.
  ///
  /// Returns `null` when the operation failed.
  T? get valueOrNull => result.getOrNull();

  /// Returns the operation error.
  ///
  /// Returns `null` when the operation succeeded.
  ResultError? get errorOrNull => result.errorOrNull;

  /// Returns `true` when a non-empty operation name is available.
  bool get hasOperation {
    final value = operation;
    return value != null && value.trim().isNotEmpty;
  }

  /// Returns `true` when a request ID is available.
  bool get hasRequestId => requestId != null;

  /// Returns `true` when a generation ID is available.
  bool get hasGenerationId => generationId != null;

  /// Returns `true` when an execution duration is available.
  bool get hasDuration => duration != null;

  /// Maps the successful value to another type.
  ///
  /// Operation metadata is preserved.
  ///
  /// When this operation fails, the existing failure is preserved and
  /// [transform] is not called.
  OperationResult<R> map<R>(R Function(T value) transform) {
    return OperationResult<R>(
      result: result.map(transform),
      operation: operation,
      requestId: requestId,
      generationId: generationId,
      duration: duration,
    );
  }

  /// Maps the underlying [ResultError].
  ///
  /// Successful results are preserved and [transform] is not called.
  OperationResult<T> mapError(ResultError Function(ResultError error) transform) {
    return OperationResult<T>(
      result: result.mapError(transform),
      operation: operation,
      requestId: requestId,
      generationId: generationId,
      duration: duration,
    );
  }

  /// Executes [action] when the operation succeeds.
  ///
  /// The operation result is immutable, so nothing is produced; callers keep
  /// using the original value.
  void onSuccess(void Function(T value) action) {
    result.onSuccess(action);
  }

  /// Executes [action] when the operation fails.
  ///
  /// The operation result is immutable, so nothing is produced; callers keep
  /// using the original value.
  void onFailure(void Function(ResultError error) action) {
    result.onFailure(action);
  }

  /// Folds the underlying result into a single value.
  ///
  /// Operation metadata is not involved in the fold operation.
  R fold<R>({required R Function(T value) onSuccess, required R Function(ResultError error) onFailure}) {
    return result.fold(onSuccess: onSuccess, onFailure: onFailure);
  }

  /// Returns the successful value or [fallback] when the operation fails.
  T getOrElse(T fallback) {
    return result.getOrElse(fallback);
  }

  /// Returns the successful value or computes a fallback when the operation
  /// fails.
  T getOrElseGet(T Function(ResultError error) fallback) {
    return result.getOrElseGet(fallback);
  }

  /// Converts this operation result into the underlying [Result].
  Result<T> toResult() => result;

  /// Returns a copy with the supplied non-null values replaced.
  ///
  /// Nullable metadata cannot be explicitly cleared through [copyWith].
  /// Use [clear] when a metadata field needs to be removed.
  OperationResult<T> copyWith({
    Result<T>? result,
    String? operation,
    RequestId? requestId,
    GenerationId? generationId,
    Duration? duration,
  }) {
    return OperationResult<T>(
      result: result ?? this.result,
      operation: operation ?? this.operation,
      requestId: requestId ?? this.requestId,
      generationId: generationId ?? this.generationId,
      duration: duration ?? this.duration,
    );
  }

  /// Returns a copy with selected metadata fields removed.
  OperationResult<T> clear({
    bool operation = false,
    bool requestId = false,
    bool generationId = false,
    bool duration = false,
  }) {
    return OperationResult<T>(
      result: result,
      operation: operation ? null : this.operation,
      requestId: requestId ? null : this.requestId,
      generationId: generationId ? null : this.generationId,
      duration: duration ? null : this.duration,
    );
  }

  /// Returns a copy with a new operation name.
  OperationResult<T> withOperation(String operation) {
    final normalized = operation.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(operation, 'operation', 'Operation name must not be empty.');
    }

    return OperationResult<T>(
      result: result,
      operation: normalized,
      requestId: requestId,
      generationId: generationId,
      duration: duration,
    );
  }

  /// Returns a copy without an operation name.
  OperationResult<T> withoutOperation() {
    return OperationResult<T>(result: result, requestId: requestId, generationId: generationId, duration: duration);
  }

  /// Returns a copy with [requestId] attached.
  OperationResult<T> withRequestId(RequestId requestId) {
    return OperationResult<T>(
      result: result,
      operation: operation,
      requestId: requestId,
      generationId: generationId,
      duration: duration,
    );
  }

  /// Returns a copy without a request ID.
  OperationResult<T> withoutRequestId() {
    return OperationResult<T>(result: result, operation: operation, generationId: generationId, duration: duration);
  }

  /// Returns a copy with [generationId] attached.
  OperationResult<T> withGenerationId(GenerationId generationId) {
    return OperationResult<T>(
      result: result,
      operation: operation,
      requestId: requestId,
      generationId: generationId,
      duration: duration,
    );
  }

  /// Returns a copy without a generation ID.
  OperationResult<T> withoutGenerationId() {
    return OperationResult<T>(result: result, operation: operation, requestId: requestId, duration: duration);
  }

  /// Returns a copy with [duration] attached.
  OperationResult<T> withDuration(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Operation duration must not be negative.');
    }

    return OperationResult<T>(
      result: result,
      operation: operation,
      requestId: requestId,
      generationId: generationId,
      duration: duration,
    );
  }

  /// Returns a copy without an execution duration.
  OperationResult<T> withoutDuration() {
    return OperationResult<T>(result: result, operation: operation, requestId: requestId, generationId: generationId);
  }

  @override
  List<Object?> get props => <Object?>[result, operation, requestId, generationId, duration];

  @override
  String toString() {
    final buffer = StringBuffer('OperationResult(')
      ..write('result: ')
      ..write(result);

    if (hasOperation) {
      buffer
        ..write(', operation: ')
        ..write(operation);
    }

    if (hasRequestId) {
      buffer
        ..write(', requestId: ')
        ..write(requestId);
    }

    if (hasGenerationId) {
      buffer
        ..write(', generationId: ')
        ..write(generationId);
    }

    if (hasDuration) {
      buffer
        ..write(', duration: ')
        ..write(duration);
    }

    buffer.write(')');

    return buffer.toString();
  }
}
