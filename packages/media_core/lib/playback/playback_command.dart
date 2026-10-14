import 'package:equatable/equatable.dart';
import 'package:media_core/playback/buffer_range.dart';

/// Playback command.
///
/// Represents a playback state mutation.
///
/// Commands are consumed by:
///
/// - PlaybackController
///
/// Does not:
///
/// - call player backend
/// - perform async operations
/// - control platform APIs
sealed class PlaybackCommand extends Equatable {
  const PlaybackCommand();

  /// Idle state.
  const factory PlaybackCommand.idle() = PlaybackCommandIdle;

  /// Start playback.
  const factory PlaybackCommand.play() = PlaybackCommandPlay;

  /// Pause playback.
  const factory PlaybackCommand.pause() = PlaybackCommandPause;

  /// Stop playback.
  const factory PlaybackCommand.stop() = PlaybackCommandStop;

  /// Buffering state.
  ///
  /// Reports a condition rather than an intention: applying it updates the
  /// transport state's buffering flag and leaves the play/pause command alone.
  const factory PlaybackCommand.buffering({required bool value}) = PlaybackCommandBuffering;

  /// Update position.
  const factory PlaybackCommand.position(Duration position) = PlaybackCommandPosition;

  /// Update duration.
  const factory PlaybackCommand.duration(Duration duration) = PlaybackCommandDuration;

  /// Seek position.
  const factory PlaybackCommand.seek(Duration position) = PlaybackCommandSeek;

  /// Update volume.
  const factory PlaybackCommand.volume(double volume) = PlaybackCommandVolume;

  /// Update playback speed.
  const factory PlaybackCommand.rate(double rate) = PlaybackCommandRate;

  /// Buffered stretches reported by the engine.
  ///
  /// A state update like [PlaybackCommand.position], not an
  /// intention: the transport command is untouched, because the
  /// player's playing/paused state is exactly what it was when the
  /// buffer advanced.
  const factory PlaybackCommand.buffered(List<BufferRange> ranges) = PlaybackCommandBuffered;

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  /// Whether the transport is at rest — the state before any command.
  bool get isIdle => this is PlaybackCommandIdle;

  /// Whether this is the reserved loading placeholder command.
  bool get isLoading => this is PlaybackCommandLoading;

  /// Whether this command puts the transport into the playing state.
  bool get isPlaying => this is PlaybackCommandPlay;

  /// Whether this command suspends the transport without leaving the session.
  bool get isPaused => this is PlaybackCommandPause;

  /// Whether this command tears the transport down and rewinds to zero.
  bool get isStopped => this is PlaybackCommandStop;

  /// Whether this command reports the engine running short of data.
  ///
  /// A buffering command updates the state's buffering flag instead of becoming
  /// the state's current command, so this is true only while the command itself
  /// is being handled — never for a state read back later.
  bool get isBuffering => this is PlaybackCommandBuffering;

  /// Whether command represents a completed state.
  ///
  /// Commands themselves are not async operations.
  /// This exists only for state compatibility.
  bool get isCompleted => false;

  /// Whether command is timeline-related.
  bool get isTimeline =>
      this is PlaybackCommandPosition || this is PlaybackCommandDuration || this is PlaybackCommandSeek;

  /// Whether command is a value change.
  bool get isValueChange => this is PlaybackCommandVolume || this is PlaybackCommandRate;

  @override
  List<Object?> get props => [];
}

/// Idle command.
final class PlaybackCommandIdle extends PlaybackCommand {
  /// Creates the command a transport rests on before any play, and returns to
  /// on a reset that keeps position and duration.
  const PlaybackCommandIdle();

  @override
  String toString() => 'PlaybackCommandIdle';
}

/// Loading command.
///
/// Reserved for future async loading state.
final class PlaybackCommandLoading extends PlaybackCommand {
  /// Creates the placeholder that marks the transport as loading; no engine
  /// sends one yet, which is why [PlaybackCommand.isLoading] is not a state any
  /// consumer should branch on.
  const PlaybackCommandLoading();

  @override
  String toString() => 'PlaybackCommandLoading';
}

/// Play command.
final class PlaybackCommandPlay extends PlaybackCommand {
  /// Creates the command that starts the transport and marks the session
  /// initialized.
  const PlaybackCommandPlay();

  @override
  String toString() => 'PlaybackCommandPlay';
}

/// Pause command.
final class PlaybackCommandPause extends PlaybackCommand {
  /// Creates the command that suspends the transport while keeping the session,
  /// position and buffer.
  const PlaybackCommandPause();

  @override
  String toString() => 'PlaybackCommandPause';
}

/// Stop command.
final class PlaybackCommandStop extends PlaybackCommand {
  /// Creates the command that leaves the session and rewinds the position to
  /// zero; duration and buffer are kept as the engine last reported them.
  const PlaybackCommandStop();

  @override
  String toString() => 'PlaybackCommandStop';
}

/// Buffering command.
final class PlaybackCommandBuffering extends PlaybackCommand {
  /// Creates a report that the engine is now short of data ([value] true) or
  /// has caught up again.
  const PlaybackCommandBuffering({required this.value});

  /// The reported buffering condition.
  ///
  /// Stored on the transport state rather than as the current command, so a
  /// `false` report does not erase the fact that the player is playing.
  final bool value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'PlaybackCommandBuffering($value)';
}

/// Position update command.
final class PlaybackCommandPosition extends PlaybackCommand {
  /// Creates a report of where the engine has played to.
  const PlaybackCommandPosition(this.position);

  /// Media time the engine reports having reached.
  ///
  /// A report, not an instruction: a seek moves the position too, and the
  /// engine's own ticking does the rest.
  final Duration position;

  @override
  List<Object?> get props => [position];
}

/// Duration update command.
final class PlaybackCommandDuration extends PlaybackCommand {
  /// Creates a report of the total media duration.
  const PlaybackCommandDuration(this.duration);

  /// Total media time, or [Duration.zero] while the stream is still unknown.
  final Duration duration;

  @override
  List<Object?> get props => [duration];
}

/// Seek command.
final class PlaybackCommandSeek extends PlaybackCommand {
  /// Creates the instruction to move to [position].
  const PlaybackCommandSeek(this.position);

  /// Media time the transport should move to.
  ///
  /// The state mirror is updated immediately; actually repositioning the engine
  /// is the adapter's job, and commands never touch a backend.
  final Duration position;

  @override
  List<Object?> get props => [position];
}

/// Volume command.
final class PlaybackCommandVolume extends PlaybackCommand {
  /// Creates the instruction to set volume to [volume].
  const PlaybackCommandVolume(this.volume);

  /// Target volume, `0.0` (silent) to `1.0` (unattenuated).
  final double volume;

  @override
  List<Object?> get props => [volume];
}

/// Rate command.
final class PlaybackCommandRate extends PlaybackCommand {
  /// Creates the instruction to set playback speed to [rate].
  const PlaybackCommandRate(this.rate);

  /// Target speed multiplier, where `1.0` is normal speed.
  final double rate;

  @override
  List<Object?> get props => [rate];
}

/// Buffered stretches reported by the engine.
final class PlaybackCommandBuffered extends PlaybackCommand {
  /// Creates a buffer report from the stretches as the engine stated them.
  const PlaybackCommandBuffered(this.ranges);

  /// Buffered stretches as reported.
  final List<BufferRange> ranges;

  @override
  List<Object?> get props => [ranges];
}
