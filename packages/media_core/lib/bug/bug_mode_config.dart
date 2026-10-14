import 'package:equatable/equatable.dart';
import 'package:media_core/bug/bug_mode.dart';

/// Defines the configuration used by the bug injection system.
final class BugModeConfig extends Equatable {
  /// Creates a configuration; every field defaults to a switched-off bug mode.
  const BugModeConfig({
    this.mode = BugMode.disabled,
    this.enabled = false,
    this.allowDeterministicFaults = true,
    this.allowRandomFaults = false,
    this.allowDisruptiveFaults = false,
    this.allowStressFaults = false,
    this.allowChaosFaults = false,
    this.maxConcurrentFaults = 1,
    this.maxScheduledFaults = 100,
  });

  /// Completely disables bug injection.
  static const BugModeConfig disabled = BugModeConfig();

  /// Enables safe deterministic fault injection.
  static const BugModeConfig safe = BugModeConfig(mode: BugMode.safe, enabled: true);

  /// Enables normal fault injection.
  static const BugModeConfig normal = BugModeConfig(
    mode: BugMode.normal,
    enabled: true,
    allowRandomFaults: true,
    maxConcurrentFaults: 2,
  );

  /// Enables aggressive fault injection.
  static const BugModeConfig aggressive = BugModeConfig(
    mode: BugMode.aggressive,
    enabled: true,
    allowRandomFaults: true,
    allowDisruptiveFaults: true,
    allowStressFaults: true,
    maxConcurrentFaults: 4,
    maxScheduledFaults: 500,
  );

  /// Enables unrestricted chaos-oriented fault injection.
  static const BugModeConfig chaos = BugModeConfig(
    mode: BugMode.chaos,
    enabled: true,
    allowRandomFaults: true,
    allowDisruptiveFaults: true,
    allowStressFaults: true,
    allowChaosFaults: true,
    maxConcurrentFaults: 8,
    maxScheduledFaults: 1000,
  );

  /// Current bug mode.
  final BugMode mode;

  /// Whether bug injection is enabled.
  final bool enabled;

  /// Whether deterministic faults are allowed.
  final bool allowDeterministicFaults;

  /// Whether random faults are allowed.
  final bool allowRandomFaults;

  /// Whether disruptive faults are allowed.
  final bool allowDisruptiveFaults;

  /// Whether stress faults are allowed.
  final bool allowStressFaults;

  /// Whether chaos faults are allowed.
  final bool allowChaosFaults;

  /// Maximum number of simultaneously active faults.
  final int maxConcurrentFaults;

  /// Maximum number of scheduled faults.
  final int maxScheduledFaults;

  /// Whether bug injection is currently active.
  bool get isActive => enabled && !mode.isDisabled;

  /// Whether bug injection is disabled.
  bool get isDisabled => !isActive;

  /// Whether deterministic fault injection is allowed.
  bool get canInjectDeterministicFaults => isActive && allowDeterministicFaults && mode.allowsDeterministicFaults;

  /// Whether random fault injection is allowed.
  bool get canInjectRandomFaults =>
      isActive && allowRandomFaults && (mode.isNormal || mode.isAggressive || mode.isChaos);

  /// Whether disruptive fault injection is allowed.
  bool get canInjectDisruptiveFaults => isActive && allowDisruptiveFaults && mode.allowsDisruptiveFaults;

  /// Whether stress fault injection is allowed.
  bool get canInjectStressFaults => isActive && allowStressFaults && mode.allowsStressFaults;

  /// Whether chaos fault injection is allowed.
  bool get canInjectChaosFaults => isActive && allowChaosFaults && mode.allowsChaosFaults;

  /// Whether faults can be scheduled.
  bool get canSchedule => isActive && maxScheduledFaults > 0;

  /// Whether another concurrent fault can be started.
  bool get canStartConcurrentFault => isActive && maxConcurrentFaults > 0;

  /// Whether this is a safe configuration.
  bool get isSafeConfiguration =>
      mode.isSafe && !allowRandomFaults && !allowDisruptiveFaults && !allowStressFaults && !allowChaosFaults;

  /// Whether this configuration enables stress behavior.
  bool get isStressConfiguration => allowStressFaults || mode.isAggressive || mode.isChaos;

  /// Whether this configuration enables chaos behavior.
  bool get isChaosConfiguration => allowChaosFaults || mode.isChaos;

  /// Enables bug injection.
  BugModeConfig enable() {
    if (enabled) {
      return this;
    }

    return copyWith(enabled: true);
  }

  /// Disables bug injection.
  BugModeConfig disable() {
    if (!enabled) {
      return this;
    }

    return copyWith(enabled: false);
  }

  /// Changes the bug mode.
  BugModeConfig withMode(BugMode value) {
    return copyWith(mode: value);
  }

  /// Returns the safe preset.
  BugModeConfig asSafe() {
    return BugModeConfig.safe;
  }

  /// Returns the disabled preset.
  BugModeConfig asDisabled() {
    return BugModeConfig.disabled;
  }

  /// Returns the normal preset.
  BugModeConfig asNormal() {
    return BugModeConfig.normal;
  }

  /// Returns the aggressive preset.
  BugModeConfig asAggressive() {
    return BugModeConfig.aggressive;
  }

  /// Returns the chaos preset.
  BugModeConfig asChaos() {
    return BugModeConfig.chaos;
  }

  /// Creates a modified configuration.
  BugModeConfig copyWith({
    BugMode? mode,
    bool? enabled,
    bool? allowDeterministicFaults,
    bool? allowRandomFaults,
    bool? allowDisruptiveFaults,
    bool? allowStressFaults,
    bool? allowChaosFaults,
    int? maxConcurrentFaults,
    int? maxScheduledFaults,
  }) {
    return BugModeConfig(
      mode: mode ?? this.mode,
      enabled: enabled ?? this.enabled,
      allowDeterministicFaults: allowDeterministicFaults ?? this.allowDeterministicFaults,
      allowRandomFaults: allowRandomFaults ?? this.allowRandomFaults,
      allowDisruptiveFaults: allowDisruptiveFaults ?? this.allowDisruptiveFaults,
      allowStressFaults: allowStressFaults ?? this.allowStressFaults,
      allowChaosFaults: allowChaosFaults ?? this.allowChaosFaults,
      maxConcurrentFaults: maxConcurrentFaults ?? this.maxConcurrentFaults,
      maxScheduledFaults: maxScheduledFaults ?? this.maxScheduledFaults,
    );
  }

  /// Validates this configuration.
  List<String> validate() {
    final errors = <String>[];

    if (maxConcurrentFaults < 0) {
      errors.add('maxConcurrentFaults must not be negative.');
    }

    if (maxScheduledFaults < 0) {
      errors.add('maxScheduledFaults must not be negative.');
    }

    if (enabled && mode.isDisabled) {
      errors.add(
        'An enabled configuration cannot use '
        'BugMode.disabled.',
      );
    }

    if (isSafeConfiguration && maxConcurrentFaults > 1) {
      errors.add(
        'Safe configuration must allow at most '
        'one concurrent fault.',
      );
    }

    return List<String>.unmodifiable(errors);
  }

  /// Validates this configuration and throws when invalid.
  void validateOrThrow() {
    final errors = validate();

    if (errors.isEmpty) {
      return;
    }

    throw StateError('Invalid BugModeConfig: ${errors.join(' ')}');
  }

  @override
  List<Object?> get props => <Object?>[
    mode,
    enabled,
    allowDeterministicFaults,
    allowRandomFaults,
    allowDisruptiveFaults,
    allowStressFaults,
    allowChaosFaults,
    maxConcurrentFaults,
    maxScheduledFaults,
  ];

  @override
  String toString() {
    return 'BugModeConfig('
        'mode: $mode, '
        'enabled: $enabled, '
        'allowDeterministicFaults: '
        '$allowDeterministicFaults, '
        'allowRandomFaults: '
        '$allowRandomFaults, '
        'allowDisruptiveFaults: '
        '$allowDisruptiveFaults, '
        'allowStressFaults: '
        '$allowStressFaults, '
        'allowChaosFaults: '
        '$allowChaosFaults, '
        'maxConcurrentFaults: '
        '$maxConcurrentFaults, '
        'maxScheduledFaults: '
        '$maxScheduledFaults'
        ')';
  }
}
