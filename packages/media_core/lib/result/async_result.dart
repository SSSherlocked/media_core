import 'package:equatable/equatable.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/result/operation_result.dart';
import 'package:media_core/result/result.dart';
import 'package:media_core/result/result_error.dart';
import 'package:media_core/result/result_status.dart';

/// Represents the lifecycle state of an asynchronous player operation.
///
/// Unlike [Result], which only represents a terminal success or failure,
/// [AsyncResult] also represents the intermediate states of an asynchronous
/// operation.
///
/// The lifecycle is:
///
/// ```text
/// AsyncResult<T>
///      │
///      ├── idle
///      │
///      ├── running
///      │
///      ├── success
///      │
///      └── failure
/// ```
///
/// The relationship between the result types is:
///
/// ```text
/// AsyncResult<T>
///       │
///       └── OperationResult<T>
///                │
///                └── Result<T>
///                     ├── success
///                     └── failure
/// ```
///
/// [Result] describes the final outcome.
///
/// [OperationResult] adds operation-level metadata.
///
/// [AsyncResult] adds asynchronous lifecycle state.
///
/// This class does not:
///
/// - classify errors;
/// - determine retry policy;
/// - determine fallback policy;
/// - perform recovery;
/// - execute asynchronous operations.
///
/// Those responsibilities belong to their respective layers.
///
/// [AsyncResult] is immutable and value-based.
final class AsyncResult<T> extends Equatable {
  /// Creates an asynchronous result.
  ///
  /// [operationResult] should normally only be provided for terminal states.
  ///
  /// For [AsyncResultStatus.running], operation metadata can be supplied
  /// directly through [operation], [requestId], and [generationId].
  const AsyncResult({required this.status, this.operationResult, this.operation, this.requestId, this.generationId});

  /// Creates an idle asynchronous result.
  ///
  /// An idle result means that the operation has not started yet.
  const AsyncResult.idle()
    : status = AsyncResultStatus.idle,
      operationResult = null,
      operation = null,
      requestId = null,
      generationId = null;

  /// Creates a running asynchronous result.
  ///
  /// A running result means that the operation is currently executing.
  ///
  /// Operation metadata is preserved so that the caller can associate the
  /// running operation with its request and playback generation.
  const AsyncResult.running({this.operation, this.requestId, this.generationId})
    : status = AsyncResultStatus.running,
      operationResult = null;

  /// Creates a successful asynchronous result.
  AsyncResult.success(T value, {this.operation, this.requestId, this.generationId, Duration? duration})
    : status = AsyncResultStatus.success,
      operationResult = OperationResult<T>.success(
        value,
        operation: operation,
        requestId: requestId,
        generationId: generationId,
        duration: duration,
      );

  /// Creates a failed asynchronous result.
  AsyncResult.failure(ResultError error, {this.operation, this.requestId, this.generationId, Duration? duration})
    : status = AsyncResultStatus.failure,
      operationResult = OperationResult<T>.failure(
        error,
        operation: operation,
        requestId: requestId,
        generationId: generationId,
        duration: duration,
      );

  /// Creates an asynchronous result from an existing [OperationResult].
  ///
  /// The lifecycle state is inferred from the operation result:
  ///
  /// ```text
  /// Result.success -> AsyncResultStatus.success
  /// Result.failure -> AsyncResultStatus.failure
  /// ```
  AsyncResult.fromOperationResult(OperationResult<T> operationResult)
    : status = operationResult.isSuccess ? AsyncResultStatus.success : AsyncResultStatus.failure,
      operationResult = operationResult,
      operation = operationResult.operation,
      requestId = operationResult.requestId,
      generationId = operationResult.generationId;

  /// Creates an asynchronous result from an existing [Result].
  ///
  /// The lifecycle state is inferred from [result].
  AsyncResult.fromResult(
    Result<T> result, {
    String? operation,
    RequestId? requestId,
    GenerationId? generationId,
    Duration? duration,
  }) : this.fromOperationResult(
         OperationResult<T>.fromResult(
           result,
           operation: operation,
           requestId: requestId,
           generationId: generationId,
           duration: duration,
         ),
       );

  /// The current asynchronous lifecycle state.
  final AsyncResultStatus status;

  /// The terminal operation result.
  ///
  /// This is normally available for [AsyncResultStatus.success] and
  /// [AsyncResultStatus.failure].
  ///
  /// It is `null` for [AsyncResultStatus.idle] and
  /// [AsyncResultStatus.running].
  final OperationResult<T>? operationResult;

  /// The name of the operation.
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

  /// The unique identifier of the operation request.
  final RequestId? requestId;

  /// The playback generation associated with the operation.
  final GenerationId? generationId;

  /// Returns `true` when the operation has not started.
  bool get isIdle => status.isIdle;

  /// Returns `true` when the operation is currently running.
  bool get isRunning => status.isRunning;

  /// Returns `true` when the operation completed successfully.
  bool get isSuccess => status.isSuccess;

  /// Returns `true` when the operation failed.
  bool get isFailure => status.isFailure;

  /// Returns `true` when the operation reached a terminal state.
  bool get isCompleted => status.isCompleted;

  /// Returns `true` when the operation has not reached a terminal state.
  bool get isPending => status.isPending;

  /// Returns the successful value.
  ///
  /// Throws [StateError] when this result does not represent a successful
  /// operation.
  T get value {
    final result = operationResult;

    if (result == null || !result.isSuccess) {
      throw StateError('AsyncResult does not contain a successful value.');
    }

    return result.value;
  }

  /// Returns the failure error.
  ///
  /// Throws [StateError] when this result does not represent a failed
  /// operation.
  ResultError get error {
    final result = operationResult;

    if (result == null || !result.isFailure) {
      throw StateError('AsyncResult does not contain a failure.');
    }

    return result.error;
  }

  /// Returns the successful value, or `null` when unavailable.
  T? get valueOrNull {
    final result = operationResult;

    if (result == null || !result.isSuccess) {
      return null;
    }

    return result.valueOrNull;
  }

  /// Returns the failure error, or `null` when unavailable.
  ResultError? get errorOrNull {
    final result = operationResult;

    if (result == null || !result.isFailure) {
      return null;
    }

    return result.errorOrNull;
  }

  /// Returns the duration of the completed operation.
  Duration? get duration => operationResult?.duration;

  /// Returns whether an operation name is available.
  bool get hasOperation {
    final value = operation;
    return value != null && value.trim().isNotEmpty;
  }

  /// Returns whether a request ID is available.
  bool get hasRequestId => requestId != null;

  /// Returns whether a generation ID is available.
  bool get hasGenerationId => generationId != null;

  /// Returns whether a terminal operation result is available.
  bool get hasOperationResult => operationResult != null;

  /// Returns whether a successful value is available.
  bool get hasValue {
    return isSuccess && operationResult != null;
  }

  /// Returns whether a failure is available.
  bool get hasError {
    return isFailure && operationResult != null;
  }

  /// Returns the underlying terminal [Result].
  ///
  /// Throws [StateError] when the asynchronous operation has not completed.
  Result<T> toResult() {
    final result = operationResult;

    if (result == null || !isCompleted) {
      throw StateError('AsyncResult is not completed.');
    }

    return result.toResult();
  }

  /// Returns the underlying [Result], or `null` when the operation has not
  /// completed.
  Result<T>? get resultOrNull {
    final result = operationResult;

    if (result == null || !isCompleted) {
      return null;
    }

    return result.toResult();
  }

  /// Executes [action] when the operation succeeds.
  ///
  /// The result is immutable, so nothing is produced; callers keep using the
  /// original value.
  void onSuccess(void Function(T value) action) {
    if (isSuccess) {
      action(value);
    }
  }

  /// Executes [action] when the operation fails.
  ///
  /// The result is immutable, so nothing is produced; callers keep using the
  /// original value.
  void onFailure(void Function(ResultError error) action) {
    if (isFailure) {
      action(error);
    }
  }

  /// Maps the successful value to another type.
  ///
  /// Idle and running states remain unchanged.
  AsyncResult<R> map<R>(R Function(T value) transform) {
    final result = operationResult;

    if (result == null) {
      if (isRunning) {
        return AsyncResult<R>.running(operation: operation, requestId: requestId, generationId: generationId);
      }

      return AsyncResult<R>.idle();
    }

    return AsyncResult<R>.fromOperationResult(result.map(transform));
  }

  /// Maps the failure error.
  ///
  /// Idle and running states remain unchanged.
  AsyncResult<T> mapError(ResultError Function(ResultError error) transform) {
    final result = operationResult;

    if (result == null) {
      if (isRunning) {
        return AsyncResult<T>.running(operation: operation, requestId: requestId, generationId: generationId);
      }

      return AsyncResult<T>.idle();
    }

    return AsyncResult<T>.fromOperationResult(result.mapError(transform));
  }

  /// Returns the successful value or [fallback] when this result fails.
  ///
  /// For idle and running states, [fallback] is returned as well.
  T getOrElse(T fallback) {
    final result = operationResult;

    if (result == null) {
      return fallback;
    }

    return result.getOrElse(fallback);
  }

  /// Returns the successful value or computes a fallback when this result
  /// fails.
  ///
  /// For idle and running states, [pendingFallback] is returned.
  T getOrElseGet({required T Function(ResultError error) fallback, required T pendingFallback}) {
    final result = operationResult;

    if (result == null) {
      return pendingFallback;
    }

    return result.getOrElseGet(fallback);
  }

  /// Creates a copy with the supplied values replaced.
  ///
  /// State semantics:
  ///
  /// - `idle` clears all operation information;
  /// - `running` keeps only operation metadata;
  /// - `success` and `failure` require a matching terminal
  ///   [OperationResult].
  AsyncResult<T> copyWith({
    AsyncResultStatus? status,
    OperationResult<T>? operationResult,
    String? operation,
    RequestId? requestId,
    GenerationId? generationId,
  }) {
    final nextStatus = status ?? this.status;

    if (nextStatus.isIdle) {
      return AsyncResult<T>.idle();
    }

    if (nextStatus.isRunning) {
      return AsyncResult<T>.running(
        operation: operation ?? this.operation,
        requestId: requestId ?? this.requestId,
        generationId: generationId ?? this.generationId,
      );
    }

    if (!nextStatus.isSuccess && !nextStatus.isFailure) {
      throw ArgumentError.value(
        nextStatus,
        'status',
        'Only idle, running, success, and failure are supported '
            'by AsyncResult.',
      );
    }

    final nextOperationResult = operationResult ?? this.operationResult;

    if (nextOperationResult == null) {
      throw ArgumentError('operationResult is required for a completed AsyncResult.');
    }

    if (nextStatus.isSuccess && !nextOperationResult.isSuccess) {
      throw ArgumentError(
        'A successful AsyncResult requires a successful '
        'OperationResult.',
      );
    }

    if (nextStatus.isFailure && !nextOperationResult.isFailure) {
      throw ArgumentError(
        'A failed AsyncResult requires a failed '
        'OperationResult.',
      );
    }

    return AsyncResult<T>(
      status: nextStatus,
      operationResult: nextOperationResult,
      operation: operation ?? nextOperationResult.operation,
      requestId: requestId ?? nextOperationResult.requestId,
      generationId: generationId ?? nextOperationResult.generationId,
    );
  }

  /// Creates an idle result.
  AsyncResult<T> toIdle() {
    return AsyncResult<T>.idle();
  }

  /// Creates a running result while preserving operation metadata.
  AsyncResult<T> toRunning() {
    return AsyncResult<T>.running(operation: operation, requestId: requestId, generationId: generationId);
  }

  /// Creates a successful result while preserving operation metadata.
  AsyncResult<T> withSuccess(T value, {Duration? duration}) {
    return AsyncResult<T>.success(
      value,
      operation: operation,
      requestId: requestId,
      generationId: generationId,
      duration: duration,
    );
  }

  /// Creates a failed result while preserving operation metadata.
  AsyncResult<T> withFailure(ResultError error, {Duration? duration}) {
    return AsyncResult<T>.failure(
      error,
      operation: operation,
      requestId: requestId,
      generationId: generationId,
      duration: duration,
    );
  }

  /// Returns a copy with a new operation name.
  AsyncResult<T> withOperation(String operation) {
    final normalized = operation.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(operation, 'operation', 'Operation name must not be empty.');
    }

    return AsyncResult<T>(
      status: status,
      operationResult: operationResult,
      operation: normalized,
      requestId: requestId,
      generationId: generationId,
    );
  }

  /// Returns a copy without an operation name.
  AsyncResult<T> withoutOperation() {
    return AsyncResult<T>(
      status: status,
      operationResult: operationResult,
      requestId: requestId,
      generationId: generationId,
    );
  }

  /// Returns a copy with [requestId] attached.
  AsyncResult<T> withRequestId(RequestId requestId) {
    return AsyncResult<T>(
      status: status,
      operationResult: operationResult,
      operation: operation,
      requestId: requestId,
      generationId: generationId,
    );
  }

  /// Returns a copy without a request ID.
  AsyncResult<T> withoutRequestId() {
    return AsyncResult<T>(
      status: status,
      operationResult: operationResult,
      operation: operation,
      generationId: generationId,
    );
  }

  /// Returns a copy with [generationId] attached.
  AsyncResult<T> withGenerationId(GenerationId generationId) {
    return AsyncResult<T>(
      status: status,
      operationResult: operationResult,
      operation: operation,
      requestId: requestId,
      generationId: generationId,
    );
  }

  /// Returns a copy without a generation ID.
  AsyncResult<T> withoutGenerationId() {
    return AsyncResult<T>(status: status, operationResult: operationResult, operation: operation, requestId: requestId);
  }

  /// Returns a copy with [duration] attached to the terminal result.
  ///
  /// Returns this result unchanged when no terminal operation result exists.
  AsyncResult<T> withDuration(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Operation duration must not be negative.');
    }

    final currentResult = operationResult;

    if (currentResult == null) {
      return this;
    }

    return AsyncResult<T>.fromOperationResult(currentResult.copyWith(duration: duration));
  }

  /// Returns the underlying terminal operation result.
  OperationResult<T>? get terminalResult => operationResult;

  @override
  List<Object?> get props => <Object?>[status, operationResult, operation, requestId, generationId];

  @override
  String toString() {
    final buffer = StringBuffer('AsyncResult(')
      ..write('status: ')
      ..write(status.value);

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

    final currentResult = operationResult;
    if (currentResult != null) {
      buffer
        ..write(', result: ')
        ..write(currentResult);
    }

    buffer.write(')');

    return buffer.toString();
  }
}

/// Represents the lifecycle state of an [AsyncResult].
///
/// This is intentionally separate from [ResultStatus].
///
/// [ResultStatus] only describes terminal outcomes:
///
/// ```text
/// success
/// failure
/// ```
///
/// [AsyncResultStatus] describes the complete asynchronous lifecycle:
///
/// ```text
/// idle
/// running
/// success
/// failure
/// ```
///
/// Keeping these concepts separate prevents an in-progress asynchronous
/// operation from being incorrectly represented as a terminal result.
///
/// [AsyncResultStatus] is immutable and value-based.
final class AsyncResultStatus extends Equatable {
  const AsyncResultStatus._(this.value, this.name);

  /// Creates a custom asynchronous result status.
  factory AsyncResultStatus.custom(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Async result status must not be empty.');
    }

    return AsyncResultStatus._(normalized, normalized);
  }

  /// No asynchronous operation has started.
  static const AsyncResultStatus idle = AsyncResultStatus._('idle', 'idle');

  /// The asynchronous operation is currently running.
  static const AsyncResultStatus running = AsyncResultStatus._('running', 'running');

  /// The asynchronous operation completed successfully.
  static const AsyncResultStatus success = AsyncResultStatus._('success', 'success');

  /// The asynchronous operation completed with a failure.
  static const AsyncResultStatus failure = AsyncResultStatus._('failure', 'failure');

  /// Machine-readable status value.
  final String value;

  /// Human-readable status name.
  final String name;

  /// Returns `true` when this is a built-in status.
  bool get isBuiltIn {
    return _builtInStatuses.contains(value);
  }

  /// Returns `true` when this is a custom status.
  bool get isCustom => !isBuiltIn;

  /// Returns `true` when this is the idle state.
  bool get isIdle => value == idle.value;

  /// Returns `true` when this is the running state.
  bool get isRunning => value == running.value;

  /// Returns `true` when this is the successful terminal state.
  bool get isSuccess => value == success.value;

  /// Returns `true` when this is the failed terminal state.
  bool get isFailure => value == failure.value;

  /// Returns `true` when this is a terminal state.
  bool get isCompleted => isSuccess || isFailure;

  /// Returns `true` when this is a non-terminal state.
  bool get isPending => isIdle || isRunning;

  /// Returns all built-in asynchronous lifecycle states.
  static List<AsyncResultStatus> get values {
    return List<AsyncResultStatus>.unmodifiable(_builtInValues);
  }

  /// Resolves a built-in status from [value].
  ///
  /// Unknown values are mapped to [idle].
  ///
  /// Use [AsyncResultStatus.custom] when custom status preservation is required.
  static AsyncResultStatus fromValue(String value) {
    final normalized = value.trim();

    for (final status in _builtInValues) {
      if (status.value == normalized) {
        return status;
      }
    }

    return AsyncResultStatus.idle;
  }

  /// Creates a status from its JSON representation.
  ///
  /// Unknown values are resolved to [idle], matching [fromValue].
  static AsyncResultStatus fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('AsyncResultStatus JSON value must be a String.');
    }

    return fromValue(json);
  }

  /// Converts this status to its JSON representation.
  String toJson() => value;

  /// Returns whether [value] represents a built-in status.
  static bool isBuiltInValue(String value) {
    return _builtInStatuses.contains(value.trim());
  }

  /// Returns a copy with optionally replaced fields.
  ///
  /// This method preserves custom values when [value] is not one of the
  /// built-in lifecycle states.
  AsyncResultStatus copyWith({String? value, String? name}) {
    final nextValue = (value ?? this.value).trim();
    final nextName = (name ?? this.name).trim();

    if (nextValue.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Async result status must not be empty.');
    }

    if (nextName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Async result status name must not be empty.');
    }

    return AsyncResultStatus._(nextValue, nextName);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}

const List<AsyncResultStatus> _builtInValues = <AsyncResultStatus>[
  AsyncResultStatus.idle,
  AsyncResultStatus.running,
  AsyncResultStatus.success,
  AsyncResultStatus.failure,
];

final Set<String> _builtInStatuses = <String>{for (final status in _builtInValues) status.value};
