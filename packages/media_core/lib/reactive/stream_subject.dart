import 'dart:async';
import 'package:rxdart/rxdart.dart';

/// Factory helpers for commonly used RxDart subjects.
///
/// All APIs are compatible with RxDart 0.28.0.
abstract final class StreamSubject {
  /// Create a BehaviorSubject with an initial value.
  ///
  /// BehaviorSubject always exposes the latest value to new listeners.
  static BehaviorSubject<T> behavior<T>(T initialValue) {
    return BehaviorSubject<T>.seeded(initialValue);
  }

  /// Create an empty BehaviorSubject.
  ///
  /// The subject does not have a value until [add] is called.
  static BehaviorSubject<T> behaviorEmpty<T>() {
    return BehaviorSubject<T>();
  }

  /// Create a PublishSubject.
  ///
  /// Values are only delivered to current listeners.
  static PublishSubject<T> publish<T>() {
    return PublishSubject<T>();
  }

  /// Create a ReplaySubject.
  ///
  /// [maxSize] controls how many recent values are replayed.
  static ReplaySubject<T> replay<T>({int? maxSize}) {
    if (maxSize != null && maxSize < 1) {
      throw ArgumentError.value(maxSize, 'maxSize', 'maxSize must be greater than 0.');
    }

    return ReplaySubject<T>(maxSize: maxSize);
  }

  /// Create a replay subject that keeps only the latest value.
  static ReplaySubject<T> replayLatest<T>() {
    return ReplaySubject<T>(maxSize: 1);
  }

  /// Close a subject safely.
  ///
  /// Calling this method with an already closed subject is harmless.
  static Future<void> close<T>(Subject<T> subject) async {
    if (subject.isClosed) {
      return;
    }

    await subject.close();
  }

  /// Add a value if the subject is still alive.
  static void add<T>(Subject<T> subject, T value) {
    if (subject.isClosed) {
      return;
    }

    subject.add(value);
  }

  /// Add an error if the subject is still alive.
  static void addError<T>(Subject<T> subject, Object error, [StackTrace? stackTrace]) {
    if (subject.isClosed) {
      return;
    }

    subject.addError(error, stackTrace);
  }
}

/// A lifecycle-safe wrapper around [BehaviorSubject].
///
/// Useful when a class owns several reactive states and wants a consistent
/// API for updating and disposing them.
///
/// Example:
/// ```dart
/// final state = ManagedBehaviorSubject<bool>.seeded(false);
///
/// state.add(true);
///
/// final subscription = state.stream.listen(print);
///
/// await state.close();
/// ```
class ManagedBehaviorSubject<T> {
  /// Creates a subject with no value yet; reading [value] before the first
  /// [add] throws, so use [ManagedBehaviorSubject.seeded] when a default is
  /// required.
  ManagedBehaviorSubject() : _subject = BehaviorSubject<T>();

  /// Creates a subject that already exposes [initialValue] to new subscribers.
  ManagedBehaviorSubject.seeded(T initialValue) : _subject = BehaviorSubject<T>.seeded(initialValue);

  final BehaviorSubject<T> _subject;

  /// Underlying subject.
  BehaviorSubject<T> get subject => _subject;

  /// Stream exposed to consumers.
  Stream<T> get stream => _subject.stream;

  /// Current value.
  ///
  /// Throws if the subject has never received a value and was created
  /// without an initial value.
  T get value => _subject.value;

  /// Whether the subject currently has a value.
  bool get hasValue => _subject.hasValue;

  /// Whether the subject has been closed.
  bool get isClosed => _subject.isClosed;

  /// Add a value when the subject is alive.
  void add(T value) {
    if (_subject.isClosed) {
      return;
    }

    _subject.add(value);
  }

  /// Add an error when the subject is alive.
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_subject.isClosed) {
      return;
    }

    _subject.addError(error, stackTrace);
  }

  /// Listen to the subject.
  StreamSubscription<T> listen(
    void Function(T value)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _subject.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  /// Close the subject.
  Future<void> close() async {
    if (_subject.isClosed) {
      return;
    }

    await _subject.close();
  }

  /// Alias for [close].
  Future<void> dispose() {
    return close();
  }
}
