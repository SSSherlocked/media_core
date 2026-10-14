import 'package:equatable/equatable.dart';

/// Immutable audio volume value object.
///
/// Volume is represented as a normalized linear value in the inclusive range
/// `0.0..1.0`.
///
/// Keeping normalization inside the core prevents platform implementations
/// from having to agree on different ranges such as `0..100`, percentages,
/// decibels, or platform-specific integer values.
final class AudioVolume extends Equatable {
  /// Creates a normalized audio volume.
  ///
  /// The value must be between `0.0` and `1.0`, inclusive.
  const AudioVolume(this.value)
    : assert(value >= 0.0 && value <= 1.0, 'AudioVolume.value must be between 0.0 and 1.0, got $value.');

  /// Creates a muted volume value.
  const AudioVolume.zero() : value = 0.0;

  /// Creates a maximum volume value.
  const AudioVolume.max() : value = 1.0;

  /// Creates a volume from a percentage in the range `0..100`.
  ///
  /// Values outside that range are clamped.
  factory AudioVolume.percent(double percent) {
    return AudioVolume((percent / 100.0).clamp(0.0, 1.0));
  }

  /// Predefined volume level representing silence.
  static const AudioVolume muted = AudioVolume(0);

  /// Predefined volume level at 25% of full scale.
  static const AudioVolume quiet = AudioVolume(0.25);

  /// Predefined volume level at 50% of full scale.
  static const AudioVolume medium = AudioVolume(0.5);

  /// Predefined volume level at 75% of full scale.
  static const AudioVolume loud = AudioVolume(0.75);

  /// Predefined volume level at full scale.
  static const AudioVolume full = AudioVolume(1);

  /// Normalized volume in the range `0.0..1.0`.
  final double value;

  /// Volume represented as a percentage in the range `0..100`.
  double get percent => value * 100.0;

  /// Whether the volume is completely silent.
  bool get isZero => value == 0.0;

  /// Whether the volume is at maximum.
  bool get isFull => value == 1.0;

  /// Whether the volume is audible.
  bool get isAudible => value > 0.0;

  /// Returns a volume with [value] clamped to the valid range.
  AudioVolume clamped() {
    return AudioVolume(value.clamp(0.0, 1.0));
  }

  /// Creates a copy with a new normalized value.
  AudioVolume copyWith({double? value}) {
    final next = value ?? this.value;
    return AudioVolume(next.clamp(0.0, 1.0));
  }

  /// Converts this value into a normalized platform-independent scalar.
  double toDouble() => value;

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => 'AudioVolume($value)';
}
