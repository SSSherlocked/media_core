import 'dart:async';

/// A lightweight scheduler for delayed and periodic asynchronous tasks.
///
/// The scheduler does not depend on Flutter and can be used by controllers,
/// repositories, services, and player managers.
class StreamScheduler {
  /// Creates an idle scheduler with no timers and no disposal.
  StreamScheduler();

  final Set<Timer> _timers = <Timer>{};

  bool _disposed = false;

  /// Whether this scheduler has been disposed.
  bool get isDisposed => _disposed;

  /// Whether this scheduler is still active.
  bool get isAlive => !_disposed;

  /// Number of active timers.
  int get timerCount => _timers.length;

  /// Schedule [action] to execute once after [delay].
  ///
  /// Returns the created [Timer].
  Timer once(Duration delay, FutureOr<void> Function() action) {
    if (_disposed) {
      throw StateError('StreamScheduler has been disposed.');
    }

    late final Timer timer;

    timer = Timer(delay, () async {
      _timers.remove(timer);

      if (_disposed) {
        return;
      }

      await action();
    });

    _timers.add(timer);

    return timer;
  }

  /// Schedule [action] periodically.
  ///
  /// The callback is awaited before another invocation is started.
  ///
  /// This prevents overlapping async callbacks.
  StreamPeriodicTask periodic(Duration interval, FutureOr<void> Function() action) {
    if (_disposed) {
      throw StateError('StreamScheduler has been disposed.');
    }

    final task = StreamPeriodicTask(interval: interval, action: action, onCancel: _removeTimer)..start();

    _timers.add(task.timer);

    return task;
  }

  /// Cancel all currently scheduled tasks.
  void cancelAll() {
    final timers = List<Timer>.from(_timers);

    _timers.clear();

    for (final timer in timers) {
      timer.cancel();
    }
  }

  /// Cancel a specific timer.
  void cancel(Timer timer) {
    if (_timers.remove(timer)) {
      timer.cancel();
    }
  }

  /// Dispose the scheduler.
  ///
  /// Scheduled tasks are cancelled. Currently executing async callbacks
  /// cannot be forcibly cancelled.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    cancelAll();
  }

  void _removeTimer(Timer timer) {
    _timers.remove(timer);
  }
}

/// A periodic asynchronous task.
///
/// Unlike [Timer.periodic], this class does not start the next invocation
/// while the previous async callback is still running.
class StreamPeriodicTask {
  /// Creates a task that runs [action] every [interval] and reports its timer
  /// to [onCancel] so the owner can drop it once the task is cancelled.
  StreamPeriodicTask({required this.interval, required this.action, this.onCancel});

  /// Delay between two invocations of [action].
  final Duration interval;

  /// Work performed on every tick.
  final FutureOr<void> Function() action;

  /// Hook the owner installs to unregister this task's timer.
  final void Function(Timer timer)? onCancel;

  Timer? _timer;

  bool _running = false;
  bool _cancelled = false;

  /// Whether this task is currently executing its callback.
  bool get isRunning => _running;

  /// Whether this task has been cancelled.
  bool get isCancelled => _cancelled;

  /// Number of completed executions.
  int executionCount = 0;

  /// Underlying timer.
  Timer get timer {
    final timer = _timer;

    if (timer == null) {
      throw StateError('StreamPeriodicTask has not been started.');
    }

    return timer;
  }

  /// Start the periodic task.
  void start() {
    if (_cancelled) {
      return;
    }

    if (_timer != null) {
      return;
    }

    _timer = Timer.periodic(interval, (_) {
      // A tick must not wait for the previous callback: `_running` inside
      // `_execute` skips overlapping ticks instead of queueing them.
      unawaited(_execute());
    });
  }

  Future<void> _execute() async {
    if (_cancelled || _running) {
      return;
    }

    _running = true;

    try {
      await action();
      executionCount++;
    } finally {
      _running = false;
    }
  }

  /// Cancel this task.
  void cancel() {
    if (_cancelled) {
      return;
    }

    _cancelled = true;

    final timer = _timer;

    if (timer != null) {
      timer.cancel();
      onCancel?.call(timer);
    }

    _timer = null;
  }
}

/// A scheduler that keeps only one delayed task for each key.
///
/// Useful for independently debouncing different resources.
///
/// Example:
/// ```dart
/// final scheduler = KeyedStreamScheduler();
///
/// scheduler.schedule(
///   'epg',
///   const Duration(seconds: 1),
///   () => refreshEpg(),
/// );
///
/// scheduler.schedule(
///   'iptv',
///   const Duration(seconds: 1),
///   () => refreshIptv(),
/// );
/// ```
class KeyedStreamScheduler {
  final Map<String, Timer> _timers = <String, Timer>{};

  bool _disposed = false;

  /// Number of currently scheduled keys.
  int get length => _timers.length;

  /// Whether a task is scheduled for [key].
  bool isScheduled(String key) {
    return _timers.containsKey(key);
  }

  /// Schedule a task for [key].
  ///
  /// An existing task with the same key is cancelled.
  void schedule(String key, Duration delay, FutureOr<void> Function() action) {
    if (_disposed) {
      return;
    }

    cancel(key);

    late final Timer timer;

    timer = Timer(delay, () async {
      _timers.remove(key);

      if (_disposed) {
        return;
      }

      await action();
    });

    _timers[key] = timer;
  }

  /// Cancel a task for [key].
  void cancel(String key) {
    final timer = _timers.remove(key);
    timer?.cancel();
  }

  /// Cancel every scheduled task.
  void cancelAll() {
    final timers = List<Timer>.from(_timers.values);
    _timers.clear();

    for (final timer in timers) {
      timer.cancel();
    }
  }

  /// Dispose this scheduler.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    cancelAll();
  }
}
