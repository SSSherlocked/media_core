import 'package:equatable/equatable.dart';
import 'package:media_core/audio/audio_volume.dart' show AudioVolume;

/// Immutable value object describing whether audio output is muted.
///
/// Mute is intentionally modeled independently from [AudioVolume]. Muting
/// should not destroy or overwrite the user's volume level, allowing the
/// previous volume to be restored when mute is disabled.
final class AudioMute extends Equatable {
  /// Creates a mute value.
  const AudioMute({required this.value});

  /// Creates an unmuted value.
  const AudioMute.unmuted() : value = false;

  /// Creates a muted value.
  const AudioMute.muted() : value = true;

  /// Whether audio output is muted.
  final bool value;

  /// Whether audio is muted.
  bool get isMuted => value;

  /// Whether audio is not muted.
  bool get isUnmuted => !value;

  /// Creates a muted value.
  AudioMute mute() => const AudioMute.muted();

  /// Creates an unmuted value.
  AudioMute unmute() => const AudioMute.unmuted();

  /// Toggles the current mute state.
  AudioMute toggle() => AudioMute(value: !value);

  /// Creates a copy with an optional new mute value.
  AudioMute copyWith({bool? value}) {
    return AudioMute(value: value ?? this.value);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => 'AudioMute($value)';
}
