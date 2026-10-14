import 'package:equatable/equatable.dart';

/// Playback duration value object.
///
/// Represents total media duration.
///
/// Does not:
///
/// - control playback
/// - perform seeking
/// - calculate renderer layout
final class PlaybackDuration extends Equatable {
  /// Creates a duration of [value].
  const PlaybackDuration({required this.value});

  /// Reads a duration written by [toMap].
  ///
  /// A missing `milliseconds` becomes [Duration.zero], which [isUnknown] then
  /// reports — the same value an engine gives for a length it does not know yet.
  factory PlaybackDuration.fromMap(Map<String, dynamic> map) {
    return PlaybackDuration.fromMilliseconds(map['milliseconds'] as int? ?? 0);
  }

  /// Zero duration.
  const PlaybackDuration.zero() : value = Duration.zero;

  /// Creates from milliseconds.
  factory PlaybackDuration.fromMilliseconds(int milliseconds) {
    return PlaybackDuration(value: Duration(milliseconds: milliseconds));
  }

  /// Total duration.
  final Duration value;

  /// Milliseconds.
  int get milliseconds => value.inMilliseconds;

  /// Seconds.
  double get seconds => value.inMilliseconds / 1000;

  /// Whether duration exists.
  bool get isValid => milliseconds > 0;

  /// Whether unknown duration.
  bool get isUnknown => value == Duration.zero;

  /// Compare.
  bool operator <(PlaybackDuration other) {
    return value < other.value;
  }

  /// Whether this duration is longer than [other].
  bool operator >(PlaybackDuration other) {
    return value > other.value;
  }

  /// Creates remaining duration.
  Duration remaining(Duration position) {
    final result = value - position;

    if (result < Duration.zero) {
      return Duration.zero;
    }

    return result;
  }

  /// Calculates progress.
  double progress(Duration position) {
    if (!isValid) {
      return 0;
    }

    final result = position.inMilliseconds / milliseconds;

    if (result < 0) {
      return 0;
    }

    if (result > 1) {
      return 1;
    }

    return result;
  }

  /// The `fromMap()` form: duration as whole milliseconds, so any sub-millisecond
  /// remainder is dropped.
  Map<String, dynamic> toMap() {
    return {'milliseconds': milliseconds};
  }

  @override
  List<Object?> get props => [value];

  @override
  String toString() {
    return 'PlaybackDuration('
        '${value.inMilliseconds}ms)';
  }
}
