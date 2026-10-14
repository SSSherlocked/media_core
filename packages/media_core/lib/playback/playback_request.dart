import 'package:equatable/equatable.dart';
import 'package:media_core/playback/playback_command.dart';

/// Playback request.
///
/// Represents an external playback operation.
///
/// Used by:
///
/// - PlaybackController
/// - PlaybackService
///
/// Does not:
///
/// - execute playback
/// - call backend player
/// - mutate state
final class PlaybackRequest extends Equatable {
  /// Wraps [command] with the [source] that issued it.
  const PlaybackRequest({required this.command, this.source = 'unknown'});

  /// Creates play request.
  factory PlaybackRequest.play({String source = 'unknown'}) {
    return PlaybackRequest(command: const PlaybackCommand.play(), source: source);
  }

  /// Creates pause request.
  factory PlaybackRequest.pause({String source = 'unknown'}) {
    return PlaybackRequest(command: const PlaybackCommand.pause(), source: source);
  }

  /// Creates stop request.
  factory PlaybackRequest.stop({String source = 'unknown'}) {
    return PlaybackRequest(command: const PlaybackCommand.stop(), source: source);
  }

  /// Creates seek request.
  factory PlaybackRequest.seek(Duration position, {String source = 'unknown'}) {
    return PlaybackRequest(command: PlaybackCommand.seek(position), source: source);
  }

  /// Creates buffering update.
  factory PlaybackRequest.buffering({required bool value, String source = 'unknown'}) {
    return PlaybackRequest(
      command: PlaybackCommand.buffering(value: value),
      source: source,
    );
  }

  /// Creates position update.
  factory PlaybackRequest.position(Duration position, {String source = 'unknown'}) {
    return PlaybackRequest(command: PlaybackCommand.position(position), source: source);
  }

  /// Creates duration update.
  factory PlaybackRequest.duration(Duration duration, {String source = 'unknown'}) {
    return PlaybackRequest(command: PlaybackCommand.duration(duration), source: source);
  }

  /// Creates volume request.
  factory PlaybackRequest.volume(double volume, {String source = 'unknown'}) {
    return PlaybackRequest(command: PlaybackCommand.volume(volume), source: source);
  }

  /// Creates rate request.
  factory PlaybackRequest.rate(double rate, {String source = 'unknown'}) {
    return PlaybackRequest(command: PlaybackCommand.rate(rate), source: source);
  }

  /// Command to execute.
  final PlaybackCommand command;

  /// Request origin.
  ///
  /// Examples:
  ///
  /// - ui
  /// - adapter
  /// - lifecycle
  final String source;

  /// Whether transport command.
  bool get isTransport {
    return command.isPlaying || command.isPaused || command.isStopped;
  }

  /// Whether timeline operation.
  bool get isTimeline {
    return command is PlaybackCommandSeek || command is PlaybackCommandPosition || command is PlaybackCommandDuration;
  }

  /// Log form: the command's runtime type name and the requesting [source].
  ///
  /// The command's payload is left out, so this cannot be read back as a
  /// request — it records who asked for what, which is all a log needs.
  Map<String, dynamic> toMap() {
    return {'command': command.runtimeType.toString(), 'source': source};
  }

  @override
  List<Object?> get props => [command, source];

  @override
  String toString() {
    return 'PlaybackRequest('
        'command=$command, '
        'source=$source)';
  }
}
