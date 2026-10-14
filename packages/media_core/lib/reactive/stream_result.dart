/// Represents the state/result of an asynchronous operation.
///
/// This is intentionally independent from Flutter and can be used by
/// repositories, services, controllers, and stream pipelines.
sealed class StreamResult<T> {
  const StreamResult();

  /// Whether the operation is still in flight.
  bool get isLoading => this is StreamLoadingResult<T>;

  /// Whether the operation produced a value.
  bool get isSuccess => this is StreamSuccess<T>;

  /// Whether the operation failed.
  bool get isError => this is StreamErrorResult<T>;

  /// Whether the operation finished without a usable value.
  bool get isEmpty => this is StreamEmptyResult<T>;

  /// Returns the successful value, or `null` for other states.
  T? get data {
    final result = this;

    if (result is StreamSuccess<T>) {
      return result.data;
    }

    return null;
  }

  /// Returns the error, or `null` when this is not an error result.
  Object? get error {
    final result = this;

    if (result is StreamErrorResult<T>) {
      return result.error;
    }

    return null;
  }

  /// Returns the stack trace of an error result.
  StackTrace? get stackTrace {
    final result = this;

    if (result is StreamErrorResult<T>) {
      return result.stackTrace;
    }

    return null;
  }

  /// Pattern matching helper.
  R when<R>({
    required R Function() loading,
    required R Function(T data) success,
    required R Function(Object error, StackTrace? stackTrace) error,
    required R Function() empty,
  }) {
    final result = this;

    if (result is StreamLoadingResult<T>) {
      return loading();
    }

    if (result is StreamSuccess<T>) {
      return success(result.data);
    }

    if (result is StreamErrorResult<T>) {
      return error(result.error, result.stackTrace);
    }

    return empty();
  }

  /// Map the successful value to another type.
  StreamResult<R> map<R>(R Function(T value) mapper) {
    final result = this;

    if (result is StreamLoadingResult<T>) {
      return StreamLoadingResult<R>();
    }

    if (result is StreamSuccess<T>) {
      return StreamSuccess<R>(mapper(result.data));
    }

    if (result is StreamErrorResult<T>) {
      return StreamErrorResult<R>(result.error, stackTrace: result.stackTrace, message: result.message);
    }

    return StreamEmptyResult<R>();
  }
}

/// Loading state.
final class StreamLoadingResult<T> extends StreamResult<T> {
  /// Marks the operation as in flight, optionally saying what via [message].
  const StreamLoadingResult({this.message});

  /// Text describing the work in progress, shown by busy indicators.
  final String? message;

  @override
  String toString() {
    return 'StreamLoadingResult(message: $message)';
  }
}

/// Successful result.
final class StreamSuccess<T> extends StreamResult<T> {
  /// Wraps the produced [data].
  const StreamSuccess(this.data);

  @override
  final T data;

  @override
  String toString() {
    return 'StreamSuccess<$T>(data: $data)';
  }
}

/// Error result.
final class StreamErrorResult<T> extends StreamResult<T> {
  /// Reports [error], optionally with the [stackTrace] it came with and a
  /// displayable [message].
  const StreamErrorResult(this.error, {this.stackTrace, this.message});

  @override
  final Object error;
  @override
  final StackTrace? stackTrace;

  /// Text the UI can show instead of the raw [error] description.
  final String? message;

  @override
  String toString() {
    return 'StreamErrorResult<$T>('
        'error: $error, '
        'message: $message'
        ')';
  }
}

/// Empty result.
///
/// This is different from [StreamSuccess]:
/// - Success means an actual value was returned.
/// - Empty means the operation completed but there was no usable value.
final class StreamEmptyResult<T> extends StreamResult<T> {
  /// Marks a completed operation that had nothing to hand back.
  const StreamEmptyResult();

  @override
  String toString() => 'StreamEmptyResult<$T>()';
}

/// Convenient constructors for [StreamResult].
abstract final class StreamResults {
  /// Builds the loading state, optionally labelled by [message].
  static StreamLoadingResult<T> loading<T>({String? message}) {
    return StreamLoadingResult<T>(message: message);
  }

  /// Builds the success state carrying [data].
  static StreamSuccess<T> success<T>(T data) {
    return StreamSuccess<T>(data);
  }

  /// Builds the error state for [error] with its optional [stackTrace] and a
  /// displayable [message].
  static StreamErrorResult<T> error<T>(Object error, {StackTrace? stackTrace, String? message}) {
    return StreamErrorResult<T>(error, stackTrace: stackTrace, message: message);
  }

  /// Builds the empty state: the operation finished without a value.
  static StreamEmptyResult<T> empty<T>() {
    return StreamEmptyResult<T>();
  }
}
