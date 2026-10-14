import 'dart:async';
import 'package:rxdart/rxdart.dart';

/// Manages StreamSubscriptions and timers and provides lifecycle-safe
/// asynchronous helpers.
///
/// Intended to be used by controllers, managers, adapters, and other
/// classes that own multiple stream subscriptions.
///
/// Example:
///
/// ```dart
/// final streams = StreamControllerManager();
///
/// streams.listen(
///   player.stream.playing,
///   (playing) {
///     // Handle state change.
///   },
/// );
///
/// await streams.dispose();
/// ```
class StreamControllerManager {
  /// Creates a manager; [onDispose] runs last, after every subscription and
  /// timer this manager owns has already been cancelled.
  StreamControllerManager({this.onDispose});

  /// Optional callback invoked after all subscriptions and timers have been
  /// cancelled.
  final FutureOr<void> Function()? onDispose;

  final CompositeSubscription _subscriptions = CompositeSubscription();

  final Set<Timer> _timers = <Timer>{};

  bool _disposed = false;

  /// Whether this manager has already been disposed.
  bool get isDisposed => _disposed;

  /// Whether this manager is still active.
  bool get isAlive => !_disposed;

  /// Adds an existing subscription to this manager.
  ///
  /// If the manager has already been disposed, the subscription is cancelled
  /// immediately.
  StreamSubscription<T> add<T>(StreamSubscription<T> subscription) {
    if (_disposed) {
      unawaited(subscription.cancel());
      return subscription;
    }

    _subscriptions.add(subscription);
    return subscription;
  }

  /// Subscribes to [stream] and automatically manages the subscription.
  ///
  /// [onError] receives the error together with its stack trace, matching the
  /// two-argument form accepted by `Stream.listen`.
  StreamSubscription<T> listen<T>(
    Stream<T> stream,
    void Function(T event) onData, {
    void Function(Object error, StackTrace stackTrace)? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_disposed) {
      return _DisposedStreamSubscription<T>();
    }

    final subscription = stream.listen(
      (event) {
        if (_disposed) {
          return;
        }

        onData(event);
      },
      onError: onError == null ? null : _guardOnError(onError),
      onDone: onDone == null
          ? null
          : () {
              if (_disposed) {
                return;
              }

              onDone();
            },
      cancelOnError: cancelOnError,
    );

    return add(subscription);
  }

  /// Subscribes to [stream] with an asynchronous callback.
  ///
  /// The next event may arrive before the previous callback completes.
  /// If sequential processing is required, use an async stream operator
  /// instead.
  ///
  /// [onError] receives the error together with its stack trace, matching the
  /// two-argument form accepted by `Stream.listen`.
  StreamSubscription<T> listenAsync<T>(
    Stream<T> stream,
    FutureOr<void> Function(T event) onData, {
    void Function(Object error, StackTrace stackTrace)? onError,
    FutureOr<void> Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_disposed) {
      return _DisposedStreamSubscription<T>();
    }

    final subscription = stream.listen(
      (event) async {
        if (_disposed) {
          return;
        }

        await onData(event);
      },
      onError: onError == null ? null : _guardOnError(onError),
      onDone: onDone == null
          ? null
          : () async {
              if (_disposed) {
                return;
              }

              await onDone();
            },
      cancelOnError: cancelOnError,
    );

    return add(subscription);
  }

  /// Wraps [handler] so errors delivered after [dispose] are dropped.
  ///
  /// `Stream.listen` declares its `onError` as an untyped `Function?`, so a
  /// handler written inline there would have `dynamic` parameters; returning a
  /// closure from this typed helper is what gives them their types and keeps
  /// the forwarding call static.
  void Function(Object, StackTrace) _guardOnError(void Function(Object, StackTrace) handler) {
    return (error, stackTrace) {
      if (_disposed) {
        return;
      }

      handler(error, stackTrace);
    };
  }

  /// Cancels all currently registered subscriptions.
  ///
  /// The manager itself remains alive and can accept new subscriptions.
  Future<void> cancelSubscriptions() async {
    if (_disposed) {
      return;
    }

    await _subscriptions.cancel();
  }

  /// Cancels all managed timers.
  void cancelTimers() {
    if (_timers.isEmpty) {
      return;
    }

    for (final timer in _timers) {
      timer.cancel();
    }

    _timers.clear();
  }

  /// Creates a periodic timer managed by this controller.
  ///
  /// The timer is automatically cancelled when [dispose] is called.
  Timer periodic(Duration duration, void Function(Timer timer) callback) {
    if (_disposed) {
      throw StateError(
        'Cannot create a timer after '
        'StreamControllerManager.dispose().',
      );
    }

    late final Timer timer;

    timer = Timer.periodic(duration, (timer) {
      if (_disposed) {
        timer.cancel();
        _timers.remove(timer);
        return;
      }

      callback(timer);
    });

    _timers.add(timer);

    return timer;
  }

  /// Creates a one-shot timer managed by this controller.
  ///
  /// The timer is automatically removed from the internal timer set after
  /// firing and cancelled automatically when [dispose] is called.
  Timer delayed(Duration duration, void Function() callback) {
    if (_disposed) {
      throw StateError(
        'Cannot create a timer after '
        'StreamControllerManager.dispose().',
      );
    }

    late final Timer timer;

    timer = Timer(duration, () {
      _timers.remove(timer);

      if (_disposed) {
        return;
      }

      callback();
    });

    _timers.add(timer);

    return timer;
  }

  /// Runs [callback] only when this manager is still alive.
  void runIfAlive(void Function() callback) {
    if (_disposed) {
      return;
    }

    callback();
  }

  /// Runs an asynchronous callback only when this manager is still alive.
  Future<void> runIfAliveAsync(FutureOr<void> Function() callback) async {
    if (_disposed) {
      return;
    }

    await callback();
  }

  /// Executes [callback] with [value] only when this manager is alive.
  void runWithValue<T>(T value, void Function(T value) callback) {
    if (_disposed) {
      return;
    }

    callback(value);
  }

  /// Executes an asynchronous callback with [value] only when this manager
  /// is alive.
  Future<void> runWithValueAsync<T>(T value, FutureOr<void> Function(T value) callback) async {
    if (_disposed) {
      return;
    }

    await callback(value);
  }

  /// Disposes this manager.
  ///
  /// Disposal is idempotent.
  ///
  /// All managed timers and stream subscriptions are cancelled before
  /// [onDispose] is invoked.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    cancelTimers();

    await _subscriptions.cancel();

    await onDispose?.call();
  }
}

/// A no-op [StreamSubscription] returned when a listener is registered after
/// the manager has already been disposed.
class _DisposedStreamSubscription<T> implements StreamSubscription<T> {
  const _DisposedStreamSubscription();

  @override
  Future<void> cancel() async {}

  @override
  void onData(void Function(T data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  bool get isPaused => false;

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    return Future<E>.value(futureValue);
  }
}
