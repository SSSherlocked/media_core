import 'dart:async';
import 'package:media_core/bug/bug_mode.dart';
import 'package:media_core/bug/bug_mode_config.dart';
import 'package:media_core/bug/library.dart' show BugHook, FaultInjector;

/// Runtime controller for [BugModeConfig].
///
/// [BugModeController] manages the mutable runtime configuration of the
/// bug injection system.
///
/// It does not perform fault injection itself.
///
/// ```text
/// BugModeController
///        │
///        ├── BugModeConfig
///        │
///        ├── FaultInjector
///        │
///        └── FaultScheduler
/// ```
final class BugModeController {
  /// Creates a controller for [config], rejecting it immediately when validation fails.
  BugModeController({BugModeConfig config = BugModeConfig.disabled}) : _config = config {
    _config.validateOrThrow();
  }

  BugModeConfig _config;

  final StreamController<BugModeConfig> _configController = StreamController<BugModeConfig>.broadcast();

  bool _disposed = false;

  /// Current configuration.
  BugModeConfig get config => _config;

  /// Current bug mode.
  BugMode get mode => _config.mode;

  /// Whether this controller has been disposed.
  bool get isDisposed => _disposed;

  /// Whether bug mode is currently active.
  bool get isActive => !_disposed && _config.isActive;

  /// Whether bug mode is disabled.
  bool get isDisabled => _disposed || _config.isDisabled;

  /// Whether deterministic faults can be injected.
  bool get canInjectDeterministicFaults => !_disposed && _config.canInjectDeterministicFaults;

  /// Whether random faults can be injected.
  bool get canInjectRandomFaults => !_disposed && _config.canInjectRandomFaults;

  /// Whether disruptive faults can be injected.
  bool get canInjectDisruptiveFaults => !_disposed && _config.canInjectDisruptiveFaults;

  /// Whether stress faults can be injected.
  bool get canInjectStressFaults => !_disposed && _config.canInjectStressFaults;

  /// Whether chaos faults can be injected.
  bool get canInjectChaosFaults => !_disposed && _config.canInjectChaosFaults;

  /// Whether new faults can be scheduled.
  bool get canSchedule => !_disposed && _config.canSchedule;

  /// Whether concurrent fault execution is allowed.
  bool get canStartConcurrentFault => !_disposed && _config.canStartConcurrentFault;

  /// Maximum number of concurrently executing faults.
  int get maxConcurrentFaults => _config.maxConcurrentFaults;

  /// Maximum number of scheduled faults.
  int get maxScheduledFaults => _config.maxScheduledFaults;

  /// Whether the current configuration is safe.
  bool get isSafeConfiguration => !_disposed && _config.isSafeConfiguration;

  /// Whether the current configuration is stress-oriented.
  bool get isStressConfiguration => !_disposed && _config.isStressConfiguration;

  /// Whether the current configuration is chaos-oriented.
  bool get isChaosConfiguration => !_disposed && _config.isChaosConfiguration;

  /// Emits whenever the configuration changes.
  Stream<BugModeConfig> get onConfigChanged => _configController.stream;

  /// Replaces the current configuration.
  ///
  /// The configuration is validated before being applied.
  BugModeConfig setConfig(BugModeConfig value) {
    _ensureNotDisposed();

    value.validateOrThrow();

    if (value == _config) {
      return _config;
    }

    _config = value;
    _emitConfig();

    return _config;
  }

  /// Enables bug mode.
  BugModeConfig enable() {
    _ensureNotDisposed();
    return setConfig(_config.enable());
  }

  /// Disables bug mode.
  BugModeConfig disable() {
    _ensureNotDisposed();
    return setConfig(_config.disable());
  }

  /// Sets the current bug mode.
  BugModeConfig setMode(BugMode value) {
    _ensureNotDisposed();
    return setConfig(_config.withMode(value));
  }

  /// Disables the current bug mode.
  BugModeConfig disableMode() {
    return disable();
  }

  /// Switches to safe mode.
  BugModeConfig setSafeMode() {
    _ensureNotDisposed();
    return setConfig(_config.asSafe());
  }

  /// Switches to normal mode.
  BugModeConfig setNormalMode() {
    _ensureNotDisposed();
    return setConfig(_config.asNormal());
  }

  /// Switches to aggressive mode.
  BugModeConfig setAggressiveMode() {
    _ensureNotDisposed();
    return setConfig(_config.asAggressive());
  }

  /// Switches to chaos mode.
  BugModeConfig setChaosMode() {
    _ensureNotDisposed();
    return setConfig(_config.asChaos());
  }

  /// Updates the configuration using a transformation callback.
  BugModeConfig update(BugModeConfig Function(BugModeConfig current) updater) {
    _ensureNotDisposed();

    final next = updater(_config);

    return setConfig(next);
  }

  /// Enables or disables deterministic faults.
  BugModeConfig setAllowDeterministicFaults({required bool value}) {
    _ensureNotDisposed();

    return setConfig(_config.copyWith(allowDeterministicFaults: value));
  }

  /// Enables or disables random faults.
  BugModeConfig setAllowRandomFaults({required bool value}) {
    _ensureNotDisposed();

    return setConfig(_config.copyWith(allowRandomFaults: value));
  }

  /// Enables or disables disruptive faults.
  BugModeConfig setAllowDisruptiveFaults({required bool value}) {
    _ensureNotDisposed();

    return setConfig(_config.copyWith(allowDisruptiveFaults: value));
  }

  /// Enables or disables stress faults.
  BugModeConfig setAllowStressFaults({required bool value}) {
    _ensureNotDisposed();

    return setConfig(_config.copyWith(allowStressFaults: value));
  }

  /// Enables or disables chaos faults.
  BugModeConfig setAllowChaosFaults({required bool value}) {
    _ensureNotDisposed();

    return setConfig(_config.copyWith(allowChaosFaults: value));
  }

  /// Sets the maximum number of concurrent faults.
  BugModeConfig setMaxConcurrentFaults(int value) {
    _ensureNotDisposed();

    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'maxConcurrentFaults must be greater than or equal to 0.');
    }

    return setConfig(_config.copyWith(maxConcurrentFaults: value));
  }

  /// Sets the maximum number of scheduled faults.
  BugModeConfig setMaxScheduledFaults(int value) {
    _ensureNotDisposed();

    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'maxScheduledFaults must be greater than or equal to 0.');
    }

    return setConfig(_config.copyWith(maxScheduledFaults: value));
  }

  /// Restores the disabled configuration.
  BugModeConfig reset() {
    _ensureNotDisposed();
    return setConfig(BugModeConfig.disabled);
  }

  /// Returns an immutable snapshot of the current configuration.
  BugModeConfig snapshot() {
    _ensureNotDisposed();
    return _config;
  }

  void _emitConfig() {
    if (_disposed || _configController.isClosed) {
      return;
    }

    _configController.add(_config);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('BugModeController has already been disposed.');
    }
  }

  /// Disposes this controller.
  ///
  /// Disposing the controller does not cancel faults that are already
  /// executing. Fault execution ownership remains with [FaultInjector]
  /// and the corresponding [BugHook].
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _configController.close();
  }
}
