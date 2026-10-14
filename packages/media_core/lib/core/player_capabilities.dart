import 'package:equatable/equatable.dart';

/// Describes the operations supported by a player implementation.
///
/// [PlayerCapabilities] represents what a player implementation can do,
/// rather than the capabilities of the currently loaded media.
///
/// This is a static capability description and must not contain runtime
/// playback state.
final class PlayerCapabilities extends Equatable {
  /// Creates a capability set, defaulting to the operations every player is
  /// expected to support.
  const PlayerCapabilities({
    this.play = true,
    this.pause = true,
    this.stop = true,
    this.seek = true,
    this.setVolume = true,
    this.setPlaybackSpeed = true,
    this.setLooping = true,
    this.setMuted = true,
    this.fullscreen = false,
    this.pictureInPicture = false,
    this.backgroundPlayback = false,
    this.frameStep = false,
    this.snapshot = false,
  });

  /// Whether the player can start or resume playback.
  final bool play;

  /// Whether the player can pause playback.
  final bool pause;

  /// Whether the player can stop playback.
  final bool stop;

  /// Whether the player supports seeking.
  final bool seek;

  /// Whether the player can change volume.
  final bool setVolume;

  /// Whether the player can change playback speed.
  final bool setPlaybackSpeed;

  /// Whether the player can enable or disable looping.
  final bool setLooping;

  /// Whether the player can mute or unmute audio.
  final bool setMuted;

  /// Whether the player supports fullscreen presentation.
  final bool fullscreen;

  /// Whether the player supports picture-in-picture.
  final bool pictureInPicture;

  /// Whether the player can continue playback while the application is
  /// backgrounded.
  final bool backgroundPlayback;

  /// Whether the player supports stepping between video frames.
  final bool frameStep;

  /// Whether the player can capture a video frame.
  final bool snapshot;

  /// A capability set with no supported operations.
  static const PlayerCapabilities none = PlayerCapabilities(
    play: false,
    pause: false,
    stop: false,
    seek: false,
    setVolume: false,
    setPlaybackSpeed: false,
    setLooping: false,
    setMuted: false,
  );

  /// A capability set with all player operations enabled.
  static const PlayerCapabilities full = PlayerCapabilities(
    fullscreen: true,
    pictureInPicture: true,
    backgroundPlayback: true,
    frameStep: true,
    snapshot: true,
  );

  /// A minimal capability set for basic playback control.
  static const PlayerCapabilities basic = PlayerCapabilities();

  /// Creates a copy with the specified capabilities replaced.
  PlayerCapabilities copyWith({
    bool? play,
    bool? pause,
    bool? stop,
    bool? seek,
    bool? setVolume,
    bool? setPlaybackSpeed,
    bool? setLooping,
    bool? setMuted,
    bool? fullscreen,
    bool? pictureInPicture,
    bool? backgroundPlayback,
    bool? frameStep,
    bool? snapshot,
  }) {
    return PlayerCapabilities(
      play: play ?? this.play,
      pause: pause ?? this.pause,
      stop: stop ?? this.stop,
      seek: seek ?? this.seek,
      setVolume: setVolume ?? this.setVolume,
      setPlaybackSpeed: setPlaybackSpeed ?? this.setPlaybackSpeed,
      setLooping: setLooping ?? this.setLooping,
      setMuted: setMuted ?? this.setMuted,
      fullscreen: fullscreen ?? this.fullscreen,
      pictureInPicture: pictureInPicture ?? this.pictureInPicture,
      backgroundPlayback: backgroundPlayback ?? this.backgroundPlayback,
      frameStep: frameStep ?? this.frameStep,
      snapshot: snapshot ?? this.snapshot,
    );
  }

  /// Returns whether this capability set supports every operation required
  /// by [other].
  bool supports(PlayerCapabilities other) {
    return (!other.play || play) &&
        (!other.pause || pause) &&
        (!other.stop || stop) &&
        (!other.seek || seek) &&
        (!other.setVolume || setVolume) &&
        (!other.setPlaybackSpeed || setPlaybackSpeed) &&
        (!other.setLooping || setLooping) &&
        (!other.setMuted || setMuted) &&
        (!other.fullscreen || fullscreen) &&
        (!other.pictureInPicture || pictureInPicture) &&
        (!other.backgroundPlayback || backgroundPlayback) &&
        (!other.frameStep || frameStep) &&
        (!other.snapshot || snapshot);
  }

  @override
  List<Object?> get props => [
    play,
    pause,
    stop,
    seek,
    setVolume,
    setPlaybackSpeed,
    setLooping,
    setMuted,
    fullscreen,
    pictureInPicture,
    backgroundPlayback,
    frameStep,
    snapshot,
  ];

  @override
  String toString() {
    return 'PlayerCapabilities('
        'play: $play, '
        'pause: $pause, '
        'stop: $stop, '
        'seek: $seek, '
        'setVolume: $setVolume, '
        'setPlaybackSpeed: $setPlaybackSpeed, '
        'setLooping: $setLooping, '
        'setMuted: $setMuted, '
        'fullscreen: $fullscreen, '
        'pictureInPicture: $pictureInPicture, '
        'backgroundPlayback: $backgroundPlayback, '
        'frameStep: $frameStep, '
        'snapshot: $snapshot'
        ')';
  }
}
