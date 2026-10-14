import 'dart:async';
import 'package:rxdart/rxdart.dart';

/// Common stream transformation helpers used by PureLive.
///
/// Keep lifecycle management in `stream_controller.dart` and simple
/// extensions in `stream_extensions.dart`.
abstract final class StreamTransform {
  StreamTransform._();

  /// Combines two streams and emits the latest values whenever either
  /// source changes.
  static Stream<R> combineLatest2<A, B, R>(Stream<A> first, Stream<B> second, R Function(A a, B b) combiner) {
    return CombineLatestStream.combine2(first, second, combiner);
  }

  /// Combines three streams.
  static Stream<R> combineLatest3<A, B, C, R>(
    Stream<A> first,
    Stream<B> second,
    Stream<C> third,
    R Function(A a, B b, C c) combiner,
  ) {
    return CombineLatestStream.combine3(first, second, third, combiner);
  }

  /// Combines four streams.
  static Stream<R> combineLatest4<A, B, C, D, R>(
    Stream<A> first,
    Stream<B> second,
    Stream<C> third,
    Stream<D> fourth,
    R Function(A a, B b, C c, D d) combiner,
  ) {
    return CombineLatestStream.combine4(first, second, third, fourth, combiner);
  }

  /// Combines an arbitrary number of streams.
  ///
  /// The resulting list follows the same order as [streams].
  static Stream<List<dynamic>> combineLatest(Iterable<Stream<dynamic>> streams) {
    return CombineLatestStream.list(streams);
  }

  /// Emits only values different from the previous value.
  static Stream<T> distinct<T>(Stream<T> source, {bool Function(T previous, T next)? equals}) {
    if (equals == null) {
      return source.distinct();
    }

    return source.distinctUnique(equals: equals);
  }

  /// Debounces [source].
  static Stream<T> debounce<T>(Stream<T> source, Duration duration) {
    return source.debounceTime(duration);
  }

  /// Throttles [source].
  static Stream<T> throttle<T>(Stream<T> source, Duration duration, {bool leading = true, bool trailing = false}) {
    return source.throttleTime(duration, leading: leading, trailing: trailing);
  }

  /// Emits only the first value during each throttle window.
  static Stream<T> throttleFirst<T>(Stream<T> source, Duration duration) {
    return source.throttleTime(duration, leading: true, trailing: false);
  }

  /// Emits the first value immediately and the latest value at the end of
  /// each throttle window.
  static Stream<T> throttleLatest<T>(Stream<T> source, Duration duration) {
    return source.throttleTime(duration, leading: true, trailing: true);
  }

  /// Maps every event to a stream and subscribes only to the latest stream.
  ///
  /// Useful for switching between live sources.
  static Stream<R> switchMap<T, R>(Stream<T> source, Stream<R> Function(T value) mapper) {
    return source.switchMap(mapper);
  }

  /// Maps every event to a stream and merges all mapped streams.
  static Stream<R> flatMap<T, R>(Stream<T> source, Stream<R> Function(T value) mapper) {
    return source.flatMap(mapper);
  }

  /// Maps every event asynchronously.
  static Stream<R> asyncMap<T, R>(Stream<T> source, FutureOr<R> Function(T value) mapper) {
    return source.asyncMap(mapper);
  }

  /// Maps each event to a stream sequentially.
  ///
  /// The next mapped stream starts after the previous stream completes.
  static Stream<R> concatMap<T, R>(Stream<T> source, Stream<R> Function(T value) mapper) {
    return source.asyncExpand(mapper);
  }

  /// Removes null values.
  static Stream<T> whereNotNull<T>(Stream<T?> source) {
    return source.where((value) => value != null).cast<T>();
  }

  /// Delays events.
  static Stream<T> delay<T>(Stream<T> source, Duration duration) {
    return source.delay(duration);
  }

  /// Prepends [value].
  static Stream<T> startWith<T>(Stream<T> source, T value) {
    return source.startWith(value);
  }

  /// Emits a fallback value if the source produces an error.
  static Stream<T> onErrorReturn<T>(Stream<T> source, T fallback) {
    return source.onErrorReturn(fallback);
  }

  /// Replaces an error with another stream.
  static Stream<T> onErrorResume<T>(Stream<T> source, Stream<T> Function(Object error, StackTrace stackTrace) resume) {
    return source.onErrorResume(resume);
  }

  /// Ignores errors and completes the stream.
  static Stream<T> ignoreErrors<T>(Stream<T> source) {
    return source.onErrorResume((error, stackTrace) {
      return Stream<T>.empty();
    });
  }

  /// Converts a single-subscription stream into a broadcast stream.
  static Stream<T> broadcast<T>(Stream<T> source) {
    if (source.isBroadcast) {
      return source;
    }

    return source.asBroadcastStream();
  }

  /// Creates a stream that emits [value] after [duration].
  static Stream<T> delayedValue<T>(T value, Duration duration) {
    return Rx.timer(value, duration);
  }

  /// Creates a periodic integer stream.
  ///
  /// The first value is `0`.
  static Stream<int> interval(Duration duration) {
    return Stream<int>.periodic(duration, (index) => index);
  }

  /// Samples this stream whenever [trigger] emits.
  static Stream<T> sampleOn<T>(Stream<T> source, Stream<dynamic> trigger) {
    return source.sample(trigger);
  }

  /// Samples the latest value periodically.
  static Stream<T> sampleTime<T>(Stream<T> source, Duration duration) {
    return source.sampleTime(duration);
  }

  /// Merges multiple streams.
  static Stream<T> merge<T>(Iterable<Stream<T>> streams) {
    return MergeStream<T>(streams);
  }

  /// Concatenates multiple streams.
  ///
  /// Each stream starts after the previous stream completes.
  static Stream<T> concat<T>(Iterable<Stream<T>> streams) {
    return ConcatStream<T>(streams);
  }

  /// Filters values using [condition].
  static Stream<T> whereCondition<T>(Stream<T> source, bool Function(T value) condition) {
    return source.where(condition);
  }

  /// Takes values while [condition] is true.
  static Stream<T> takeWhile<T>(Stream<T> source, bool Function(T value) condition) {
    return source.takeWhile(condition);
  }

  /// Takes values until [stopper] emits.
  static Stream<T> takeUntil<T>(Stream<T> source, Stream<dynamic> stopper) {
    return source.takeUntil(stopper);
  }

  /// Skips values until [trigger] emits.
  static Stream<T> skipUntil<T>(Stream<T> source, Stream<dynamic> trigger) {
    return source.skipUntil(trigger);
  }
}
