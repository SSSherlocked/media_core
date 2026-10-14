import 'dart:async';
import 'package:rxdart/rxdart.dart';

/// A small lifecycle manager for disposable asynchronous resources.
///
/// It can manage:
/// - StreamSubscription
/// - Timer
/// - StreamSink
/// - RxDart Subject
/// - arbitrary async cleanup callbacks
///
/// Example:
/// ```dart
/// final disposable = StreamDisposable();
///
/// disposable.addSubscription(
///   stream.listen(...),
/// );
///
/// disposable.addTimer(
///   Timer.periodic(...),
/// );
///
/// await disposable.dispose();
/// ```
class StreamDisposable {
  final List<StreamSubscription<dynamic>> _subscriptions = <StreamSubscription<dynamic>>[];

  final List<Timer> _timers = <Timer>[];

  final List<StreamSink<dynamic>> _sinks = <StreamSink<dynamic>>[];

  final List<Subject<dynamic>> _subjects = <Subject<dynamic>>[];

  final List<FutureOr<void> Function()> _cleanups = <FutureOr<void> Function()>[];

  bool _disposed = false;

  /// Whether this manager has been disposed.
  bool get isDisposed => _disposed;

  /// Whether this manager is still active.
  bool get isAlive => !_disposed;

  /// Number of registered subscriptions.
  int get subscriptionCount => _subscriptions.length;

  /// Number of registered timers.
  int get timerCount => _timers.length;

  /// Register a stream subscription.
  ///
  /// The subscription is automatically cancelled during [dispose].
  StreamSubscription<T> addSubscription<T>(StreamSubscription<T> subscription) {
    if (_disposed) {
      unawaited(subscription.cancel());
      return subscription;
    }

    _subscriptions.add(subscription);

    return subscription;
  }

  /// Listen to [stream] and automatically manage its subscription.
  StreamSubscription<T> listen<T>(
    Stream<T> stream,
    void Function(T value)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

    return addSubscription(subscription);
  }

  /// Register a timer.
  Timer addTimer(Timer timer) {
    if (_disposed) {
      timer.cancel();
      return timer;
    }

    _timers.add(timer);

    return timer;
  }

  /// Create and register a one-shot timer.
  Timer timer(Duration duration, void Function() callback) {
    late final Timer timer;

    timer = Timer(duration, () {
      _timers.remove(timer);

      if (_disposed) {
        return;
      }

      callback();
    });

    return addTimer(timer);
  }

  /// Create and register a periodic timer.
  Timer periodic(Duration duration, void Function(Timer timer) callback) {
    final timer = Timer.periodic(duration, (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }

      callback(timer);
    });

    return addTimer(timer);
  }

  /// Register a StreamSink.
  StreamSink<T> addSink<T>(StreamSink<T> sink) {
    if (_disposed) {
      unawaited(sink.close());
      return sink;
    }

    _sinks.add(sink);

    return sink;
  }

  /// Register an RxDart Subject.
  Subject<T> addSubject<T>(Subject<T> subject) {
    if (_disposed) {
      unawaited(subject.close());
      return subject;
    }

    _subjects.add(subject);

    return subject;
  }

  /// Register a custom cleanup callback.
  ///
  /// Both synchronous and asynchronous callbacks are supported.
  void addCleanup(FutureOr<void> Function() cleanup) {
    if (_disposed) {
      final result = cleanup();

      if (result is Future<void>) {
        unawaited(result);
      }

      return;
    }

    _cleanups.add(cleanup);
  }

  /// Remove and cancel a specific subscription.
  Future<void> removeSubscription(StreamSubscription<dynamic> subscription) async {
    _subscriptions.remove(subscription);
    await subscription.cancel();
  }

  /// Cancel all managed subscriptions.
  Future<void> cancelSubscriptions() async {
    final subscriptions = List<StreamSubscription<dynamic>>.from(_subscriptions);

    _subscriptions.clear();

    for (final subscription in subscriptions) {
      try {
        await subscription.cancel();
      } on Object catch (_) {
        // Cleanup should continue even when one subscription fails.
      }
    }
  }

  /// Cancel all managed timers.
  void cancelTimers() {
    final timers = List<Timer>.from(_timers);

    _timers.clear();

    for (final timer in timers) {
      timer.cancel();
    }
  }

  /// Close all managed sinks.
  Future<void> closeSinks() async {
    final sinks = List<StreamSink<dynamic>>.from(_sinks);

    _sinks.clear();

    for (final sink in sinks) {
      try {
        await sink.close();
      } on Object catch (_) {
        // Cleanup should continue.
      }
    }
  }

  /// Close all managed subjects.
  Future<void> closeSubjects() async {
    final subjects = List<Subject<dynamic>>.from(_subjects);

    _subjects.clear();

    for (final subject in subjects) {
      try {
        if (!subject.isClosed) {
          await subject.close();
        }
      } on Object catch (_) {
        // Cleanup should continue.
      }
    }
  }

  /// Run all registered custom cleanup callbacks.
  Future<void> runCleanups() async {
    final cleanups = List<FutureOr<void> Function()>.from(_cleanups);

    _cleanups.clear();

    for (final cleanup in cleanups) {
      try {
        await cleanup();
      } on Object catch (_) {
        // Cleanup should continue.
      }
    }
  }

  /// Dispose all registered resources.
  ///
  /// This method is idempotent.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    cancelTimers();

    await cancelSubscriptions();
    await closeSinks();
    await closeSubjects();
    await runCleanups();
  }
}

/// Convenience extension for safely registering subscriptions.
extension StreamDisposableSubscriptionX<T> on StreamSubscription<T> {
  /// Register this subscription with [disposable].
  StreamSubscription<T> manageWith(StreamDisposable disposable) {
    return disposable.addSubscription(this);
  }
}

/// Convenience extension for registering timers.
extension StreamDisposableTimerX on Timer {
  /// Register this timer with [disposable].
  Timer manageWith(StreamDisposable disposable) {
    return disposable.addTimer(this);
  }
}
