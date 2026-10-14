import 'dart:async';

import 'package:clock/clock.dart';
import 'package:media_core/bug/fault_config.dart';
import 'package:media_core/bug/fault_event.dart';
import 'package:media_core/bug/fault_scenario.dart';

/// Callback used by [FaultScheduler] to perform the actual fault injection.
///
/// The scheduler is responsible only for timing and bookkeeping.
/// The callback is responsible for executing the fault.
typedef FaultInjectionCallback = FutureOr<FaultEvent> Function({required String faultId, required FaultConfig config});

/// Schedules fault injections for a later execution time.
///
/// [FaultScheduler] owns timing and scheduled-fault bookkeeping.
///
/// It does not:
/// - decide whether a fault is allowed;
/// - execute business fault logic;
/// - manage bug mode permissions;
/// - manage fault hooks;
/// - cancel running fault execution.
///
/// ```text
/// FaultScheduler
///       │
///       ├── schedule()
///       ├── scheduleDelayed()
///       ├── scheduleScenario()
///       │
///       └── FaultInjectionCallback
///                  ↓
///             FaultInjector
///                  ↓
///                BugHook
/// ```
final class FaultScheduler {
  /// Creates a scheduler that hands every due fault to [onInject].
  FaultScheduler({required FaultInjectionCallback onInject}) : _onInject = onInject;

  final FaultInjectionCallback _onInject;

  final Map<String, _ScheduledFault> _scheduled = <String, _ScheduledFault>{};

  bool _disposed = false;

  /// Whether this scheduler has been disposed.
  bool get isDisposed => _disposed;

  /// Number of currently scheduled faults.
  int get scheduledCount => _scheduled.length;

  /// Whether any faults are currently scheduled.
  bool get hasScheduledFaults => _scheduled.isNotEmpty;

  /// IDs of all currently scheduled faults.
  List<String> get scheduledFaultIds => List<String>.unmodifiable(_scheduled.keys);

  /// Whether a fault with [faultId] is currently scheduled.
  bool isScheduled(String faultId) {
    return _scheduled.containsKey(faultId);
  }

  /// Schedules a fault for execution.
  ///
  /// The configuration's own delay is respected.
  Future<FaultEvent> schedule({required String faultId, required FaultConfig config}) {
    return scheduleDelayed(faultId: faultId, config: config, delay: config.delay ?? Duration.zero);
  }

  /// Schedules a fault with an explicit delay.
  ///
  /// The explicit [delay] replaces the delay contained in [config].
  Future<FaultEvent> scheduleDelayed({required String faultId, required FaultConfig config, required Duration delay}) {
    _ensureNotDisposed();
    _validateFaultId(faultId);

    if (delay.isNegative) {
      throw ArgumentError.value(delay, 'delay', 'delay must not be negative.');
    }

    config.validateOrThrow();

    if (!config.isActive) {
      throw StateError('Cannot schedule a disabled fault.');
    }

    if (_scheduled.containsKey(faultId)) {
      throw StateError('A fault with ID "$faultId" is already scheduled.');
    }

    final effectiveConfig = config.withDelay(delay);

    final scheduled = _ScheduledFault(faultId: faultId, config: effectiveConfig, scheduledAt: clock.now());

    _scheduled[faultId] = scheduled;

    final future = _executeScheduled(scheduled);

    scheduled.future = future;

    return future;
  }

  /// Schedules every fault in a scenario.
  ///
  /// Each fault receives a generated ID based on the scenario ID and
  /// its position within the scenario.
  Future<List<FaultEvent>> scheduleScenario(FaultScenario scenario) async {
    _ensureNotDisposed();

    scenario.validateOrThrow();

    if (!scenario.enabled) {
      return const <FaultEvent>[];
    }

    final futures = <Future<FaultEvent>>[];

    for (var index = 0; index < scenario.faults.length; index++) {
      final config = scenario.faults[index];

      if (!config.isActive) {
        continue;
      }

      final faultId = '${scenario.id}_$index';

      futures.add(schedule(faultId: faultId, config: config));
    }

    if (futures.isEmpty) {
      return const <FaultEvent>[];
    }

    return await Future.wait(futures);
  }

  /// Schedules a scenario repeatedly.
  ///
  /// A new run starts after the previous run has completed.
  ///
  /// If [FaultScenario.maxRuns] is `null`, the scenario repeats indefinitely
  /// until cancellation or disposal.
  Future<List<FaultEvent>> scheduleRepeatedScenario(FaultScenario scenario) async {
    _ensureNotDisposed();

    scenario.validateOrThrow();

    if (!scenario.enabled) {
      return const <FaultEvent>[];
    }

    if (!scenario.repeat) {
      return await scheduleScenario(scenario);
    }

    final events = <FaultEvent>[];
    var run = 0;

    while (!_disposed) {
      if (scenario.maxRuns != null && run >= scenario.maxRuns!) {
        break;
      }

      run++;

      final runScenario = scenario.copyWith(id: '${scenario.id}_run_$run');

      final runEvents = await scheduleScenario(runScenario);

      events.addAll(runEvents);

      if (!scenario.repeat) {
        break;
      }
    }

    if (_disposed) {
      throw FaultScheduleCancelledException(
        'Fault scenario "${scenario.id}" was cancelled because '
        'the scheduler was disposed.',
      );
    }

    return List<FaultEvent>.unmodifiable(events);
  }

  /// Returns the future associated with a scheduled fault.
  ///
  /// Returns `null` when [faultId] is not scheduled.
  Future<FaultEvent>? futureOf(String faultId) {
    return _scheduled[faultId]?.future;
  }

  /// Cancels a scheduled fault.
  ///
  /// Cancellation only prevents the scheduled callback from executing.
  /// It does not interrupt a callback that has already started.
  bool cancel(String faultId) {
    final scheduled = _scheduled.remove(faultId);

    if (scheduled == null) {
      return false;
    }

    scheduled.cancel();

    return true;
  }

  /// Cancels all currently scheduled faults.
  ///
  /// Running fault callbacks are not interrupted.
  int cancelAll() {
    if (_scheduled.isEmpty) {
      return 0;
    }

    final values = List<_ScheduledFault>.of(_scheduled.values);

    _scheduled.clear();

    for (final scheduled in values) {
      scheduled.cancel();
    }

    return values.length;
  }

  /// Removes a scheduled fault from the bookkeeping map.
  ///
  /// Unlike [cancel], this method does not cancel the underlying timer.
  ///
  /// This method is intended for internal lifecycle cleanup.
  bool remove(String faultId) {
    return _scheduled.remove(faultId) != null;
  }

  /// Removes all scheduled-fault bookkeeping.
  ///
  /// Unlike [cancelAll], this method does not cancel timers.
  ///
  /// This method should only be used when the owner is already disposing
  /// the scheduler and no further callback execution is expected.
  void clear() {
    _scheduled.clear();
  }

  /// Waits for a scheduled fault to complete.
  ///
  /// Throws [StateError] when [faultId] is not scheduled.
  Future<FaultEvent> wait(String faultId) {
    final future = futureOf(faultId);

    if (future == null) {
      throw StateError('Fault "$faultId" is not scheduled.');
    }

    return future;
  }

  Future<FaultEvent> _executeScheduled(_ScheduledFault scheduled) async {
    try {
      if (scheduled.delay > Duration.zero) {
        await Future<void>.delayed(scheduled.delay);
      }

      if (scheduled.isCancelled || _disposed) {
        throw FaultScheduleCancelledException('Fault "${scheduled.faultId}" was cancelled.');
      }

      return await _onInject(faultId: scheduled.faultId, config: scheduled.config);
    } finally {
      if (identical(_scheduled[scheduled.faultId], scheduled)) {
        _scheduled.remove(scheduled.faultId);
      }
    }
  }

  void _validateFaultId(String faultId) {
    if (faultId.trim().isEmpty) {
      throw ArgumentError.value(faultId, 'faultId', 'faultId must not be empty.');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('FaultScheduler has already been disposed.');
    }
  }

  /// Disposes the scheduler.
  ///
  /// Scheduled timers are cancelled.
  /// Fault callbacks that are already running are not interrupted.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    cancelAll();
  }
}

/// Internal representation of a scheduled fault.
final class _ScheduledFault {
  _ScheduledFault({required this.faultId, required this.config, required this.scheduledAt})
    : delay = config.delay ?? Duration.zero;

  final String faultId;
  final FaultConfig config;
  final DateTime scheduledAt;
  final Duration delay;

  Future<FaultEvent>? future;

  bool isCancelled = false;

  void cancel() {
    isCancelled = true;
  }
}

/// Thrown when a scheduled fault is cancelled before execution.
final class FaultScheduleCancelledException implements Exception {
  /// Creates the cancellation error with a default message when none is supplied.
  FaultScheduleCancelledException([this.message = 'The scheduled fault was cancelled.']);

  /// Why the scheduled fault was cancelled, for display in bug-mode diagnostics.
  final String message;

  @override
  String toString() {
    return 'FaultScheduleCancelledException: $message';
  }
}
