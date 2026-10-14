import 'dart:async';
import 'package:rxdart/rxdart.dart';

/// Provides the public entry point for the reactive infrastructure used by
/// `media_core`.
///
/// This class contains shared reactive types and lightweight factory helpers.
/// RxDart remains the underlying reactive implementation rather than being
/// replaced by a custom observable system.
abstract final class Reactive {
  /// Creates a broadcast controller that supports multiple listeners.
  ///
  /// The controller is suitable for player events and other application-wide
  /// reactive signals where multiple consumers may subscribe independently.
  static StreamController<T> broadcastController<T>({
    bool sync = false,
    void Function()? onListen,
    void Function()? onCancel,
  }) {
    return StreamController<T>.broadcast(sync: sync, onListen: onListen, onCancel: onCancel);
  }

  /// Creates a single-subscription stream controller.
  ///
  /// Use this when a stream represents one asynchronous workflow and should
  /// not be consumed by multiple independent listeners.
  static StreamController<T> controller<T>({
    bool sync = false,
    void Function()? onListen,
    void Function()? onPause,
    void Function()? onResume,
    FutureOr<void> Function()? onCancel,
  }) {
    return StreamController<T>(
      sync: sync,
      onListen: onListen,
      onPause: onPause,
      onResume: onResume,
      onCancel: onCancel,
    );
  }

  /// Creates a [PublishSubject].
  ///
  /// A publish subject forwards newly emitted events to current subscribers
  /// and does not replay previous events to later subscribers.
  static PublishSubject<T> publishSubject<T>() {
    return PublishSubject<T>();
  }

  /// Creates a [BehaviorSubject] with [seed].
  ///
  /// A behavior subject stores the latest value and immediately exposes it to
  /// new subscribers.
  static BehaviorSubject<T> behaviorSubject<T>({required T seed}) {
    return BehaviorSubject<T>.seeded(seed);
  }

  /// Creates a [ReplaySubject].
  ///
  /// When [maxSize] is provided, at most that many recent events are retained.
  static ReplaySubject<T> replaySubject<T>({int? maxSize}) {
    return ReplaySubject<T>(maxSize: maxSize);
  }

  /// Converts a [Stream] into a broadcast stream.
  ///
  /// This is useful when a source stream must be consumed by multiple
  /// independent components.
  static Stream<T> asBroadcast<T>(Stream<T> stream) {
    return stream.isBroadcast ? stream : stream.asBroadcastStream();
  }

  /// Returns a stream that emits only when the source value changes.
  ///
  /// Equality is determined by [equals] when supplied; otherwise the default
  /// equality operator is used by RxDart.
  static Stream<T> distinct<T>(Stream<T> stream, {bool Function(T previous, T next)? equals}) {
    if (equals == null) {
      return stream.distinct();
    }

    return stream.distinct((previous, next) => equals(previous, next));
  }

  /// Returns a stream that waits for a quiet period before forwarding values.
  ///
  /// This is commonly used for high-frequency UI or player signals where
  /// intermediate values do not need to be processed immediately.
  static Stream<T> debounce<T>(Stream<T> stream, Duration duration) {
    return stream.debounceTime(duration);
  }

  /// Returns a stream that limits the frequency of emitted values.
  ///
  /// Unlike debouncing, throttling can allow values through while the source
  /// continues producing events.
  static Stream<T> throttle<T>(Stream<T> stream, Duration duration) {
    return stream.throttleTime(duration, trailing: true);
  }

  /// Combines the latest values from multiple streams.
  ///
  /// The resulting stream emits whenever one of the input streams emits after
  /// all required input streams have produced at least one value.
  static Stream<List<T>> combineLatest<T>(Iterable<Stream<T>> streams) {
    return Rx.combineLatestList<T>(streams);
  }

  /// Merges multiple streams into a single stream.
  ///
  /// Events are forwarded in the order they arrive.
  static Stream<T> merge<T>(Iterable<Stream<T>> streams) {
    return Rx.merge<T>(streams);
  }

  /// Concatenates streams sequentially.
  ///
  /// The next stream starts only after the previous stream completes.
  static Stream<T> concat<T>(Iterable<Stream<T>> streams) {
    return Rx.concat<T>(streams);
  }

  /// Creates a stream that emits [value] once.
  static Stream<T> value<T>(T value) {
    return Stream<T>.value(value);
  }

  /// Creates a stream that emits no values and completes immediately.
  static Stream<T> empty<T>() {
    return Stream<T>.empty();
  }

  /// Creates a stream that emits [values] synchronously in sequence.
  static Stream<T> fromIterable<T>(Iterable<T> values) {
    return Stream<T>.fromIterable(values);
  }

  /// Returns whether [stream] is already a broadcast stream.
  static bool isBroadcast<T>(Stream<T> stream) {
    return stream.isBroadcast;
  }

  /// Returns a broadcast view of [stream].
  ///
  /// The source stream itself is not replaced; this method only exposes a
  /// broadcast-compatible view to consumers.
  static Stream<T> broadcast<T>(Stream<T> stream) {
    return asBroadcast(stream);
  }
}

/// Type alias for a reactive stream.
typedef ReactiveStream<T> = Stream<T>;

/// Type alias for a stream subscription.
typedef ReactiveSubscription<T> = StreamSubscription<T>;

/// Type alias for a replay subject.
typedef ReactiveReplay<T> = ReplaySubject<T>;

/// Type alias for a reactive value notifier.
///
/// This is intentionally kept as a simple stream-based abstraction. The
/// reactive module does not introduce a second state-management framework.
typedef ReactiveValue<T> = BehaviorSubject<T>;
