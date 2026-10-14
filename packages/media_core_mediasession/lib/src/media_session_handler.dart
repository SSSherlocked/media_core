import 'package:audio_service/audio_service.dart';

/// Snapshot of playback state pushed into the system media surface.
final class MediaSessionState {
  /// Creates the snapshot.
  const MediaSessionState({required this.playing, required this.position, required this.duration, required this.speed});

  /// Whether playback is active.
  final bool playing;

  /// Current playback position.
  final Duration position;

  /// Known media duration.
  final Duration duration;

  /// Current playback speed.
  final double speed;
}

/// Metadata describing the current media item.
final class MediaSessionItem {
  /// Creates the metadata.
  const MediaSessionItem({
    required this.id,
    required this.title,
    this.album = '',
    this.artist = '',
    this.duration,
    this.artUri,
  });

  /// Stable media identifier.
  final String id;

  /// Display title.
  final String title;

  /// Display album.
  final String album;

  /// Display artist.
  final String artist;

  /// Media duration when known.
  final Duration? duration;

  /// Artwork uri when available.
  final Uri? artUri;

  /// This item with some fields replaced.
  MediaSessionItem copyWith({String? title, String? album, String? artist, Duration? duration, Uri? artUri}) {
    return MediaSessionItem(
      id: id,
      title: title ?? this.title,
      album: album ?? this.album,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
      artUri: artUri ?? this.artUri,
    );
  }

  /// Converts to the platform model.
  MediaItem toMediaItem() {
    return MediaItem(id: id, album: album, title: title, artist: artist, duration: duration, artUri: artUri);
  }
}

/// [BaseAudioHandler] that bridges the platform media surfaces and media_core.
///
/// Outbound (player → notification): [publishState] and [publishMediaItem]
/// mirror a `PlayerHandle`'s playback state.
///
/// Inbound (notification → player): transport commands are forwarded through
/// the callbacks supplied at construction. A callback that was not supplied
/// degrades to [BaseAudioHandler]'s default, so a control the host did not
/// install cannot silently do nothing.
final class MediaSessionHandler extends BaseAudioHandler {
  /// Creates the handler.
  MediaSessionHandler({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function(Duration position) onSeek,
    required Future<void> Function() onStop,
    Future<void> Function()? onNext,
    Future<void> Function()? onPrevious,
    Future<void> Function(int index)? onSkipToQueueItem,
    Future<void> Function(double rate)? onSetSpeed,
    this.controlsBuilder,
    this.stopOnTaskRemoved = false,
  }) : _onPlay = onPlay,
       _onPause = onPause,
       _onSeek = onSeek,
       _onStop = onStop,
       _onNext = onNext,
       _onPrevious = onPrevious,
       _onSkipToQueueItem = onSkipToQueueItem,
       _onSetSpeed = onSetSpeed;

  final Future<void> Function() _onPlay;
  final Future<void> Function() _onPause;
  final Future<void> Function(Duration position) _onSeek;
  final Future<void> Function() _onStop;
  final Future<void> Function()? _onNext;
  final Future<void> Function()? _onPrevious;
  final Future<void> Function(int index)? _onSkipToQueueItem;
  final Future<void> Function(double rate)? _onSetSpeed;

  /// Whether the platform may offer skip-next.
  bool get canSkipToNext => _onNext != null;

  /// Whether the platform may offer skip-previous.
  bool get canSkipToPrevious => _onPrevious != null;

  /// Whether the task-removal callback stops playback.
  ///
  /// `MediaSessionConfig.androidStopOnRemoveTask`, which is what the platform's
  /// "the viewer swiped the app away" signal is for. Off means the audio keeps
  /// running from the notification, which is what a music app wants and what a
  /// live room does not.
  final bool stopOnTaskRemoved;

  /// Optional builder for notification controls.
  ///
  /// Receives the current playing state and returns the controls to display.
  /// When null a play/pause + stop pair is used.
  // Positional `playing` mirrors audio_service's `MediaControlsBuilder`, so a
  // platform-provided builder can be dropped in without rewrapping.
  // ignore: avoid_positional_boolean_parameters
  final List<MediaControl> Function(bool playing)? controlsBuilder;

  /// Builds compact action indices advertised to the platform.
  ///
  /// Derived from [controls] so callers don't have to keep two lists in sync.
  static List<int> compactIndicesFor(List<MediaControl> controls) {
    if (controls.length <= 2) {
      return List<int>.generate(controls.length, (index) => index);
    }

    return const <int>[0, 1];
  }

  /// Pushes [state] into the media surface.
  void publishState(MediaSessionState state, {List<MediaControl>? controls}) {
    playbackState.add(
      PlaybackState(
        controls: controls ?? const <MediaControl>[],
        processingState: AudioProcessingState.ready,
        playing: state.playing,
        updatePosition: state.position,
        bufferedPosition: state.duration,
        speed: state.speed,
      ),
    );
  }

  /// Pushes idle state into the media surface.
  void publishIdle() {
    playbackState.add(PlaybackState());
  }

  /// Pushes [item] as the current media item.
  void publishMediaItem(MediaSessionItem item) {
    mediaItem.add(item.toMediaItem());
  }

  /// Clears the current media item.
  void clearMediaItem() {
    mediaItem.add(null);
  }

  /// Publishes the play list so the platform can show and jump through it.
  ///
  /// The playing entry is also published as the current [mediaItem]; the
  /// platform derives "current" from that, not from the list order.
  void publishQueue(List<MediaSessionItem> items, {int index = -1}) {
    queue.add(items.map((item) => item.toMediaItem()).toList(growable: false));

    if (index >= 0 && index < items.length) {
      publishMediaItem(items[index]);
    }
  }

  // ---------------------------------------------------------------------------
  // Inbound transport commands (notification / lock screen / media keys)
  // ---------------------------------------------------------------------------

  @override
  Future<void> play() => _onPlay();

  @override
  Future<void> pause() => _onPause();

  @override
  Future<void> seek(Duration position) => _onSeek(position);

  @override
  Future<void> stop() async {
    await _onStop();
    await super.stop();
  }

  /// The viewer swiped the app away in Android's recents.
  ///
  /// Without [stopOnTaskRemoved] this answers nothing and playback continues —
  /// the music keeps playing from the notification, which is what a music app
  /// asks for. With it, the stop the viewer meant is the stop that happens: a
  /// live room that keeps streaming after its page is gone is the case the flag
  /// exists for.
  @override
  Future<void> onTaskRemoved() async {
    if (!stopOnTaskRemoved) {
      return;
    }

    await stop();
  }

  @override
  Future<void> skipToNext() async {
    final next = _onNext;

    // Without a queue the sane degrade is the default behavior.
    if (next == null) {
      return await super.skipToNext();
    }

    await next();
  }

  @override
  Future<void> skipToPrevious() async {
    final previous = _onPrevious;

    if (previous == null) {
      return await super.skipToPrevious();
    }

    await previous();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final skip = _onSkipToQueueItem;

    if (skip == null) {
      return await super.skipToQueueItem(index);
    }

    await skip(index);
  }

  @override
  Future<void> setSpeed(double speed) async {
    final setSpeed = _onSetSpeed;

    if (setSpeed == null) {
      return await super.setSpeed(speed);
    }

    await setSpeed(speed);
  }
}
