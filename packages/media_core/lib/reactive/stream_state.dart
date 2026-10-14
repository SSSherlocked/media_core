import 'dart:async';
import 'package:rxdart/rxdart.dart';

/// A small reactive state holder based on [BehaviorSubject].
///
/// Suitable for state such as:
/// - isPlaying
/// - isBuffering
/// - hasError
/// - currentQuality
/// - selectedSource
/// - volume
/// - player state
///
/// Example:
/// ```dart
/// final isPlaying = StreamState<bool>(false);
///
/// isPlaying.stream.listen((value) {
///   print('playing: $value');
/// });
///
/// isPlaying.value = true;
/// isPlaying.update((current) => !current);
///
/// await isPlaying.close();
/// ```
class StreamState<T> {
  /// Seeds the state with [initialValue] so subscribers read `.value` or join
  /// the stream and immediately get a value instead of waiting for a change.
  StreamState(T initialValue) : _subject = BehaviorSubject<T>.seeded(initialValue);

  final BehaviorSubject<T> _subject;

  /// Current state value.
  T get value => _subject.value;

  /// Whether the state currently has a value.
  bool get hasValue => _subject.hasValue;

  /// Whether the underlying subject has been closed.
  bool get isClosed => _subject.isClosed;

  /// Reactive state stream.
  Stream<T> get stream => _subject.stream;

  /// Set a new state value.
  ///
  /// Writing is ignored once the state is closed, matching [add].
  set value(T newValue) {
    add(newValue);
  }

  /// Publish [newValue] unless the underlying subject is already closed.
  ///
  /// This is where the closed-state guard lives; the [value] setter forwards
  /// here so both entry points behave the same.
  void add(T newValue) {
    if (_subject.isClosed) {
      return;
    }

    _subject.add(newValue);
  }

  /// Update the current state using [updater].
  void update(T Function(T current) updater) {
    if (_subject.isClosed) {
      return;
    }

    _subject.add(updater(_subject.value));
  }

  /// Add an error to the state stream.
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_subject.isClosed) {
      return;
    }

    _subject.addError(error, stackTrace);
  }

  /// Listen to state changes.
  StreamSubscription<T> listen(
    void Function(T value)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _subject.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  /// Close the state.
  Future<void> close() {
    return _subject.close();
  }

  /// Alias for [close].
  Future<void> dispose() {
    return close();
  }
}

/// A nullable version of [StreamState].
///
/// Useful when the initial state is intentionally `null`.
///
/// Example:
/// ```dart
/// final currentUrl = NullableStreamState<String>();
///
/// currentUrl.value = 'https://example.com/live.flv';
/// currentUrl.value = null;
/// ```
class NullableStreamState<T> extends StreamState<T?> {
  /// Starts from [initialValue], or `null` when no seed is supplied.
  NullableStreamState([super.initialValue]);
}
