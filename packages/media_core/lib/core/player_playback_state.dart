import 'package:freezed_annotation/freezed_annotation.dart';

/// The semantic playback state of a player.
///
/// This represents what the core believes the player is doing. It is not a
/// backend-specific state.
@JsonEnum()
enum PlayerPlaybackState {
  /// No playback is in progress.
  idle,

  /// A media source is being opened.
  opening,

  /// Playback is running.
  playing,

  /// Playback is paused.
  paused,

  /// Playback is stalled while media is being loaded.
  buffering,

  /// The playback position is being changed.
  seeking,

  /// Playback is being stopped.
  stopping,

  /// Playback has stopped.
  stopped,

  /// Playback reached the end of the media.
  completed,

  /// Playback failed.
  error,
}
