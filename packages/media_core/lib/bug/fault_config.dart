import 'package:equatable/equatable.dart';
import 'package:media_core/bug/fault_type.dart';

/// Configuration for a single fault injection.
///
/// [FaultConfig] describes how a fault should be injected.
/// It does not execute the fault and does not schedule it.
///
/// ```text
/// FaultType
///     ↓
/// FaultConfig
///     ↓
/// FaultInjector / FaultScheduler
/// ```
final class FaultConfig extends Equatable {
  /// Describes one fault to inject, including when it fires and how often it may repeat.
  const FaultConfig({
    required this.type,
    this.enabled = true,
    this.probability = 1.0,
    this.delay,
    this.duration,
    this.maxOccurrences,
    this.message,
    this.metadata = const <String, Object?>{},
  }) : assert(probability >= 0.0 && probability <= 1.0, 'probability must be between 0.0 and 1.0.'),
       assert(maxOccurrences == null || maxOccurrences > 0, 'maxOccurrences must be greater than 0.');

  /// Creates a configuration for a deterministic fault.
  const FaultConfig.deterministic({
    required FaultType type,
    bool enabled = true,
    Duration? delay,
    Duration? duration,
    int? maxOccurrences,
    String? message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         type: type,
         enabled: enabled,
         probability: 1,
         delay: delay,
         duration: duration,
         maxOccurrences: maxOccurrences,
         message: message,
         metadata: metadata,
       );

  /// Creates a configuration for a probabilistic fault.
  const FaultConfig.random({
    required FaultType type,
    bool enabled = true,
    double probability = 0.5,
    Duration? delay,
    Duration? duration,
    int? maxOccurrences,
    String? message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         type: type,
         enabled: enabled,
         probability: probability,
         delay: delay,
         duration: duration,
         maxOccurrences: maxOccurrences,
         message: message,
         metadata: metadata,
       );

  /// Fault type.
  final FaultType type;

  /// Whether this fault configuration is enabled.
  final bool enabled;

  /// Probability of injecting this fault.
  ///
  /// `1.0` means always.
  /// `0.0` means never.
  final double probability;

  /// Delay before fault injection.
  final Duration? delay;

  /// Optional duration for the fault.
  final Duration? duration;

  /// Maximum number of times this fault may occur.
  ///
  /// `null` means unlimited.
  final int? maxOccurrences;

  /// Optional human-readable fault message.
  final String? message;

  /// Additional fault metadata.
  final Map<String, Object?> metadata;

  /// Whether this configuration is active.
  bool get isActive => enabled && probability > 0.0;

  /// Whether this configuration is disabled.
  bool get isDisabled => !enabled;

  /// Whether the fault has a guaranteed probability.
  bool get isGuaranteed => probability >= 1.0;

  /// Whether the fault is probabilistic.
  bool get isProbabilistic => probability > 0.0 && probability < 1.0;

  /// Whether this configuration has a delay.
  bool get hasDelay => delay != null;

  /// Whether this configuration has a duration.
  bool get hasDuration => duration != null;

  /// Whether this configuration has an occurrence limit.
  bool get hasMaxOccurrences => maxOccurrences != null;

  /// Whether this configuration has a message.
  bool get hasMessage => message != null && message!.trim().isNotEmpty;

  /// Whether this configuration has metadata.
  bool get hasMetadata => metadata.isNotEmpty;

  /// Whether this configuration represents a deterministic fault.
  bool get isDeterministic => type.isDeterministic && isGuaranteed;

  /// Whether this configuration represents a random fault.
  bool get isRandom => type.isRandom;

  /// Whether this configuration represents a disruptive fault.
  bool get isDisruptive => type.isDisruptive;

  /// Whether this configuration represents a stress fault.
  bool get isStress => type.isStress;

  /// Whether this configuration represents a chaos fault.
  bool get isChaos => type.isChaos;

  /// Whether this configuration requires random-fault permission.
  bool get requiresRandomMode => isRandom || isProbabilistic;

  /// Whether this configuration requires deterministic-fault permission.
  bool get requiresDeterministicMode => !requiresRandomMode && type.isDeterministic;

  /// Whether this configuration requires disruptive-fault permission.
  bool get requiresDisruptiveMode => isDisruptive;

  /// Whether this configuration requires stress-fault permission.
  bool get requiresStressMode => isStress;

  /// Whether this configuration requires chaos-fault permission.
  bool get requiresChaosMode => isChaos;

  /// Creates a modified copy of this configuration.
  FaultConfig copyWith({
    FaultType? type,
    bool? enabled,
    double? probability,
    Duration? delay,
    Duration? duration,
    int? maxOccurrences,
    String? message,
    Map<String, Object?>? metadata,
  }) {
    return FaultConfig(
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      probability: probability ?? this.probability,
      delay: delay ?? this.delay,
      duration: duration ?? this.duration,
      maxOccurrences: maxOccurrences ?? this.maxOccurrences,
      message: message ?? this.message,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Enables this fault.
  FaultConfig enable() {
    if (enabled) {
      return this;
    }

    return copyWith(enabled: true);
  }

  /// Disables this fault.
  FaultConfig disable() {
    if (!enabled) {
      return this;
    }

    return copyWith(enabled: false);
  }

  /// Changes the fault type.
  FaultConfig withType(FaultType value) {
    return copyWith(type: value);
  }

  /// Changes the probability.
  FaultConfig withProbability(double value) {
    _validateProbability(value);

    return copyWith(probability: value);
  }

  /// Changes the delay.
  ///
  /// Passing `null` clears the delay.
  FaultConfig withDelay(Duration? value) {
    if (value != null && value.isNegative) {
      throw ArgumentError.value(value, 'value', 'delay must not be negative.');
    }

    return FaultConfig(
      type: type,
      enabled: enabled,
      probability: probability,
      delay: value,
      duration: duration,
      maxOccurrences: maxOccurrences,
      message: message,
      metadata: metadata,
    );
  }

  /// Removes the delay.
  FaultConfig withoutDelay() {
    return withDelay(null);
  }

  /// Changes the fault duration.
  ///
  /// Passing `null` clears the duration.
  FaultConfig withDuration(Duration? value) {
    if (value != null && value.isNegative) {
      throw ArgumentError.value(value, 'value', 'duration must not be negative.');
    }

    return FaultConfig(
      type: type,
      enabled: enabled,
      probability: probability,
      delay: delay,
      duration: value,
      maxOccurrences: maxOccurrences,
      message: message,
      metadata: metadata,
    );
  }

  /// Removes the fault duration.
  FaultConfig withoutDuration() {
    return withDuration(null);
  }

  /// Changes the maximum occurrence count.
  ///
  /// Passing `null` removes the occurrence limit.
  FaultConfig withMaxOccurrences(int? value) {
    if (value != null && value <= 0) {
      throw ArgumentError.value(value, 'value', 'maxOccurrences must be greater than 0.');
    }

    return FaultConfig(
      type: type,
      enabled: enabled,
      probability: probability,
      delay: delay,
      duration: duration,
      maxOccurrences: value,
      message: message,
      metadata: metadata,
    );
  }

  /// Removes the maximum occurrence limit.
  FaultConfig withoutMaxOccurrences() {
    return withMaxOccurrences(null);
  }

  /// Changes the fault message.
  ///
  /// Passing `null` clears the message.
  FaultConfig withMessage(String? value) {
    final normalized = value?.trim();

    return FaultConfig(
      type: type,
      enabled: enabled,
      probability: probability,
      delay: delay,
      duration: duration,
      maxOccurrences: maxOccurrences,
      message: normalized,
      metadata: metadata,
    );
  }

  /// Removes the fault message.
  FaultConfig withoutMessage() {
    return withMessage(null);
  }

  /// Adds or replaces a metadata entry.
  FaultConfig withMetadata(String key, Object? value) {
    final normalizedKey = key.trim();

    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Metadata key must not be empty.');
    }

    final nextMetadata = <String, Object?>{...metadata, normalizedKey: value};

    return copyWith(metadata: nextMetadata);
  }

  /// Adds multiple metadata entries.
  FaultConfig withMetadataMap(Map<String, Object?> values) {
    if (values.isEmpty) {
      return this;
    }

    final nextMetadata = <String, Object?>{...metadata};

    for (final entry in values.entries) {
      final key = entry.key.trim();

      if (key.isEmpty) {
        throw ArgumentError.value(entry.key, 'values', 'Metadata keys must not be empty.');
      }

      nextMetadata[key] = entry.value;
    }

    return copyWith(metadata: nextMetadata);
  }

  /// Removes a metadata entry.
  FaultConfig withoutMetadata(String key) {
    final normalizedKey = key.trim();

    if (!metadata.containsKey(normalizedKey)) {
      return this;
    }

    final nextMetadata = <String, Object?>{...metadata}..remove(normalizedKey);

    return copyWith(metadata: nextMetadata);
  }

  /// Clears all metadata.
  FaultConfig clearMetadata() {
    if (metadata.isEmpty) {
      return this;
    }

    return copyWith(metadata: const <String, Object?>{});
  }

  /// Returns whether a metadata key exists.
  bool containsMetadata(String key) {
    return metadata.containsKey(key.trim());
  }

  /// Returns a metadata value.
  Object? metadataValue(String key) {
    return metadata[key.trim()];
  }

  /// Returns a typed metadata value.
  T? metadataAs<T>(String key) {
    final value = metadataValue(key);

    if (value is T) {
      return value;
    }

    return null;
  }

  /// Returns an immutable metadata view.
  Map<String, Object?> get metadataView => Map<String, Object?>.unmodifiable(metadata);

  /// Validates this configuration.
  List<String> validate() {
    final errors = <String>[];

    if (!FaultType.isValid(type.value)) {
      errors.add('type must not be empty.');
    }

    if (probability < 0.0 || probability > 1.0) {
      errors.add('probability must be between 0.0 and 1.0.');
    }

    if (delay != null && delay!.isNegative) {
      errors.add('delay must not be negative.');
    }

    if (duration != null && duration!.isNegative) {
      errors.add('duration must not be negative.');
    }

    if (maxOccurrences != null && maxOccurrences! <= 0) {
      errors.add('maxOccurrences must be greater than 0.');
    }

    return List<String>.unmodifiable(errors);
  }

  /// Validates this configuration and throws if invalid.
  void validateOrThrow() {
    final errors = validate();

    if (errors.isEmpty) {
      return;
    }

    throw StateError('Invalid FaultConfig: ${errors.join(' ')}');
  }

  void _validateProbability(double value) {
    if (value < 0.0 || value > 1.0) {
      throw ArgumentError.value(value, 'value', 'probability must be between 0.0 and 1.0.');
    }
  }

  @override
  List<Object?> get props => <Object?>[type, enabled, probability, delay, duration, maxOccurrences, message, metadata];

  @override
  String toString() {
    return 'FaultConfig('
        'type: ${type.value}, '
        'enabled: $enabled, '
        'probability: $probability, '
        'delay: $delay, '
        'duration: $duration, '
        'maxOccurrences: $maxOccurrences, '
        'message: $message, '
        'metadata: $metadata'
        ')';
  }
}
