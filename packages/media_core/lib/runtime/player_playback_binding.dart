import 'dart:async';
import 'package:media_core/adapter/player_adapter.dart';
import 'package:media_core/adapter/player_adapter_event.dart';
import 'package:media_core/playback/playback_command.dart';
import 'package:media_core/playback/playback_controller.dart';
import 'package:media_core/runtime/player_runtime.dart' show PlayerRuntime;

/// Bridges [PlayerAdapter] playback events into a [PlaybackController].
///
/// Thin bridge, same rules as `PlayerGeometryBinding`: no state, no
/// lifecycle, no model. Owned by [PlayerRuntime].
final class PlayerPlaybackBinding {
  /// Subscribes to [adapter]'s event stream and forwards playback
  /// events into [playback].
  PlayerPlaybackBinding({required PlayerAdapter adapter, required PlaybackController playback}) : _playback = playback {
    _subscription = adapter.events.listen(_onEvent);
  }

  final PlaybackController _playback;
  late final StreamSubscription<PlayerAdapterEvent> _subscription;

  void _onEvent(PlayerAdapterEvent event) {
    switch (event) {
      case PlayerAdapterPlaying():
        _playback.apply(const PlaybackCommand.play());

      case PlayerAdapterPaused():
        _playback.apply(const PlaybackCommand.pause());

      case PlayerAdapterStopped():
        _playback.apply(const PlaybackCommand.stop());

      case PlayerAdapterBuffering(:final buffering):
        _playback.setBuffering(buffering: buffering);

      case PlayerAdapterPositionChanged(:final position):
        _playback.updatePosition(position);

      case PlayerAdapterDurationChanged(:final duration):
        _playback.updateDuration(duration);

      case PlayerAdapterBufferedRangesChanged(:final ranges):
        _playback.updateBuffer(ranges);

      case PlayerAdapterVolumeChanged(:final volume):
        _playback.apply(PlaybackCommand.volume(volume));

      case PlayerAdapterRateChanged(:final rate):
        _playback.apply(PlaybackCommand.rate(rate));

      // `PlaybackCommand` has no `completed` variant, and mapping the
      // completion onto `stop()` would reset position to zero — wrong
      // for a source that just played to the end. Completion is a
      // session-level concern; the session layer observes
      // `PlayerAdapterCompleted` directly.
      case PlayerAdapterCompleted():
        break;

      default:
        break;
    }
  }

  /// Detaches from [PlayerAdapter.events].
  ///
  /// Does not dispose [PlaybackController]; that is owned by
  /// [PlayerRuntime] and disposed separately.
  Future<void> dispose() => _subscription.cancel();
}
