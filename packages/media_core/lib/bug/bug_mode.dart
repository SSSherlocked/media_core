import 'package:equatable/equatable.dart';

/// Defines the runtime level of bug / fault-injection behavior.
///
/// [BugMode] is an immutable value object. It describes how aggressively
/// the bug module is allowed to inject faults.
///
/// The built-in modes are:
///
/// - [disabled] - bug injection is completely disabled.
/// - [safe] - only explicitly safe and deterministic faults are allowed.
/// - [normal] - normal development fault injection.
/// - [aggressive] - aggressive fault injection for stress testing.
/// - [chaos] - unrestricted chaos-style fault injection.
///
/// Custom modes are supported for applications that need their own mode
/// vocabulary.
final class BugMode extends Equatable implements Comparable<BugMode> {
  const BugMode._(this.value, this.name);

  /// Creates a custom bug mode.
  ///
  /// Custom modes must have a non-empty value.
  factory BugMode.custom(String value, {String? name}) {
    final normalizedValue = value.trim();

    if (normalizedValue.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Bug mode value must not be empty.');
    }

    final normalizedName = name?.trim();

    return BugMode._(normalizedValue, normalizedName?.isNotEmpty == true ? normalizedName! : normalizedValue);
  }

  /// Creates a bug mode from its serialized value.
  ///
  /// Known built-in values are mapped to their canonical instances.
  /// Unknown values become custom modes.
  factory BugMode.fromValue(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Bug mode value must not be empty.');
    }

    switch (normalized) {
      case 'disabled':
        return disabled;
      case 'safe':
        return safe;
      case 'normal':
        return normal;
      case 'aggressive':
        return aggressive;
      case 'chaos':
        return chaos;
      default:
        return BugMode.custom(normalized);
    }
  }

  /// Creates a bug mode from JSON.
  factory BugMode.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('BugMode JSON value must be a String.');
    }

    return BugMode.fromValue(json);
  }

  /// Bug injection is completely disabled.
  static const BugMode disabled = BugMode._('disabled', 'Disabled');

  /// Only explicitly safe and deterministic faults are allowed.
  static const BugMode safe = BugMode._('safe', 'Safe');

  /// Normal development fault injection.
  static const BugMode normal = BugMode._('normal', 'Normal');

  /// Aggressive fault injection intended for stress testing.
  static const BugMode aggressive = BugMode._('aggressive', 'Aggressive');

  /// Chaos-style fault injection.
  static const BugMode chaos = BugMode._('chaos', 'Chaos');

  /// Attempts to parse a bug mode.
  ///
  /// Returns `null` when [value] is empty or invalid.
  static BugMode? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    try {
      return BugMode.fromValue(value);
    } on Object {
      return null;
    }
  }

  /// Whether [value] is a valid bug mode value.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Whether [value] represents a built-in bug mode.
  static bool isBuiltInValue(String value) {
    switch (value.trim()) {
      case 'disabled':
      case 'safe':
      case 'normal':
      case 'aggressive':
      case 'chaos':
        return true;
      default:
        return false;
    }
  }

  /// All built-in bug modes.
  static const List<BugMode> builtIns = <BugMode>[disabled, safe, normal, aggressive, chaos];

  /// Serialized mode value.
  final String value;

  /// Human-readable mode name.
  final String name;

  /// Alias for [value].
  String get rawValue => value;

  /// Returns the serialized value.
  String get toValue => value;

  /// Returns the serialized JSON value.
  String toJson() => value;

  /// Whether this mode is one of the built-in modes.
  bool get isBuiltIn => isBuiltInValue(value);

  /// Whether this mode is custom.
  bool get isCustom => !isBuiltIn;

  /// Whether this mode disables bug injection.
  bool get isDisabled => value == disabled.value;

  /// Whether this mode uses safe fault injection.
  bool get isSafe => value == safe.value;

  /// Whether this is the normal development mode.
  bool get isNormal => value == normal.value;

  /// Whether this mode enables aggressive fault injection.
  bool get isAggressive => value == aggressive.value;

  /// Whether this mode enables chaos-style fault injection.
  bool get isChaos => value == chaos.value;

  /// Whether fault injection is enabled.
  bool get isEnabled => !isDisabled;

  /// Whether this mode allows deterministic fault injection.
  bool get allowsDeterministicFaults => !isDisabled;

  /// Whether this mode allows potentially disruptive faults.
  bool get allowsDisruptiveFaults => isNormal || isAggressive || isChaos;

  /// Whether this mode allows stress-oriented faults.
  bool get allowsStressFaults => isAggressive || isChaos;

  /// Whether this mode allows chaos-style faults.
  bool get allowsChaosFaults => isChaos;

  /// Returns a copy with optionally changed values.
  ///
  /// An empty [value] is rejected.
  BugMode copyWith({String? value, String? name}) {
    final nextValue = value?.trim() ?? this.value;

    if (nextValue.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Bug mode value must not be empty.');
    }

    final nextName = name?.trim();

    return BugMode._(nextValue, nextName?.isNotEmpty == true ? nextName! : this.name);
  }

  /// Returns whether this mode has the same value as [other].
  bool isSameAs(BugMode other) {
    return value == other.value;
  }

  /// Returns whether this mode has a different value from [other].
  bool isDifferentFrom(BugMode other) {
    return value != other.value;
  }

  /// Returns the built-in mode matching [value], if any.
  static BugMode? builtIn(String value) {
    final normalized = value.trim();

    for (final mode in builtIns) {
      if (mode.value == normalized) {
        return mode;
      }
    }

    return null;
  }

  @override
  int compareTo(BugMode other) {
    return value.compareTo(other.value);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() {
    if (isBuiltIn) {
      return 'BugMode($value)';
    }

    return 'BugMode($value, name: $name)';
  }
}
