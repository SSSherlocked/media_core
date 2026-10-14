import 'package:media_core/core/player_core_state.dart' show PlayerCoreState;

/// Semantic status of a player.
///
/// [PlayerStatus] is a derived, high-level view of [PlayerCoreState].
///
/// It does not own or duplicate runtime state.
enum PlayerStatus {
  /// The player has not been initialized.
  idle,

  /// The player is opening a media source.
  opening,

  /// The player is ready for normal control.
  ready,

  /// The player is currently playing.
  playing,

  /// Playback is paused.
  paused,

  /// The player is buffering.
  buffering,

  /// The player is seeking.
  seeking,

  /// The player is stopping.
  stopping,

  /// Playback has stopped.
  stopped,

  /// Playback reached the end of the media.
  completed,

  /// The player is being disposed.
  disposing,

  /// The player has been disposed.
  disposed,

  /// The player encountered an error.
  error,
}

/// Extension methods for [PlayerStatus].
extension PlayerStatusX on PlayerStatus {
  /// Whether this status represents active playback.
  bool get isPlaying => this == PlayerStatus.playing;

  /// Whether this status represents paused playback.
  bool get isPaused => this == PlayerStatus.paused;

  /// Whether this status represents buffering.
  bool get isBuffering => this == PlayerStatus.buffering;

  /// Whether this status represents seeking.
  bool get isSeeking => this == PlayerStatus.seeking;

  /// Whether this status represents an opening transition.
  bool get isOpening => this == PlayerStatus.opening;

  /// Whether this status represents a stopping transition.
  bool get isStopping => this == PlayerStatus.stopping;

  /// Whether this status represents a stopped player.
  bool get isStopped => this == PlayerStatus.stopped;

  /// Whether playback has completed.
  bool get isCompleted => this == PlayerStatus.completed;

  /// Whether the player is ready for normal control.
  bool get isReady => this == PlayerStatus.ready;

  /// Whether the player is idle.
  bool get isIdle => this == PlayerStatus.idle;

  /// Whether the player is currently being disposed.
  bool get isDisposing => this == PlayerStatus.disposing;

  /// Whether the player has already been disposed.
  bool get isDisposed => this == PlayerStatus.disposed;

  /// Whether the player is in an error state.
  bool get isError => this == PlayerStatus.error;

  /// Whether the player is actively processing playback or a transition.
  bool get isActive {
    return this == PlayerStatus.opening ||
        this == PlayerStatus.playing ||
        this == PlayerStatus.buffering ||
        this == PlayerStatus.seeking ||
        this == PlayerStatus.stopping;
  }

  /// Whether the player is performing a transition.
  bool get isTransitioning {
    return this == PlayerStatus.opening ||
        this == PlayerStatus.seeking ||
        this == PlayerStatus.stopping ||
        this == PlayerStatus.disposing;
  }

  /// Whether the player can normally accept playback commands.
  ///
  /// This describes the semantic status only. Whether a specific command is
  /// actually valid also depends on the current source and player
  /// capabilities.
  bool get canControl {
    return this == PlayerStatus.ready ||
        this == PlayerStatus.playing ||
        this == PlayerStatus.paused ||
        this == PlayerStatus.buffering ||
        this == PlayerStatus.seeking ||
        this == PlayerStatus.completed ||
        this == PlayerStatus.stopped;
  }

  /// Whether this status represents a terminal player state.
  bool get isTerminal => this == PlayerStatus.disposed;

  /// Whether this status represents a failure.
  bool get isFailure => this == PlayerStatus.error;

  /// Returns a stable string representation of the status.
  String get value => name;
}
