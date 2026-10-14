import 'dart:async';
import 'package:rxdart/rxdart.dart';

/// Common stream extensions used throughout PureLive.
///
/// These extensions keep RxDart-specific operators in one place so the rest
/// of the project can work with a small and consistent stream API.
extension PureLiveStreamExtensions<T> on Stream<T> {
  /// Debounces events.
  ///
  /// Only the latest event is emitted after the source has been quiet for
  /// [duration].
  Stream<T> debounce(Duration duration) {
    return debounceTime(duration);
  }

  /// Throttles events.
  ///
  /// By default, the first event in each window is emitted.
  ///
  /// Set [trailing] to true if the latest event in the window should also
  /// be emitted.
  Stream<T> throttle(Duration duration, {bool trailing = false}) {
    return throttleTime(duration, leading: true, trailing: trailing);
  }

  /// Emits only the first event during each [duration] window.
  Stream<T> throttleFirst(Duration duration) {
    return throttleTime(duration, leading: true, trailing: false);
  }

  /// Emits the first event immediately and the latest event at the end of
  /// each throttle window.
  Stream<T> throttleLatest(Duration duration) {
    return throttleTime(duration, leading: true, trailing: true);
  }

  /// Samples this stream whenever [sampler] emits.
  Stream<T> sampleOn(Stream<dynamic> sampler) {
    return sample(sampler);
  }

  /// Samples the latest value periodically.
  Stream<T> sampleEvery(Duration duration) {
    return sampleTime(duration);
  }

  /// Removes consecutive duplicate values.
  Stream<T> distinctValues({bool Function(T previous, T next)? equals}) {
    if (equals == null) {
      return distinct();
    }

    return distinctUnique(equals: equals);
  }

  /// Maps each event to a stream and merges the resulting streams.
  Stream<R> flatMapAsync<R>(Stream<R> Function(T value) mapper) {
    return flatMap(mapper);
  }

  /// Maps each event to a stream sequentially.
  ///
  /// The next mapped stream is not subscribed to until the previous one
  /// completes.
  Stream<R> concatMapAsync<R>(Stream<R> Function(T value) mapper) {
    return asyncExpand(mapper);
  }

  /// Converts this stream to a broadcast stream.
  ///
  /// If the source is already a broadcast stream, it is returned unchanged.
  Stream<T> broadcastStream() {
    if (isBroadcast) {
      return this;
    }

    return asBroadcastStream();
  }

  /// Emits [fallback] when an error occurs.
  Stream<T> onErrorReturnValue(T fallback) {
    return onErrorResume((error, stackTrace) {
      return Stream<T>.value(fallback);
    });
  }

  /// Emits a value generated from the error.
  Stream<T> onErrorReturnWithValue(T Function(Object error) mapper) {
    return onErrorResume((error, stackTrace) {
      return Stream<T>.value(mapper(error));
    });
  }

  /// Ignores errors from this stream.
  Stream<T> ignoreErrors() {
    return onErrorResume((error, stackTrace) {
      return Stream<T>.empty();
    });
  }

  /// Delays every event by [duration].
  Stream<T> delayEvents(Duration duration) {
    return delay(duration);
  }

  /// Buffers events until [boundary] emits.
  Stream<List<T>> bufferUntil(Stream<dynamic> boundary) {
    return buffer(boundary);
  }

  /// Prepends [value] to this stream.
  Stream<T> startWithValue(T value) {
    return startWith(value);
  }

  /// Alias for [debounce].
  ///
  /// Useful when the semantic meaning is "wait until the value settles".
  Stream<T> settle(Duration duration) {
    return debounceTime(duration);
  }

  /// Converts this stream into a [BehaviorSubject].
  ///
  /// The returned subject owns the subscription to this stream.
  ///
  /// The caller is responsible for closing the returned subject.
  BehaviorSubject<T> toBehaviorSubject() {
    final subject = BehaviorSubject<T>();

    // addStream returns the subject's done future, which only completes once
    // the caller closes the subject, so nothing here may await it.
    unawaited(subject.addStream(this));

    return subject;
  }

  /// Converts this stream into a [ReplaySubject].
  ///
  /// By default only the latest value is retained.
  ///
  /// The caller is responsible for closing the returned subject.
  ReplaySubject<T> toReplaySubject({int maxSize = 1}) {
    if (maxSize < 1) {
      throw ArgumentError.value(maxSize, 'maxSize', 'must be greater than or equal to 1');
    }

    final subject = ReplaySubject<T>(maxSize: maxSize);

    // Same as toBehaviorSubject: the done future only completes when the
    // caller closes the subject and must not be awaited here.
    unawaited(subject.addStream(this));

    return subject;
  }
}

/// Extensions for nullable stream values.
extension PureLiveNullableStreamExtensions<T> on Stream<T?> {
  /// Filters null values from the stream.
  Stream<T> whereNotNull() {
    return where((value) => value != null).cast<T>();
  }
}

/// Extensions for asynchronous stream operations.
extension PureLiveAsyncStreamExtensions<T> on Stream<T> {
  /// Executes [callback] for each event and then emits the original value.
  ///
  /// Useful when an asynchronous side effect must complete before the event
  /// continues downstream.
  Stream<T> tapAsync(FutureOr<void> Function(T value) callback) {
    return asyncMap((value) async {
      await callback(value);
      return value;
    });
  }

  /// Maps each event asynchronously.
  Stream<R> mapAsync<R>(FutureOr<R> Function(T value) mapper) {
    return asyncMap(mapper);
  }
}
