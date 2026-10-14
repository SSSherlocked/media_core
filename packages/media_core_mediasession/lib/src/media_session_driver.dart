import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart' as asvc;
import 'package:audio_service_mpris/audio_service_mpris.dart' as ampris;
import 'package:audio_service_win/audio_service_win.dart' as aswin;
import 'package:audio_session/audio_session.dart' as asession;
import 'package:media_core/media_core.dart';
import 'package:media_core_mediasession/src/media_session_config.dart';
import 'package:media_core_mediasession/src/media_session_handler.dart';
import 'package:meta/meta.dart' show visibleForTesting;

/// System media surfaces for the media_core kernel.
///
/// Implements [KernelAudioDriver], so the kernel hands it the active player —
/// video or audio, it does not care which — and wires that player to the
/// platform's media surfaces:
///
/// ```text
/// PlayerHandle.playbackStream ──▶ MediaSessionHandler ──▶ notification / SMTC / MPRIS
/// notification buttons        ──▶ MediaSessionHandler ──▶ PlayerHandle
/// audio focus interruptions   ──▶ pause / duck / resume
/// headphones unplugged        ──▶ pause
/// ```
///
/// ### Why this is its own package
///
/// The surfaces are not an audio feature: a video player wants the same
/// notification, the same lock-screen entry and the same media keys, and the
/// only differences are cosmetic (a seek pair instead of a skip pair, a video
/// channel name). Keeping the capability here means a video host gets it without
/// depending on the music module, and the music module uses the same
/// implementation instead of a second one.
///
/// Usage:
///
/// ```dart
/// final session = MediaSessionDriver(config: const MediaSessionConfig.video());
/// await session.initialize();          // once, early (before runApp is fine)
/// kernel.attachAudio(session);         // the kernel notifies active players
///
/// // or drive it manually without a kernel:
/// session.setActive(handle);
/// ```
///
/// The host app still owns the platform plumbing a library cannot declare for
/// it — the `audio_service` activity/service entries and, on Android 13+, the
/// notification permission. See the package README.
base class MediaSessionDriver implements KernelAudioDriver {
  /// Creates the driver.
  MediaSessionDriver({
    this.config = const MediaSessionConfig(),
    asession.AudioSessionConfiguration? sessionConfiguration,
    this.artUriResolver,
    @visibleForTesting MediaSessionHandler? handler,
  }) : _sessionConfiguration = sessionConfiguration,
       _handler = handler;

  /// Capability configuration.
  final MediaSessionConfig config;

  /// Resolves artwork for a source that does not carry any.
  ///
  /// A music source usually publishes `artUri` metadata; a video source
  /// usually has nothing but a URL and a title, and a notification without
  /// artwork looks unfinished next to every other app on the device. The host
  /// knows where its thumbnails come from, so it supplies the answer here.
  ///
  /// Called once per media item, on the main isolate.
  final Uri? Function(PlayerSource source)? artUriResolver;

  final asession.AudioSessionConfiguration? _sessionConfiguration;

  MediaSessionHandler? _handler;
  PlayerHandle? _active;

  /// Queue transports a host may install (a music player with a queue).
  ///
  /// Mutable rather than constructor arguments: the driver is created once at
  /// startup, while the player that owns a queue appears later — and a
  /// single-media app never sets them, so the notification simply shows the
  /// seek pair instead of skip buttons.
  Future<void> Function()? skipToNextHandler;

  /// Installed counterpart of [skipToNextHandler].
  Future<void> Function()? skipToPreviousHandler;

  /// Jump to a queue index.
  Future<void> Function(int index)? skipToQueueItemHandler;

  /// Playback-rate changes coming from the platform.
  Future<void> Function(double rate)? setSpeedHandler;

  StreamSubscription<void>? _playbackSub;
  StreamSubscription<asession.AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  bool _initialized = false;
  bool _disposed = false;
  bool _ducked = false;
  bool _resumeOnInterruptionEnd = false;
  double _volumeBeforeDuck = 1;

  /// The underlying audio_service handler.
  ///
  /// Null before [initialize].
  MediaSessionHandler? get handler => _handler;

  /// The active player, if any.
  PlayerHandle? get active => _active;

  /// Whether the driver is publishing, i.e. whether [initialize] ran.
  bool get isInitialized => _initialized;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initializes audio_service and the audio session.
  ///
  /// Call once, early (before `runApp` is fine).
  ///
  /// Platform integration:
  ///
  /// - Android/iOS: media notification + lock screen controls
  /// - Windows: SMTC (System Media Transport Controls) via audio_service_win
  /// - Linux: MPRIS (D-Bus) via audio_service_mpris — shows up in GNOME/KDE
  ///   media applets and media keys work
  ///
  /// On platforms without audio_session support the focus part is skipped;
  /// the surfaces still work.
  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }

    _initialized = true;

    _registerPlatformImplementation();

    if (_handler != null) {
      // Supplied from outside (a test): the platform session is still wired,
      // but there is no handler to build.
      return;
    }

    _handler = await asvc.AudioService.init(
      builder: () => MediaSessionHandler(
        onPlay: () async {
          await _active?.play();
        },
        onPause: () async {
          await _active?.pause();
        },
        onSeek: (position) async {
          await _active?.seek(position);
        },
        onStop: () async {
          await _active?.stop();
        },
        onNext: skipToNextHandler == null
            ? null
            : () async {
                await skipToNextHandler!.call();
              },
        onPrevious: skipToPreviousHandler == null
            ? null
            : () async {
                await skipToPreviousHandler!.call();
              },
        onSkipToQueueItem: skipToQueueItemHandler == null
            ? null
            : (index) async {
                await skipToQueueItemHandler!.call(index);
              },
        onSetSpeed: setSpeedHandler == null
            ? null
            : (rate) async {
                await setSpeedHandler!.call(rate);
              },
        controlsBuilder: _buildControls,
        stopOnTaskRemoved: config.androidStopOnRemoveTask,
      ),
      config: asvc.AudioServiceConfig(
        androidNotificationChannelId: config.androidNotificationChannelId,
        androidNotificationChannelName: config.androidNotificationChannelName,
        androidNotificationOngoing: config.androidNotificationOngoing,
        androidStopForegroundOnPause: !config.androidNotificationOngoing,
      ),
    );

    if (!_supportsAudioSession) {
      return;
    }

    try {
      final session = await asession.AudioSession.instance;

      await session.configure(_sessionConfiguration ?? const asession.AudioSessionConfiguration.music());

      if (config.processInterruptions) {
        _interruptionSub = session.interruptionEventStream.listen(_onInterruption, onError: (_) {});
      }

      if (config.pauseOnBecomingNoisy) {
        _noisySub = session.becomingNoisyEventStream.listen((_) => _active?.pause(), onError: (_) {});
      }
    } on Object catch (_) {
      // A platform without a functional audio_session implementation. Playback
      // still works; focus handling is simply unavailable.
    }
  }

  /// Releases this driver.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _playbackSub?.cancel();
    _playbackSub = null;

    await _interruptionSub?.cancel();
    _interruptionSub = null;

    await _noisySub?.cancel();
    _noisySub = null;

    _handler?.publishIdle();
    _handler?.clearMediaItem();

    _active = null;
    _handler = null;
  }

  // ---------------------------------------------------------------------------
  // KernelAudioDriver
  // ---------------------------------------------------------------------------

  @override
  void onPlayerActivated(PlayerHandle handle) {
    setActive(handle);
  }

  @override
  void onPlayerDeactivated() {
    setActive(null);
  }

  // ---------------------------------------------------------------------------
  // Active player binding
  // ---------------------------------------------------------------------------

  /// Binds [handle] as the player the surfaces describe.
  ///
  /// Pass null to detach. The kernel calls this automatically via
  /// `attachAudio`; apps without a kernel can drive it directly. Safe before
  /// [initialize]: the binding is remembered and published once a handler
  /// exists, so a host that opens a player while `AudioService.init` is still
  /// running does not end up with a silent notification.
  void setActive(PlayerHandle? handle) {
    if (_disposed || identical(handle, _active)) {
      return;
    }

    unawaited(_playbackSub?.cancel());
    _playbackSub = null;

    _active = handle;
    _ducked = false;
    _resumeOnInterruptionEnd = false;

    final handler = _handler;

    if (handler == null) {
      // No handler yet: keep the binding and publish when initialize finishes.
      return;
    }

    if (handle == null) {
      handler
        ..publishIdle()
        ..clearMediaItem();

      return;
    }

    handler.publishMediaItem(_itemFor(handle));
    _publishCurrent(handle);

    _playbackSub = handle.playbackStream.listen(
      (_) => _publishCurrent(handle),
      onError: (_) {},
      onDone: () {
        if (identical(_active, handle)) {
          setActive(null);
        }
      },
    );
  }

  /// Publishes again, for a host that changed something the surfaces show.
  ///
  /// Used after [initialize] finished to pick up a binding that arrived while
  /// the platform was starting, and by a host whose player began playing a
  /// different source on the same handle.
  void refresh() {
    final handle = _active;
    final handler = _handler;

    if (handle == null || handler == null) {
      return;
    }

    handler.publishMediaItem(_itemFor(handle));
    _publishCurrent(handle);

    _playbackSub ??= handle.playbackStream.listen(
      (_) => _publishCurrent(handle),
      onError: (_) {},
      onDone: () {
        if (identical(_active, handle)) {
          setActive(null);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Interruptions
  // ---------------------------------------------------------------------------

  void _onInterruption(asession.AudioInterruptionEvent event) {
    final active = _active;

    if (active == null) {
      return;
    }

    if (event.begin) {
      switch (event.type) {
        case asession.AudioInterruptionType.duck:
          if (!_ducked) {
            _ducked = true;
            _volumeBeforeDuck = active.playback.volume;
            unawaited(active.setVolume(_volumeBeforeDuck * config.duckFactor));
          }

        case asession.AudioInterruptionType.pause:
        case asession.AudioInterruptionType.unknown:
          _resumeOnInterruptionEnd = config.resumeAfterInterruption && active.playback.isPlaying;
          unawaited(active.pause());
      }

      return;
    }

    if (_ducked) {
      _ducked = false;
      unawaited(active.setVolume(_volumeBeforeDuck));
    }

    if (_resumeOnInterruptionEnd) {
      _resumeOnInterruptionEnd = false;
      unawaited(active.play());
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool get _supportsAudioSession {
    // audio_session has no implementation on Windows/Linux.
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  void _registerPlatformImplementation() {
    // Federated plugins normally self-register through the generated plugin
    // registrant. Explicit registration covers custom embedders and makes the
    // backend selection visible.
    try {
      if (Platform.isWindows) {
        aswin.AudioServiceWin.registerWith();
      } else if (Platform.isLinux) {
        ampris.AudioServiceMpris.registerWith();
      }
    } on Object catch (_) {
      // Registration is best-effort: audio_service falls back to its default
      // platform implementation when this fails.
    }
  }

  /// The controls the platform shows for the current state.
  ///
  /// Skip buttons appear only when the host installed queue transports; the
  /// seek pair appears when the configuration asks for it. A single-media
  /// player therefore gets play/pause, ±[MediaSessionConfig.seekStep] and stop,
  /// while a queue player gets skip-previous/next in the same slots — which is
  /// what each platform's users expect from that kind of app.
  List<asvc.MediaControl> _buildControls(bool playing) {
    if (!config.showControls) {
      return const <asvc.MediaControl>[];
    }

    return <asvc.MediaControl>[
      if (skipToPreviousHandler != null)
        asvc.MediaControl(androidIcon: config.previousIcon, label: 'Previous', action: asvc.MediaAction.skipToPrevious)
      else if (config.showSeekButtons)
        asvc.MediaControl(
          androidIcon: config.rewindIcon,
          label: 'Back ${config.seekStep.inSeconds}s',
          action: asvc.MediaAction.rewind,
        ),
      asvc.MediaControl(
        androidIcon: playing ? config.pauseIcon : config.playIcon,
        label: playing ? 'Pause' : 'Play',
        action: playing ? asvc.MediaAction.pause : asvc.MediaAction.play,
      ),
      if (skipToNextHandler != null)
        asvc.MediaControl(androidIcon: config.nextIcon, label: 'Next', action: asvc.MediaAction.skipToNext)
      else if (config.showSeekButtons)
        asvc.MediaControl(
          androidIcon: config.fastForwardIcon,
          label: 'Forward ${config.seekStep.inSeconds}s',
          action: asvc.MediaAction.fastForward,
        ),
      asvc.MediaControl(androidIcon: config.stopIcon, label: 'Stop', action: asvc.MediaAction.stop),
    ];
  }

  /// What the surfaces were last told, so a position-only tick can be skipped.
  MediaSessionState? _published;

  /// How far the notification's position may lag the player.
  ///
  /// A lock screen redraws this bar about once a second no matter what the app
  /// pushes, and every publish is a platform notification rebuild. The player
  /// can report many times a second (and, before the engine adapters reduced
  /// their position streams, once per frame) - publishing each one spent battery
  /// and heat on frames nobody would see.
  static const Duration _positionPublishInterval = Duration(seconds: 1);

  void _publishCurrent(PlayerHandle handle) {
    final playback = handle.playback;
    final next = MediaSessionState(
      playing: playback.isPlaying,
      position: playback.position,
      duration: playback.duration,
      speed: playback.rate,
    );

    final previous = _published;
    if (previous != null &&
        next.playing == previous.playing &&
        next.duration == previous.duration &&
        next.speed == previous.speed) {
      final drift = next.position - previous.position;
      // Only small forward drift is skippable. A jump - a seek back, a new song
      // whose zero position follows the old one - must reach the surfaces now:
      // it is a different timeline, not a step along the same one.
      if (drift >= Duration.zero && drift < _positionPublishInterval) {
        return;
      }
    }

    _published = next;
    _handler?.publishState(next, controls: _buildControls(next.playing));
  }

  /// Describes a handle as a media item.
  ///
  /// Title order: the source's own title, then its file name, then the URI —
  /// a notification that says "Media" is worse than one that says
  /// "movie.mp4". Artwork comes from the source metadata, then from
  /// [artUriResolver]; a video source usually only has the second.
  MediaSessionItem _itemFor(PlayerHandle handle) {
    final source = handle.source;
    final uri = source?.uri;

    final title = source?.hasTitle == true
        ? source!.title!
        : (uri == null ? 'Media' : (uri.pathSegments.isEmpty ? uri.toString() : uri.pathSegments.last));

    final metadata = source?.metadataValue('artUri');

    final artUri = metadata is String ? Uri.tryParse(metadata) : (source != null ? artUriResolver?.call(source) : null);

    final duration = handle.playback.duration;

    return MediaSessionItem(
      id: source?.id.value ?? handle.id.value,
      title: title,
      duration: duration == Duration.zero ? null : duration,
      artUri: artUri,
    );
  }

  @override
  String toString() {
    return 'MediaSessionDriver('
        'initialized: $_initialized, '
        'active: ${_active?.id.value ?? 'none'}, '
        'channel: ${config.androidNotificationChannelId}'
        ')';
  }
}
