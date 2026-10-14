import 'package:equatable/equatable.dart';
import 'package:media_core/result/result_error.dart';
import 'package:media_core/result/result_status.dart';

/// Represents the result of a completed operation.
///
/// A [Result] is either:
///
/// - a successful result containing a value of type [T];
/// - a failed result containing a [ResultError].
///
/// [Result] only represents the outcome of a completed operation.
///
/// It does not represent asynchronous lifecycle states such as loading,
/// pending, or running. Those concerns belong to higher-level abstractions
/// such as `AsyncResult`.
///
/// Example:
///
/// ```dart
/// final Result<String> result = Result.success('http://example.com');
///
/// if (result.isSuccess) {
///   print(result.value);
/// }
/// ```
sealed class Result<T> extends Equatable {
  const Result._();

  /// Creates a successful result containing [value].
  const factory Result.success(T value) = ResultSuccess<T>;

  /// Creates a failed result containing [error].
  const factory Result.failure(ResultError error) = ResultFailure<T>;

  /// Returns the current result status.
  ResultStatus get status;

  /// Returns `true` when this result represents success.
  bool get isSuccess => status == ResultStatus.success;

  /// Returns `true` when this result represents failure.
  bool get isFailure => status == ResultStatus.failure;

  /// Returns the successful value.
  ///
  /// Throws [StateError] when this result is a failure.
  T get value {
    throw StateError('Result does not contain a success value.');
  }

  /// Returns the failure error.
  ///
  /// Throws [StateError] when this result is successful.
  ResultError get error {
    throw StateError('Result does not contain an error.');
  }

  /// Transforms the successful value using [transform].
  ///
  /// A failure is preserved without invoking [transform].
  Result<R> map<R>(R Function(T value) transform) {
    if (this case final ResultSuccess<T> success) {
      return Result<R>.success(transform(success.value));
    }

    final failure = this as ResultFailure<T>;

    return Result<R>.failure(failure.error);
  }

  /// Transforms the contained error using [transform].
  ///
  /// A successful result is preserved without invoking [transform].
  Result<T> mapError(ResultError Function(ResultError error) transform) {
    if (this case final ResultFailure<T> failure) {
      return Result<T>.failure(transform(failure.error));
    }

    final success = this as ResultSuccess<T>;

    return Result<T>.success(success.value);
  }

  /// Folds this result into a single value.
  ///
  /// [onSuccess] is called for successful results.
  ///
  /// [onFailure] is called for failed results.
  R fold<R>({required R Function(T value) onSuccess, required R Function(ResultError error) onFailure}) {
    if (this case final ResultSuccess<T> success) {
      return onSuccess(success.value);
    }

    final failure = this as ResultFailure<T>;

    return onFailure(failure.error);
  }

  /// Returns the successful value or [fallback] when this result fails.
  T getOrElse(T fallback) {
    if (this case final ResultSuccess<T> success) {
      return success.value;
    }

    return fallback;
  }

  /// Returns the successful value or computes one using [fallback].
  ///
  /// The fallback function is only invoked when this result is a failure.
  T getOrElseGet(T Function(ResultError error) fallback) {
    if (this case final ResultSuccess<T> success) {
      return success.value;
    }

    return fallback(error);
  }

  /// Returns the successful value or `null` when this result fails.
  T? getOrNull() {
    if (this case final ResultSuccess<T> success) {
      return success.value;
    }

    return null;
  }

  /// Returns the contained error or `null` when this result succeeds.
  ResultError? get errorOrNull {
    if (this case final ResultFailure<T> failure) {
      return failure.error;
    }

    return null;
  }

  /// Executes [action] when this result succeeds.
  ///
  /// The result is immutable, so nothing is produced; callers keep using the
  /// original result.
  void onSuccess(void Function(T value) action) {
    if (this case final ResultSuccess<T> success) {
      action(success.value);
    }
  }

  /// Executes [action] when this result fails.
  ///
  /// The result is immutable, so nothing is produced; callers keep using the
  /// original result.
  void onFailure(void Function(ResultError error) action) {
    if (this case final ResultFailure<T> failure) {
      action(failure.error);
    }
  }

  /// Converts this result to a successful [Result<void>].
  ///
  /// The original successful value is discarded.
  ///
  /// A failure is preserved.
  Result<void> ignoreValue() {
    if (this case final ResultFailure<T> failure) {
      return Result<void>.failure(failure.error);
    }

    return const Result<void>.success(null);
  }

  /// Converts this result to a nullable value.
  ///
  /// Returns `null` when this result is a failure.
  T? get nullableValue => getOrNull();

  @override
  String toString() {
    return fold(onSuccess: (value) => 'Result.success($value)', onFailure: (error) => 'Result.failure($error)');
  }
}

/// Successful [Result] implementation.
final class ResultSuccess<T> extends Result<T> {
  /// Wraps [value] as the outcome of an operation that produced it.
  const ResultSuccess(this.value) : super._();

  /// Successful result value.
  @override
  final T value;

  @override
  ResultStatus get status => ResultStatus.success;

  @override
  List<Object?> get props => <Object?>[ResultStatus.success, value];
}

/// Failed [Result] implementation.
final class ResultFailure<T> extends Result<T> {
  /// Wraps [error] as the outcome of an operation that did not produce a value.
  const ResultFailure(this.error) : super._();

  /// Error describing why the operation failed.
  @override
  final ResultError error;

  @override
  ResultStatus get status => ResultStatus.failure;

  @override
  List<Object?> get props => <Object?>[ResultStatus.failure, error];
}
