import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/core/player_lifecycle_state.dart';
import 'package:media_core/core/player_playback_state.dart';

part 'player_core_state.freezed.dart';
part 'player_core_state.g.dart';

/// Represents the immutable semantic runtime state of a player.
///
/// [PlayerCoreState] belongs to the core and describes only the fundamental
/// lifecycle, source, output, and playback state of a player.
///
/// Backend-specific state belongs to the adapter layer.
/// Presentation state belongs to the presentation layer.
/// Recording state belongs to the recording layer.
/// Recovery and fallback state belong to their respective layers.
///
/// Lifecycle and playback are represented by mutually exclusive enums rather
/// than collections of independent boolean flags.
@freezed
abstract class PlayerCoreState with _$PlayerCoreState {
  /// Creates an immutable player state.
  const factory PlayerCoreState({
    /// Current player lifecycle state.
    @Default(PlayerLifecycleState.idle) PlayerLifecycleState lifecycle,

    /// Current semantic playback state.
    @Default(PlayerPlaybackState.idle) PlayerPlaybackState playback,

    /// Whether a media source is currently associated with the player.
    @Default(false) bool hasSource,

    /// Whether audio output is enabled.
    @Default(false) bool audioEnabled,

    /// Whether video output is enabled.
    @Default(false) bool videoEnabled,

    /// Whether subtitle output is enabled.
    @Default(false) bool subtitlesEnabled,

    /// Whether audio output is muted.
    @Default(false) bool muted,
  }) = _PlayerState;

  /// Creates a player state from JSON.
  factory PlayerCoreState.fromJson(Map<String, Object?> json) => _$PlayerStateFromJson(json);

  const PlayerCoreState._();

  /// The default state of a newly created player.
  static const PlayerCoreState idle = PlayerCoreState();

  /// Whether the player has completed initialization and is ready for use.
  bool get initialized {
    return lifecycle == PlayerLifecycleState.ready;
  }

  /// Whether the player is currently opening a source.
  bool get opening {
    return playback == PlayerPlaybackState.opening;
  }

  /// Whether the player is currently playing.
  bool get playing {
    return playback == PlayerPlaybackState.playing;
  }

  /// Whether playback is currently paused.
  bool get paused {
    return playback == PlayerPlaybackState.paused;
  }

  /// Whether the player is currently buffering.
  bool get buffering {
    return playback == PlayerPlaybackState.buffering;
  }

  /// Whether the player is currently seeking.
  bool get seeking {
    return playback == PlayerPlaybackState.seeking;
  }

  /// Whether the player is currently stopping.
  bool get stopping {
    return playback == PlayerPlaybackState.stopping;
  }

  /// Whether the player has stopped playback.
  bool get stopped {
    return playback == PlayerPlaybackState.stopped;
  }

  /// Whether playback reached the end of the current media.
  bool get completed {
    return playback == PlayerPlaybackState.completed;
  }

  /// Whether the player is currently in an error state.
  bool get hasError {
    return playback == PlayerPlaybackState.error;
  }

  /// Whether the player is ready for normal playback operations.
  ///
  /// Opening, stopping, and error states are not considered ready.
  bool get ready {
    return lifecycle == PlayerLifecycleState.ready &&
        playback != PlayerPlaybackState.opening &&
        playback != PlayerPlaybackState.stopping &&
        playback != PlayerPlaybackState.error;
  }

  /// Whether the player is being disposed.
  bool get disposing {
    return lifecycle == PlayerLifecycleState.disposing;
  }

  /// Whether the player has been disposed.
  bool get disposed {
    return lifecycle == PlayerLifecycleState.disposed;
  }

  /// Whether the player is completely idle.
  bool get isIdle {
    return lifecycle == PlayerLifecycleState.idle && playback == PlayerPlaybackState.idle && !hasSource;
  }

  /// Whether the player is actively processing playback or a transition.
  bool get isActive {
    return opening || playing || buffering || seeking || stopping;
  }

  /// Whether playback is currently active.
  ///
  /// Opening and stopping are excluded because they are playback transitions,
  /// not active playback.
  bool get isPlaybackActive {
    return playing || buffering || seeking;
  }

  /// Whether the player is currently transitioning.
  bool get isTransitioning {
    return opening || seeking || stopping || disposing;
  }

  /// Whether the player has reached a terminal lifecycle state.
  bool get isTerminal {
    return disposed;
  }

  /// Whether the player can accept normal control commands.
  bool get canControl {
    return lifecycle == PlayerLifecycleState.ready && !opening && !stopping && !hasError;
  }

  /// Whether playback can currently be started.
  bool get canPlay {
    return canControl && hasSource && !playing && !buffering && !seeking;
  }

  /// Whether playback can currently be paused.
  bool get canPause {
    return canControl && playing;
  }

  /// Whether seeking is currently possible.
  bool get canSeek {
    return canControl && hasSource;
  }

  /// Whether the player can currently be stopped.
  bool get canStop {
    return lifecycle == PlayerLifecycleState.ready && (playing || paused || buffering || seeking || opening);
  }

  /// Whether the player has an audio output.
  bool get hasAudioOutput {
    return audioEnabled;
  }

  /// Whether the player has a video output.
  bool get hasVideoOutput {
    return videoEnabled;
  }

  /// Whether the current configuration represents audio-only playback.
  bool get isAudioOnly {
    return audioEnabled && !videoEnabled;
  }

  /// Whether the current configuration represents video-only playback.
  bool get isVideoOnly {
    return videoEnabled && !audioEnabled;
  }

  /// Whether both audio and video outputs are enabled.
  bool get isAudioVideo {
    return audioEnabled && videoEnabled;
  }

  /// Whether the state contains no active error.
  bool get isClean {
    return !hasError && !disposed;
  }

  /// Marks the player as initializing.
  PlayerCoreState initializingState() {
    return copyWith(lifecycle: PlayerLifecycleState.initializing, playback: PlayerPlaybackState.idle);
  }

  /// Marks the player as opening a source.
  ///
  /// The player must already be initialized before opening a source.
  PlayerCoreState openingState() {
    return copyWith(lifecycle: PlayerLifecycleState.ready, playback: PlayerPlaybackState.opening);
  }

  /// Marks the player as ready without starting playback.
  PlayerCoreState readyState() {
    return copyWith(lifecycle: PlayerLifecycleState.ready, playback: PlayerPlaybackState.idle);
  }

  /// Marks the player as playing.
  PlayerCoreState playingState() {
    return copyWith(lifecycle: PlayerLifecycleState.ready, playback: PlayerPlaybackState.playing);
  }

  /// Marks the player as paused.
  PlayerCoreState pausedState() {
    return copyWith(lifecycle: PlayerLifecycleState.ready, playback: PlayerPlaybackState.paused);
  }

  /// Marks the player as buffering.
  PlayerCoreState bufferingState() {
    return copyWith(lifecycle: PlayerLifecycleState.ready, playback: PlayerPlaybackState.buffering);
  }

  /// Marks the player as seeking.
  PlayerCoreState seekingState() {
    return copyWith(lifecycle: PlayerLifecycleState.ready, playback: PlayerPlaybackState.seeking);
  }

  /// Marks the player as stopping.
  PlayerCoreState stoppingState() {
    return copyWith(lifecycle: PlayerLifecycleState.ready, playback: PlayerPlaybackState.stopping);
  }

  /// Marks the player as stopped.
  PlayerCoreState stoppedState() {
    return copyWith(lifecycle: PlayerLifecycleState.ready, playback: PlayerPlaybackState.stopped);
  }

  /// Marks playback as completed.
  PlayerCoreState completedState() {
    return copyWith(lifecycle: PlayerLifecycleState.ready, playback: PlayerPlaybackState.completed);
  }

  /// Marks the player as having an error.
  PlayerCoreState errorState() {
    return copyWith(playback: PlayerPlaybackState.error);
  }

  /// Marks the player as disposing.
  PlayerCoreState disposingState() {
    return copyWith(lifecycle: PlayerLifecycleState.disposing, playback: PlayerPlaybackState.stopped);
  }

  /// Marks the player as disposed.
  PlayerCoreState disposedState() {
    return copyWith(
      lifecycle: PlayerLifecycleState.disposed,
      playback: PlayerPlaybackState.stopped,
      hasSource: false,
      audioEnabled: false,
      videoEnabled: false,
      subtitlesEnabled: false,
      muted: false,
    );
  }

  /// Associates or removes a media source.
  PlayerCoreState withSource({required bool value}) {
    if (value) {
      return copyWith(hasSource: true);
    }

    return copyWith(hasSource: false, playback: PlayerPlaybackState.idle);
  }

  /// Returns a state with the requested mute state.
  PlayerCoreState withMuted({required bool value}) {
    return copyWith(muted: value);
  }

  /// Returns a state with audio output enabled or disabled.
  PlayerCoreState withAudioEnabled({required bool value}) {
    return copyWith(audioEnabled: value);
  }

  /// Returns a state with video output enabled or disabled.
  PlayerCoreState withVideoEnabled({required bool value}) {
    return copyWith(videoEnabled: value);
  }

  /// Returns a state with subtitles enabled or disabled.
  PlayerCoreState withSubtitlesEnabled({required bool value}) {
    return copyWith(subtitlesEnabled: value);
  }

  /// Resets playback state while preserving lifecycle and other state.
  PlayerCoreState resetPlayback() {
    return copyWith(playback: PlayerPlaybackState.idle);
  }

  /// Clears the current error state.
  PlayerCoreState clearError() {
    return copyWith(playback: hasError ? PlayerPlaybackState.idle : playback);
  }

  /// Returns a clean state while preserving source and output state.
  PlayerCoreState reset() {
    return copyWith(
      lifecycle: lifecycle == PlayerLifecycleState.disposed ? PlayerLifecycleState.idle : lifecycle,
      playback: PlayerPlaybackState.idle,
    );
  }
}
