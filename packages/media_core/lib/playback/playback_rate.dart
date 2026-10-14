import 'package:equatable/equatable.dart';

/// Playback speed value object.
///
/// Represents playback speed multiplier.
///
/// Examples:
///
/// 0.5  -> half speed
/// 1.0  -> normal speed
/// 2.0  -> double speed
///
/// Does not:
///
/// - control player backend
/// - change playback state
final class PlaybackRate extends Equatable {
  /// Creates a speed multiplier of [value].
  ///
  /// The value is kept as given even outside [min] to [max]; [normalized] is
  /// where clamping happens, so [isValid] can still report that a caller asked
  /// for a speed the transport will not honor.
  const PlaybackRate({required this.value});

  /// Reads a rate written by [toMap].
  ///
  /// A missing `value` means normal speed: a rate that could not be read must
  /// not quietly change the pace of the video.
  factory PlaybackRate.fromMap(Map<String, dynamic> map) {
    return PlaybackRate(value: map['value'] as double? ?? 1.0);
  }

  /// Normal playback speed.
  const PlaybackRate.normal() : value = 1.0;

  /// Slow playback.
  const PlaybackRate.slow() : value = 0.5;

  /// Fast playback.
  const PlaybackRate.fast() : value = 2.0;

  /// Creates from double.
  factory PlaybackRate.from(double value) {
    return PlaybackRate(value: value);
  }

  /// Speed multiplier.
  final double value;

  /// Minimum supported rate.
  static const double min = 0.25;

  /// Maximum supported rate.
  static const double max = 4;

  /// Whether rate is valid.
  bool get isValid {
    return value >= min && value <= max;
  }

  /// Whether normal speed.
  bool get isNormal {
    return value == 1.0;
  }

  /// Whether slower than normal.
  bool get isSlow {
    return value < 1.0;
  }

  /// Whether faster than normal.
  bool get isFast {
    return value > 1.0;
  }

  /// Safe normalized value.
  double get normalized {
    if (value < min) {
      return min;
    }

    if (value > max) {
      return max;
    }

    return value;
  }

  /// Creates copy.
  PlaybackRate copyWith(double value) {
    return PlaybackRate(value: value);
  }

  /// The `fromMap()` form: the multiplier as a plain double.
  Map<String, dynamic> toMap() {
    return {'value': value};
  }

  @override
  List<Object?> get props => [value];

  @override
  String toString() {
    return 'PlaybackRate(${value}x)';
  }
}
