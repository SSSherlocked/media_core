import 'dart:async';

/// Stream related utilities.
abstract final class StreamUtils {
  StreamUtils._();

  /// Creates a stream from a single value.
  static Stream<T> value<T>(T value) {
    return Stream<T>.value(value);
  }

  /// Creates an empty stream.
  static Stream<T> empty<T>() {
    return const Stream.empty();
  }

  /// Creates a stream that emits [values].
  static Stream<T> fromIterable<T>(Iterable<T> values) {
    return Stream<T>.fromIterable(values);
  }

  /// Converts future into stream.
  static Stream<T> fromFuture<T>(Future<T> future) {
    return Stream<T>.fromFuture(future);
  }

  /// Safely listens to a stream.
  static StreamSubscription<T> listen<T>(
    Stream<T> stream,
    void Function(T value) onData, {
    void Function(Object error, StackTrace stackTrace)? onError,
    void Function()? onDone,
    bool cancelOnError = false,
  }) {
    return stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  /// Converts a stream error into a value.
  static Stream<T> recover<T>(Stream<T> stream, T Function(Object error, StackTrace stackTrace) fallback) {
    return stream
        .handleError((Object error, StackTrace stackTrace) {})
        .transform(
          StreamTransformer<T, T>.fromHandlers(
            handleError: (error, stackTrace, sink) {
              sink.add(fallback(error, stackTrace));
            },
          ),
        );
  }

  /// Ignores stream errors.
  static Stream<T> ignoreErrors<T>(Stream<T> stream) {
    return stream.transform(StreamTransformer<T, T>.fromHandlers(handleError: (_, _, _) {}));
  }

  /// Converts stream into broadcast stream.
  static Stream<T> asBroadcast<T>(Stream<T> stream) {
    if (stream.isBroadcast) {
      return stream;
    }

    return stream.asBroadcastStream();
  }

  /// Returns first item or null.
  static Future<T?> firstOrNull<T>(Stream<T> stream) async {
    try {
      return await stream.first;
    } on Object catch (_) {
      return null;
    }
  }

  /// Returns last item or null.
  static Future<T?> lastOrNull<T>(Stream<T> stream) async {
    try {
      return await stream.last;
    } on Object catch (_) {
      return null;
    }
  }

  /// Collects stream values into list.
  static Future<List<T>> toList<T>(Stream<T> stream) {
    return stream.toList();
  }

  /// Counts stream events.
  static Future<int> count<T>(Stream<T> stream) async {
    var count = 0;

    await for (final _ in stream) {
      count++;
    }

    return count;
  }

  /// Waits until stream emits [value].
  static Future<T> waitFor<T>(Stream<T> stream, bool Function(T value) predicate) async {
    await for (final value in stream) {
      if (predicate(value)) {
        return value;
      }
    }

    throw StateError('Stream completed before matching value');
  }

  /// Debounces stream events.
  static Stream<T> debounce<T>(Stream<T> stream, Duration duration) {
    late StreamController<T> controller;

    Timer? timer;
    T? latest;
    var hasValue = false;

    controller = StreamController<T>(
      onListen: () {
        stream.listen(
          (value) {
            latest = value;
            hasValue = true;

            timer?.cancel();

            timer = Timer(duration, () {
              if (hasValue) {
                controller.add(latest as T);
                hasValue = false;
              }
            });
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            // Nothing awaits the close here: the `onDone` callback is `void`,
            // and downstream subscribers observe completion via the returned
            // controller stream itself.
            unawaited(controller.close());
          },
        );
      },
    );

    return controller.stream;
  }

  /// Distinct stream values.
  static Stream<T> distinct<T>(Stream<T> stream) {
    return stream.distinct();
  }

  /// Maps nullable stream values and removes nulls.
  static Stream<T> whereNotNull<T>(Stream<T?> stream) {
    return stream.where((value) => value != null).cast<T>();
  }

  /// Cancels subscription safely.
  static Future<void> cancel(StreamSubscription<dynamic>? subscription) async {
    await subscription?.cancel();
  }

  /// Converts stream into future completion.
  static Future<void> drain<T>(Stream<T> stream) async {
    await stream.drain<void>();
  }

  /// Returns whether stream emits any value.
  static Future<bool> hasValue<T>(Stream<T> stream) async {
    await for (final _ in stream) {
      return true;
    }

    return false;
  }
}
