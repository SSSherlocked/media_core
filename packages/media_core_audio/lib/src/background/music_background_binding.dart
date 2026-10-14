import 'dart:async';

import 'package:media_core/media_core.dart' show PlayerHandle;
import 'package:media_core_audio/src/media_core_audio.dart';
import 'package:media_core_audio/src/player/audio_playback_controller.dart';
import 'package:media_core_audio/src/player/audio_playback_state.dart';
import 'package:media_core_audio/src/track/music_track.dart';
import 'package:media_core_mediasession/media_core_mediasession.dart';

/// Connects an [AudioPlaybackController] to the platform's background playback
/// surfaces.
///
/// Background playback is four separate things, and this binding does the three
/// that belong to a music player:
///
/// 1. **The player keeps running off-screen.** Nothing to do here — the engine
///    is the same one used in the foreground.
/// 2. **The system surface shows the right thing.** The notification/lock
///    screen/SMTC/MPRIS gets the music metadata (title, artist, album, cover)
///    instead of a file name, plus the queue, so the platform's own "next"
///    works.
/// 3. **Transport commands come back.** Play/pause/seek/next/previous from the
///    notification, the lock screen, a headset button or a media key all reach
///    the controller through this binding.
/// 4. **Whether playback is allowed off-screen at all** is *not* decided here —
///    it is `PlayerConfig.pauseWhenBackgrounded` (per player) and
///    `KernelOptions.pauseWhenBackgrounded` (per kernel, on by default). What
///    this binding does about it is the part a policy cannot do alone: the
///    surface publishes what the player really is doing, and a detach releases
///    the surface instead of leaving a media session claiming playback.
///
/// Audio focus and interruptions stay the capability driver's job
/// ([MediaCoreAudio] itself) — this binding only installs the queue transports,
/// mirrors state, and asks for the background pause.
///
/// ```dart
/// final audio = await MediaSessionBootstrap.enable();
/// await audio.initialize();
/// final player = AudioPlaybackController(kernel);
/// final background = MusicBackgroundBinding(player, audio)..attach();
/// ```
final class MusicBackgroundBinding {
  /// Creates a binding.
  MusicBackgroundBinding(this.player, this.audio);

  /// The music player to mirror.
  final AudioPlaybackController player;

  /// The platform capability driver to publish through.
  ///
  /// The shared [MediaSessionDriver], which the app may have enabled once for
  /// the whole process ([MediaSessionBootstrap.enable]) — the binding does not
  /// need the music module's subclass for anything.
  final MediaSessionDriver audio;

  StreamSubscription<AudioPlaybackState>? _stateSub;

  /// The handle this binding put on the surface.
  ///
  /// The driver is app-wide (a video player can be published too), so only the
  /// surface this binding took may be released by it.
  PlayerHandle? _published;

  bool _attached = false;
  bool _disposed = false;

  /// Whether the binding is installed.
  bool get attached => _attached;

  /// Installs the transports and starts mirroring.
  ///
  /// Safe to call before the first track plays: the handle is created lazily by
  /// the controller, and the binding picks it up as soon as it exists.
  void attach() {
    if (_attached || _disposed) {
      return;
    }

    _attached = true;

    // Assigned one by one, not as a cascade: `..x = () => y() ..z = w` parses
    // the following section as part of the lambda body, silently turning the
    // cascade into a cascade on the lambda's return value.
    audio.skipToNextHandler = player.next;
    audio.skipToPreviousHandler = player.previous;
    audio.skipToQueueItemHandler = player.playAt;
    audio.setSpeedHandler = player.setRate;

    _stateSub = player.stateStream.listen(_onState);

    // The current snapshot may already describe a playing track.
    _onState(player.state);
  }

  /// Removes the transports, releases the surface this binding published, and
  /// stops mirroring.
  ///
  /// Releasing the surface is the half that matters. The last state published
  /// said "playing", and on Android a media session that still claims playback
  /// keeps its foreground service alive: leaving the binding installed would
  /// look exactly like a background playback that cannot be turned off.
  void detach() {
    if (!_attached) {
      return;
    }

    _attached = false;

    audio.skipToNextHandler = null;
    audio.skipToPreviousHandler = null;
    audio.skipToQueueItemHandler = null;
    audio.setSpeedHandler = null;

    unawaited(_stateSub?.cancel());
    _stateSub = null;

    final published = _published;
    _published = null;

    if (published != null && identical(audio.active, published)) {
      // publishIdle + clearMediaItem, and the driver stops following the player.
      audio.setActive(null);
    }
  }

  /// Releases the binding.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    detach();
  }

  void _onState(AudioPlaybackState state) {
    if (_disposed) {
      return;
    }

    final handle = player.handle;

    // The capability driver follows "the active player"; the controller's
    // handle appears on first playback, so it is attached here rather than at
    // construction.
    if (handle != null && !handle.disposed && !identical(audio.active, handle)) {
      audio.setActive(handle);
      _published = handle;
    }

    final handler = audio.handler;

    if (handler == null) {
      return;
    }

    final track = state.track;

    if (track == null) {
      handler
        ..publishIdle()
        ..clearMediaItem();

      return;
    }

    handler.publishMediaItem(_itemFor(track, state));

    if (state.queueLength > 0) {
      handler.publishQueue(
        player.queue.tracks.map((item) => _itemFor(item, state)).toList(growable: false),
        index: state.index,
      );
    }

    // No explicit controls: the handler builds them from the transports that
    // are installed, so installing/removing skip support never needs a second
    // list kept in sync here.
    handler.publishState(
      MediaSessionState(playing: state.playing, position: state.position, duration: state.duration, speed: state.rate),
    );
  }

  MediaSessionItem _itemFor(MusicTrack track, AudioPlaybackState state) {
    final isCurrent = identical(track, state.track) || track == state.track;

    return MediaSessionItem(
      id: '${track.sourceId}:${track.id}',
      title: track.title,
      artist: track.artist,
      album: track.album,
      artUri: track.coverUri,
      duration: isCurrent && state.duration > Duration.zero ? state.duration : track.duration,
    );
  }
}
