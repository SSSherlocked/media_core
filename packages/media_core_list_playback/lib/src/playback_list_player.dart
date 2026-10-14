import 'package:media_core/media_core.dart' show PlayerHandle, PlayerHandlePlayback, PlayerSource;

/// The player a list drives.
///
/// Narrow on purpose: the list controller needs to open a source, seek into it
/// and read the current position — nothing else. Keeping the seam this small
/// means a host can drive the list with the kernel's PlayerHandle, with the
/// live controller for a list of streams, or with its own player, and it means
/// the controller's resume semantics can be tested without a backend.
abstract interface class PlaybackListPlayer {
  /// Opens [source], starting playback.
  Future<void> open(PlayerSource source);

  /// Seeks to [position].
  Future<void> seek(Duration position);

  /// Current playback position.
  Duration get position;

  /// Total duration, or [Duration.zero] when unknown (a live stream has none).
  Duration get duration;
}

/// [PlaybackListPlayer] backed by a kernel [PlayerHandle].
final class KernelPlaybackListPlayer implements PlaybackListPlayer {
  /// Creates a list player that drives [handle].
  KernelPlaybackListPlayer(this.handle);

  /// Handle the list plays through.
  final PlayerHandle handle;

  @override
  Future<void> open(PlayerSource source) => handle.open(source, autoPlay: true);

  @override
  Future<void> seek(Duration position) => handle.seek(position);

  @override
  Duration get position => handle.position;

  @override
  Duration get duration => handle.duration;
}
