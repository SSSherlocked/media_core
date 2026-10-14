import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/playback/playback_buffer.dart';
import 'package:media_core/playback/playback_command.dart';

/// Current playback runtime state.
///
/// Owned by:
///
/// - PlaybackController
///
/// Used by:
///
/// - PlayerIdentity
/// - Renderer
/// - UI
///
/// Does not:
///
/// - control backend
/// - call platform APIs
/// - manage decoder
final class PlayerTransportState extends Equatable {
  /// Creates the transport mirror straight from the fields an engine reports.
  ///
  /// Every field is a statement about what the player is doing now; only
  /// [reduce] moves it forward, and `PlayerTransportState.initial()` is where a
  /// session starts.
  const PlayerTransportState({
    required this.command,
    required this.position,
    required this.duration,
    required this.volume,
    required this.rate,
    required this.initialized,
    required this.updatedAt,
    this.buffering = false,
    this.buffer = const PlaybackBuffer.empty(),
  });

  /// Initial state.
  const PlayerTransportState.initial()
    : command = const PlaybackCommand.idle(),
      position = Duration.zero,
      duration = Duration.zero,
      volume = 1.0,
      rate = 1.0,
      initialized = false,
      updatedAt = null,
      buffering = false,
      buffer = const PlaybackBuffer.empty();

  /// Current playback command/state.
  final PlaybackCommand command;

  /// Current position.
  final Duration position;

  /// Media duration.
  final Duration duration;

  /// Volume 0.0 - 1.0.
  final double volume;

  /// Playback speed.
  final double rate;

  /// Whether playback initialized.
  final bool initialized;

  /// Last state update.
  final DateTime? updatedAt;

  /// Whether the engine is currently short of data.
  ///
  /// A separate field rather than a command: buffering is a *condition* that
  /// happens while playing, so it must not replace the transport command. When
  /// it did, a single `buffering: false` notification left the mirror reading
  /// `isBuffering == true, isPlaying == false, isPaused == false` for the rest
  /// of the session - which silently disabled everything that asks the player
  /// whether it is playing.
  final bool buffering;

  /// What the engine currently reports as buffered.
  ///
  /// The playback mirror of the engine's report, not the cache
  /// layer's inventory: this says what the engine believes it can
  /// play without waiting. An engine that never reports ranges leaves
  /// it empty, which is a fact about the engine — a progress bar that
  /// draws "no ahead fill" instead of guessing.
  final PlaybackBuffer buffer;

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  /// Whether the transport is at rest, before any play command.
  bool get isIdle => command.isIdle;

  /// Whether the transport is in the reserved loading state.
  ///
  /// No engine report produces that command yet, so this reads false.
  bool get isLoading => command.isLoading;

  /// Whether the playhead is meant to be advancing.
  ///
  /// Independent of [isBuffering]: a player that is stalled is still playing,
  /// which is exactly the distinction a controls bar has to get right.
  bool get isPlaying => command.isPlaying;

  /// Whether the user or the app suspended playback without leaving the session.
  bool get isPaused => command.isPaused;

  /// Whether the session has been torn down and the playhead rewound.
  bool get isStopped => command.isStopped;

  /// Whether playback ran to the end of the media.
  ///
  /// Always false: reaching the end is not a command, so a consumer that needs
  /// completion has to compare [position] against [duration] itself.
  bool get isCompleted => command.isCompleted;

  /// Whether the engine is short of data at this moment.
  bool get isBuffering => buffering;

  /// Whether the media length is known.
  ///
  /// A live stream or a not-yet-ready asset reports [Duration.zero], so this is
  /// the test for "can a total be displayed" rather than for "is it nonzero".
  bool get hasDuration => duration > Duration.zero;

  /// Whether the playhead has left the very start.
  bool get hasPosition => position > Duration.zero;

  /// Fraction of the media that has been played, `0` while the length is unknown.
  ///
  /// Deliberately unclamped, so a position past a shrinking live duration reads
  /// above 1; a bar that cannot overdraw must clamp it.
  double get progress {
    if (!hasDuration) {
      return 0;
    }

    return position.inMilliseconds / duration.inMilliseconds;
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  /// The same transport with the named fields replaced.
  ///
  /// A null argument keeps the current value — so this cannot clear
  /// [updatedAt] — and no field is re-derived: engine commands go through
  /// [reduce], which decides what each report implies.
  PlayerTransportState copyWith({
    PlaybackCommand? command,
    Duration? position,
    Duration? duration,
    double? volume,
    double? rate,
    bool? initialized,
    DateTime? updatedAt,
    bool? buffering,
    PlaybackBuffer? buffer,
  }) {
    return PlayerTransportState(
      command: command ?? this.command,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      rate: rate ?? this.rate,
      initialized: initialized ?? this.initialized,
      updatedAt: updatedAt ?? this.updatedAt,
      buffering: buffering ?? this.buffering,
      buffer: buffer ?? this.buffer,
    );
  }

  /// Reduce command.
  PlayerTransportState reduce(PlaybackCommand command) {
    switch (command) {
      case PlaybackCommandPlay():
        return copyWith(command: command, initialized: true, updatedAt: clock.now());

      case PlaybackCommandPause():
        return copyWith(command: command, updatedAt: clock.now());

      case PlaybackCommandStop():
        return copyWith(command: command, position: Duration.zero, updatedAt: clock.now());

      case PlaybackCommandBuffering():
        // Keeps the transport command on purpose: the player is still playing
        // (or paused) while it waits for data, and callers ask `isPlaying`.
        return copyWith(buffering: command.value, updatedAt: clock.now());

      case PlaybackCommandLoading():
        return copyWith(command: command, updatedAt: clock.now());

      case PlaybackCommandSeek():
        return copyWith(position: command.position, updatedAt: clock.now());

      case PlaybackCommandPosition():
        return copyWith(position: command.position, updatedAt: clock.now());

      case PlaybackCommandDuration():
        return copyWith(duration: command.duration, updatedAt: clock.now());

      case PlaybackCommandBuffered(:final ranges):
        // A report, not an intention: the transport command is
        // untouched, because playing/paused is exactly what it was
        // when the buffer advanced. Normalized on the way in so every
        // consumer of `state.buffer` reads canonical ranges no matter
        // how the engine chunked its reports.
        return copyWith(
          buffer: PlaybackBuffer(ranges: ranges).normalize(),
          updatedAt: clock.now(),
        );

      case PlaybackCommandVolume():
        return copyWith(volume: command.volume, updatedAt: clock.now());

      case PlaybackCommandRate():
        return copyWith(rate: command.rate, updatedAt: clock.now());

      case PlaybackCommandIdle():
        return copyWith(command: command, updatedAt: clock.now());
    }
  }

  @override
  List<Object?> get props => [command, position, duration, volume, rate, initialized, updatedAt, buffering, buffer];

  @override
  String toString() {
    return 'PlayerTransportState('
        'command=$command, '
        'position=$position, '
        'duration=$duration, '
        'volume=$volume, '
        'rate=$rate'
        '${buffering ? ', buffering' : ''})';
  }
}
