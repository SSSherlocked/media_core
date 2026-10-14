import 'package:equatable/equatable.dart';
import 'package:media_core/bug/fault_config.dart';
import 'package:media_core/bug/fault_type.dart';

/// Defines a collection of fault configurations that can be executed
/// as a single fault injection scenario.
///
/// A scenario only describes faults and their execution policy.
/// It does not execute or schedule faults.
///
/// ```text
/// FaultScenario
///      │
///      ├── FaultConfig
///      │      └── FaultType
///      │
///      └── FaultScheduler
/// ```
final class FaultScenario extends Equatable {
  /// Groups [faults] behind one identifiable, repeatable scenario.
  FaultScenario({
    required String id,
    required String name,
    List<FaultConfig> faults = const <FaultConfig>[],
    this.enabled = true,
    this.repeat = false,
    this.maxRuns,
    this.description,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : id = _requireText(id, 'id'),
       name = _requireText(name, 'name'),
       faults = List<FaultConfig>.unmodifiable(faults),
       metadata = Map<String, Object?>.unmodifiable(metadata) {
    _validateConstructor();
  }

  /// Unique scenario identifier.
  final String id;

  /// Human-readable scenario name.
  final String name;

  /// Fault configurations contained in this scenario.
  final List<FaultConfig> faults;

  /// Whether the scenario is enabled.
  final bool enabled;

  /// Whether the scenario should repeat.
  final bool repeat;

  /// Maximum number of scenario runs.
  ///
  /// `null` means unlimited runs when [repeat] is enabled.
  final int? maxRuns;

  /// Optional scenario description.
  final String? description;

  /// Additional scenario metadata.
  final Map<String, Object?> metadata;

  /// Whether the scenario is currently active.
  bool get isActive => enabled && faults.isNotEmpty;

  /// Whether the scenario is disabled.
  bool get isDisabled => !enabled;

  /// Whether the scenario contains no faults.
  bool get isEmpty => faults.isEmpty;

  /// Whether the scenario contains at least one fault.
  bool get isNotEmpty => faults.isNotEmpty;

  /// Number of configured faults.
  int get faultCount => faults.length;

  /// Whether a description is available.
  bool get hasDescription => description != null && description!.trim().isNotEmpty;

  /// Whether metadata is available.
  bool get hasMetadata => metadata.isNotEmpty;

  /// Whether the scenario has a run limit.
  bool get hasRunLimit => maxRuns != null;

  /// Whether the scenario can repeat.
  bool get canRepeat => repeat && enabled;

  /// Whether this scenario runs only once.
  bool get isSingleRun => !repeat;

  /// Whether any contained fault is disabled.
  bool get containsDisabledFault => faults.any((fault) => fault.isDisabled);

  /// Whether the scenario contains a random fault.
  bool get containsRandomFault => faults.any((fault) => fault.type.isRandom);

  /// Whether the scenario contains a deterministic fault.
  bool get containsDeterministicFault => faults.any((fault) => fault.type.isDeterministic);

  /// Whether the scenario contains a disruptive fault.
  bool get containsDisruptiveFault => faults.any((fault) => fault.type.isDisruptive);

  /// Whether the scenario contains a stress fault.
  bool get containsStressFault => faults.any((fault) => fault.type.isStress);

  /// Whether the scenario contains a chaos fault.
  bool get containsChaosFault => faults.any((fault) => fault.type.isChaos);

  /// Finds the first fault with the given type.
  FaultConfig? findByType(FaultType type) {
    for (final fault in faults) {
      if (fault.type == type) {
        return fault;
      }
    }

    return null;
  }

  /// Whether the scenario contains the given fault type.
  bool containsType(FaultType type) {
    return findByType(type) != null;
  }

  /// Returns an immutable metadata view.
  Map<String, Object?> get metadataView => Map<String, Object?>.unmodifiable(metadata);

  /// Whether a metadata key exists.
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

  /// Creates a modified copy of this scenario.
  FaultScenario copyWith({
    String? id,
    String? name,
    List<FaultConfig>? faults,
    bool? enabled,
    bool? repeat,
    int? maxRuns,
    String? description,
    Map<String, Object?>? metadata,
  }) {
    return FaultScenario(
      id: id ?? this.id,
      name: name ?? this.name,
      faults: faults ?? this.faults,
      enabled: enabled ?? this.enabled,
      repeat: repeat ?? this.repeat,
      maxRuns: maxRuns ?? this.maxRuns,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Enables the scenario.
  FaultScenario enable() {
    if (enabled) {
      return this;
    }

    return copyWith(enabled: true);
  }

  /// Disables the scenario.
  FaultScenario disable() {
    if (!enabled) {
      return this;
    }

    return copyWith(enabled: false);
  }

  /// Adds a fault to the scenario.
  FaultScenario withFault(FaultConfig fault) {
    return copyWith(faults: <FaultConfig>[...faults, fault]);
  }

  /// Adds multiple faults to the scenario.
  FaultScenario withFaults(Iterable<FaultConfig> values) {
    final additions = values.toList(growable: false);

    if (additions.isEmpty) {
      return this;
    }

    return copyWith(faults: <FaultConfig>[...faults, ...additions]);
  }

  /// Replaces all faults in the scenario.
  FaultScenario replaceFaults(Iterable<FaultConfig> values) {
    return copyWith(faults: values.toList(growable: false));
  }

  /// Removes a fault by index.
  FaultScenario removeFaultAt(int index) {
    if (index < 0 || index >= faults.length) {
      throw RangeError.index(index, faults, 'index');
    }

    final nextFaults = <FaultConfig>[...faults]..removeAt(index);

    return copyWith(faults: nextFaults);
  }

  /// Removes the first matching fault.
  FaultScenario removeFault(FaultConfig fault) {
    final index = faults.indexOf(fault);

    if (index < 0) {
      return this;
    }

    return removeFaultAt(index);
  }

  /// Removes all faults.
  FaultScenario clearFaults() {
    if (faults.isEmpty) {
      return this;
    }

    return copyWith(faults: const <FaultConfig>[]);
  }

  /// Sets the maximum number of runs.
  ///
  /// Passing `null` removes the limit.
  FaultScenario withMaxRuns(int? value) {
    if (value != null && value <= 0) {
      throw ArgumentError.value(value, 'value', 'maxRuns must be greater than 0.');
    }

    return FaultScenario(
      id: id,
      name: name,
      faults: faults,
      enabled: enabled,
      repeat: repeat,
      maxRuns: value,
      description: description,
      metadata: metadata,
    );
  }

  /// Removes the maximum run limit.
  FaultScenario withoutMaxRuns() {
    return withMaxRuns(null);
  }

  /// Enables single-run execution.
  FaultScenario asSingleRun() {
    return copyWith(repeat: false);
  }

  /// Enables repeating execution.
  FaultScenario asRepeating() {
    return copyWith(repeat: true);
  }

  /// Changes the description.
  ///
  /// Passing `null` clears the description.
  FaultScenario withDescription(String? value) {
    final normalized = value?.trim();

    return FaultScenario(
      id: id,
      name: name,
      faults: faults,
      enabled: enabled,
      repeat: repeat,
      maxRuns: maxRuns,
      description: normalized,
      metadata: metadata,
    );
  }

  /// Removes the description.
  FaultScenario withoutDescription() {
    return withDescription(null);
  }

  /// Adds or replaces a metadata entry.
  FaultScenario withMetadata(String key, Object? value) {
    final normalizedKey = key.trim();

    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Metadata key must not be empty.');
    }

    final nextMetadata = <String, Object?>{...metadata, normalizedKey: value};

    return copyWith(metadata: nextMetadata);
  }

  /// Adds multiple metadata entries.
  FaultScenario withMetadataMap(Map<String, Object?> values) {
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
  FaultScenario withoutMetadata(String key) {
    final normalizedKey = key.trim();

    if (!metadata.containsKey(normalizedKey)) {
      return this;
    }

    final nextMetadata = <String, Object?>{...metadata}..remove(normalizedKey);

    return copyWith(metadata: nextMetadata);
  }

  /// Clears all metadata.
  FaultScenario clearMetadata() {
    if (metadata.isEmpty) {
      return this;
    }

    return copyWith(metadata: const <String, Object?>{});
  }

  /// Validates this scenario.
  List<String> validate() {
    final errors = <String>[];

    if (id.trim().isEmpty) {
      errors.add('id must not be empty.');
    }

    if (name.trim().isEmpty) {
      errors.add('name must not be empty.');
    }

    if (maxRuns != null && maxRuns! <= 0) {
      errors.add('maxRuns must be greater than 0.');
    }

    for (var index = 0; index < faults.length; index++) {
      final faultErrors = faults[index].validate();

      for (final error in faultErrors) {
        errors.add('fault[$index]: $error');
      }
    }

    if (repeat && maxRuns == 0) {
      errors.add('A repeating scenario cannot have maxRuns equal to 0.');
    }

    return List<String>.unmodifiable(errors);
  }

  /// Validates the scenario and throws if invalid.
  void validateOrThrow() {
    final errors = validate();

    if (errors.isEmpty) {
      return;
    }

    throw StateError('Invalid FaultScenario: ${errors.join(' ')}');
  }

  void _validateConstructor() {
    if (maxRuns != null && maxRuns! <= 0) {
      throw ArgumentError.value(maxRuns, 'maxRuns', 'maxRuns must be greater than 0.');
    }
  }

  static String _requireText(String value, String name) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty.');
    }

    return normalized;
  }

  @override
  List<Object?> get props => <Object?>[id, name, faults, enabled, repeat, maxRuns, description, metadata];

  @override
  String toString() {
    return 'FaultScenario('
        'id: $id, '
        'name: $name, '
        'faultCount: ${faults.length}, '
        'enabled: $enabled, '
        'repeat: $repeat, '
        'maxRuns: $maxRuns, '
        'description: $description, '
        'metadata: $metadata'
        ')';
  }
}
