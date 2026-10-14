import 'dart:async';
import 'package:clock/clock.dart';
import 'package:media_core/bug/bug_hooks.dart';
import 'package:media_core/bug/bug_mode_controller.dart';
import 'package:media_core/bug/fault_config.dart';
import 'package:media_core/bug/fault_event.dart';
import 'package:media_core/bug/fault_scheduler.dart' show FaultScheduler;
import 'package:media_core/bug/fault_type.dart';

/// Coordinates fault injection between bug mode configuration and hooks.
///
/// The injector owns permission checks, active fault bookkeeping,
/// fault ID generation, hook selection, and event creation.
///
/// Scheduling belongs to [FaultScheduler].
final class FaultInjector {
  /// Wires a [modeController] to the [hooks] registry that performs injection.
  FaultInjector({required BugModeController modeController, BugHooks? hooks})
    : _modeController = modeController,
      _hooks = hooks ?? BugHooks();

  final BugModeController _modeController;
  final BugHooks _hooks;

  final Set<String> _activeFaultIds = <String>{};

  bool _disposed = false;
  int _faultCounter = 0;

  /// Controls the current bug injection mode.
  BugModeController get modeController => _modeController;

  /// Provides access to registered bug hooks.
  BugHooks get hooks => _hooks;

  /// Whether this injector has been disposed.
  bool get isDisposed => _disposed;

  /// Number of currently active fault injections.
  int get activeFaultCount => _activeFaultIds.length;

  /// Whether at least one fault is currently active.
  bool get hasActiveFaults => _activeFaultIds.isNotEmpty;

  /// Returns the IDs of currently active faults.
  List<String> get activeFaultIds => List<String>.unmodifiable(_activeFaultIds);

  /// Returns whether the given fault configuration can be injected.
  bool canInject(FaultConfig config) {
    if (_disposed) {
      return false;
    }

    if (!_modeController.isActive) {
      return false;
    }

    if (!config.isActive) {
      return false;
    }

    if (!_modeAllows(config)) {
      return false;
    }

    if (!_hooks.canInject(config)) {
      return false;
    }

    if (_activeFaultIds.length >= _modeController.maxConcurrentFaults) {
      return false;
    }

    return true;
  }

  /// Injects a fault through the first supporting hook.
  ///
  /// The fault remains active until the selected hook completes.
  Future<FaultEvent> inject(FaultConfig config, {String? source, String? target, Object? metadata}) async {
    _ensureNotDisposed();

    config.validateOrThrow();

    if (!config.isActive) {
      throw StateError('Cannot inject a disabled fault.');
    }

    _ensureModeAllows(config);

    if (_activeFaultIds.length >= _modeController.maxConcurrentFaults) {
      throw StateError('Maximum concurrent fault count has been reached.');
    }

    final hook = _hooks.findSupporting(config);

    if (hook == null) {
      throw StateError(
        'No bug hook supports fault type '
        '"${config.type.toValue}".',
      );
    }

    final faultId = _createFaultId(config);

    _activeFaultIds.add(faultId);

    try {
      await hook.onFault(config, target: target, metadata: metadata);

      return FaultEvent.injected(faultId: faultId, config: config, source: source, target: target, metadata: metadata);
    } finally {
      _activeFaultIds.remove(faultId);
    }
  }

  /// Convenience alias for [inject].
  ///
  /// This method remains asynchronous and returns a Future.
  Future<FaultEvent> injectSync(FaultConfig config, {String? source, String? target, Object? metadata}) {
    return inject(config, source: source, target: target, metadata: metadata);
  }

  /// Attempts to inject a fault.
  ///
  /// Returns `null` when injection fails.
  Future<FaultEvent?> tryInject(FaultConfig config, {String? source, String? target, Object? metadata}) async {
    try {
      return await inject(config, source: source, target: target, metadata: metadata);
    } on Object catch (_) {
      return null;
    }
  }

  /// Attempts to inject a fault through [injectSync].
  Future<FaultEvent?> tryInjectSync(FaultConfig config, {String? source, String? target, Object? metadata}) {
    return tryInject(config, source: source, target: target, metadata: metadata);
  }

  /// Creates a fault event without executing a hook.
  ///
  /// This is useful when the caller performs the actual fault behavior
  /// independently.
  FaultEvent createEvent({
    required String faultId,
    required FaultConfig config,
    String? source,
    String? target,
    Object? metadata,
  }) {
    _ensureNotDisposed();

    final normalizedFaultId = faultId.trim();

    if (normalizedFaultId.isEmpty) {
      throw ArgumentError.value(faultId, 'faultId', 'faultId must not be empty.');
    }

    config.validateOrThrow();

    return FaultEvent.injected(
      faultId: normalizedFaultId,
      config: config,
      source: source,
      target: target,
      metadata: metadata,
    );
  }

  /// Returns whether a fault type is currently allowed by bug mode.
  bool isTypeAllowed(FaultType type) {
    if (_disposed || !_modeController.isActive) {
      return false;
    }

    if (type.isRandom) {
      return _modeController.canInjectRandomFaults;
    }

    if (type.isChaos) {
      return _modeController.canInjectChaosFaults;
    }

    if (type.isDisruptive) {
      return _modeController.canInjectDisruptiveFaults;
    }

    if (type.isStress) {
      return _modeController.canInjectStressFaults;
    }

    return _modeController.canInjectDeterministicFaults;
  }

  /// Clears active fault bookkeeping.
  ///
  /// This does not interrupt fault hooks that are already executing.
  void clearActiveFaults() {
    _activeFaultIds.clear();
  }

  bool _modeAllows(FaultConfig config) {
    if (config.requiresRandomMode && !_modeController.canInjectRandomFaults) {
      return false;
    }

    if (config.requiresChaosMode && !_modeController.canInjectChaosFaults) {
      return false;
    }

    if (config.requiresDisruptiveMode && !_modeController.canInjectDisruptiveFaults) {
      return false;
    }

    if (config.requiresStressMode && !_modeController.canInjectStressFaults) {
      return false;
    }

    if (config.requiresDeterministicMode && !_modeController.canInjectDeterministicFaults) {
      return false;
    }

    return true;
  }

  void _ensureModeAllows(FaultConfig config) {
    if (!_modeController.isActive) {
      throw StateError('Bug mode is not active.');
    }

    if (!_modeAllows(config)) {
      throw StateError(
        'Bug mode does not allow fault type '
        '"${config.type.toValue}".',
      );
    }
  }

  String _createFaultId(FaultConfig config) {
    final timestamp = clock.now().microsecondsSinceEpoch;
    final counter = _faultCounter++;

    return 'fault_${config.type.value}_'
        '${timestamp}_$counter';
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('FaultInjector has already been disposed.');
    }
  }

  /// Disposes the injector.
  ///
  /// Running hooks are not interrupted. Only local bookkeeping is cleared.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _activeFaultIds.clear();
  }
}
