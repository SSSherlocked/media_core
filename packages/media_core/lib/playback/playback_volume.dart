import 'package:equatable/equatable.dart';

/// Playback volume value object.
///
/// Represents playback volume level.
///
/// Range:
///
/// 0.0 -> silent
/// 1.0 -> maximum
///
/// Does not:
///
/// - control audio hardware
/// - manage audio focus
/// - change playback state
final class PlaybackVolume extends Equatable {
  /// Creates a level of [value], muted or not as stated.
  ///
  /// [value] and [muted] stay independent on purpose: silence encoded as
  /// `value: 0` could not be unmuted back to where the listener was.
  const PlaybackVolume({required this.value, this.muted = false});

  /// Reads a volume written by [toMap].
  ///
  /// Missing keys mean full volume, unmuted — the level a player starts at.
  factory PlaybackVolume.fromMap(Map<String, dynamic> map) {
    return PlaybackVolume(value: map['value'] as double? ?? 1.0, muted: map['muted'] as bool? ?? false);
  }

  /// Default volume.
  const PlaybackVolume.defaultValue() : value = 1.0, muted = false;

  /// Muted volume.
  const PlaybackVolume.muted() : value = 0.0, muted = true;

  /// Silent volume.
  const PlaybackVolume.silent() : value = 0.0, muted = false;

  /// Creates volume.
  factory PlaybackVolume.from(double value, {bool muted = false}) {
    return PlaybackVolume(value: value, muted: muted);
  }

  /// Volume value.
  ///
  /// Range:
  ///
  /// 0.0 - 1.0
  final double value;

  /// Whether muted.
  final bool muted;

  /// Minimum volume.
  static const double min = 0;

  /// Maximum volume.
  static const double max = 1;

  /// Whether value is valid.
  bool get isValid {
    return value >= min && value <= max;
  }

  /// Effective volume.
  ///
  /// Returns zero when muted.
  double get effectiveValue {
    if (muted) {
      return 0;
    }

    return normalized;
  }

  /// Normalized value.
  double get normalized {
    if (value < min) {
      return min;
    }

    if (value > max) {
      return max;
    }

    return value;
  }

  /// Whether silent.
  bool get isSilent {
    return effectiveValue == 0;
  }

  /// Whether audible.
  bool get isAudible {
    return effectiveValue > 0;
  }

  /// Creates muted volume.
  PlaybackVolume mute() {
    return PlaybackVolume(value: value, muted: true);
  }

  /// Creates unmuted volume.
  PlaybackVolume unmute() {
    return PlaybackVolume(value: value);
  }

  /// Creates copy.
  PlaybackVolume copyWith({double? value, bool? muted}) {
    return PlaybackVolume(value: value ?? this.value, muted: muted ?? this.muted);
  }

  /// The `fromMap()` form: level and mute flag stored apart, so a saved muted
  /// volume restores the level it was muted at.
  Map<String, dynamic> toMap() {
    return {'value': value, 'muted': muted};
  }

  @override
  List<Object?> get props => [value, muted];

  @override
  String toString() {
    return 'PlaybackVolume('
        'value=$value, '
        'muted=$muted)';
  }
}
