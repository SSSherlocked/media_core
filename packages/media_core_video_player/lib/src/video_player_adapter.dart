import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_player_adapter_factory.dart';

/// [PlayerAdapter] on AVPlayer (macOS and iOS), through the official
/// video_player AVFoundation implementation.
///
/// AVPlayer reads HLS natively: one persistent connection per host, the
/// playlist reloaded on its own schedule, hardware decoding, and the
/// system's own buffering. The adapter drives the platform interface
/// directly (no app-facing VideoPlayerController):
///
/// - one native player per open; a new open disposes the previous one
/// - events come from `videoEventsFor`; errors arrive as stream errors
/// - the position is polled (the platform interface has no position
///   events) while the source is open, so the host's stall watch sees it
/// - `play` / `pause` follow `isPlayingStateUpdate`, de-duplicated, with
///   buffering reported through [PlayerAdapterEvent.buffering]
/// - fit applied by sizing the texture inside a [FittedBox]
final class VideoPlayerAdapter extends PlayerAdapterBase implements PlayerVideo {
  VideoPlayerAdapter({super.id = kVideoPlayerBackendId, super.capabilities = defaultCapabilities});

  static const Duration _positionPollInterval = Duration(milliseconds: 250);

  PlayerAdapterContext? _context;
  int? _playerId;
  StreamSubscription<VideoEvent>? _events;
  Timer? _positionTimer;
  bool _platformReady = false;

  final ValueNotifier<Size?> _size = ValueNotifier<Size?>(null);
  final ValueNotifier<BoxFit> _fit = ValueNotifier<BoxFit>(BoxFit.contain);

  bool _liveSource = false;
  bool _playingNow = false;
  bool _buffering = false;
  Duration _lastPosition = Duration.zero;
  Duration? _lastDuration;
  String? _lastReportedError;
  Completer<void>? _initialized;

  VideoPlayerPlatform get _platform => VideoPlayerPlatform.instance;

  // ---------------------------------------------------------------------------
  // PlayerVideo
  // ---------------------------------------------------------------------------

  @override
  bool get available => !isDisposed && _playerId != null;

  @override
  void setVideoFit(BoxFit fit) => _fit.value = fit;

  @override
  Widget build() {
    final int? playerId = _playerId;
    if (playerId == null) return const SizedBox.shrink();
    final Widget view = _platform.buildViewWithOptions(VideoViewOptions(playerId: playerId));
    return ValueListenableBuilder<BoxFit>(
      valueListenable: _fit,
      builder: (context, fit, _) => ValueListenableBuilder<Size?>(
        valueListenable: _size,
        builder: (context, size, _) {
          if (size == null || size.width <= 0 || size.height <= 0) return const SizedBox.expand();
          return SizedBox.expand(
            child: ClipRect(
              child: FittedBox(
                fit: fit,
                child: SizedBox(width: size.width, height: size.height, child: view),
              ),
            ),
          );
        },
      ),
    );
  }

  /// No-op: the texture lives as long as the native player.
  @override
  Future<void> attach() async {}

  @override
  Future<void> detach() async {}

  // ---------------------------------------------------------------------------
  // Engine contract
  // ---------------------------------------------------------------------------

  @override
  bool get engineReportsOpenFailure => _lastReportedError != null;

  @override
  Future<void> onInitialize(PlayerAdapterContext context) async {
    _context = context;
    if (!_platformReady) {
      await _platform.init();
      _platformReady = true;
    }
  }

  @override
  Future<void> onOpen(PlayerSource source) async {
    await _disposeNativePlayer();
    if (isDisposed) return;
    _lastReportedError = null;
    _liveSource = source.isLive;
    _lastPosition = Duration.zero;
    _lastDuration = null;
    _playingNow = false;
    _buffering = false;

    final DataSource dataSource = _dataSourceOf(source);
    final int? playerId = await _platform.createWithOptions(
      VideoCreationOptions(dataSource: dataSource, viewType: VideoViewType.textureView),
    );
    if (playerId == null) {
      throw StateError('VideoPlayerAdapter could not create a player for ${source.uri}');
    }
    if (isDisposed) {
      await _platform.dispose(playerId);
      return;
    }
    _playerId = playerId;
    final Completer<void> initialized = Completer<void>();
    _initialized = initialized;
    _events = _platform.videoEventsFor(playerId).listen(_onEvent, onError: _onEventError);

    // The open completes once AVPlayer has read enough to know the item
    // (or failed): the kernel's source-ready window covers a hung read.
    await initialized.future;
    if (isDisposed) return;

    final PlayerAdapterConfig config = _context?.config ?? const PlayerAdapterConfig();
    await _platform.setVolume(playerId, config.volume.clamp(0.0, 1.0));
    if (!_liveSource && config.playbackRate != 1.0) {
      await _platform.setPlaybackSpeed(playerId, config.playbackRate);
    }
    _startPositionPoll();
  }

  @override
  Future<void> onAfterOpen(PlayerSource source) async {
    final bool autoPlay = _context?.playerConfig?.autoPlay ?? true;
    if (autoPlay) await play();
  }

  @override
  Future<void> onPlay() async {
    final int? playerId = _playerId;
    if (playerId != null) await _platform.play(playerId);
  }

  @override
  Future<void> onPause() async {
    final int? playerId = _playerId;
    if (playerId != null) await _platform.pause(playerId);
  }

  @override
  Future<void> onStop() async {
    final int? playerId = _playerId;
    if (playerId == null) return;
    await _platform.pause(playerId);
    _playingNow = false;
    // A live stream has no rewindable timeline.
    if (_liveSource) return;
    await _platform.seekTo(playerId, Duration.zero);
  }

  @override
  Future<void> onSeek(Duration position) async {
    final int? playerId = _playerId;
    if (playerId != null) await _platform.seekTo(playerId, position);
  }

  @override
  Future<void> onSetVolume(double volume) async {
    final int? playerId = _playerId;
    if (playerId != null) await _platform.setVolume(playerId, volume.clamp(0.0, 1.0));
  }

  @override
  Future<void> onSetRate(double rate) async {
    final int? playerId = _playerId;
    if (playerId == null || _liveSource) return;
    await _platform.setPlaybackSpeed(playerId, rate);
  }

  @override
  Future<void> onClose() async {
    await _disposeNativePlayer();
  }

  @override
  Future<void> onDispose() async {
    await _disposeNativePlayer();
    _context = null;
    _size.dispose();
    _fit.dispose();
  }

  // ---------------------------------------------------------------------------
  // Native player
  // ---------------------------------------------------------------------------

  DataSource _dataSourceOf(PlayerSource source) {
    final Map<String, String> headers = source.hasHeaders
        ? Map<String, String>.from(source.headers!.values)
        : const <String, String>{};
    if (source.isFile) {
      return DataSource(sourceType: DataSourceType.file, uri: source.uri.toString());
    }
    if (source.isNetworkSource) {
      final bool hls = source.uri.path.toLowerCase().endsWith('.m3u8');
      return DataSource(
        sourceType: DataSourceType.network,
        uri: source.uri.toString(),
        formatHint: hls ? VideoFormat.hls : null,
        httpHeaders: headers,
      );
    }
    throw StateError('VideoPlayerAdapter cannot open ${source.uri} (unsupported source type).');
  }

  Future<void> _disposeNativePlayer() async {
    _positionTimer?.cancel();
    _positionTimer = null;
    final StreamSubscription<VideoEvent>? events = _events;
    _events = null;
    final int? playerId = _playerId;
    _playerId = null;
    final Completer<void>? initialized = _initialized;
    _initialized = null;
    if (initialized != null && !initialized.isCompleted) {
      initialized.completeError(StateError('VideoPlayerAdapter: the source was closed while opening'));
    }
    _playingNow = false;
    _buffering = false;
    if (!isDisposed) _size.value = null;
    await events?.cancel();
    if (playerId != null) {
      try {
        await _platform.dispose(playerId);
      } catch (_) {
        // The native player may already be gone.
      }
    }
  }

  void _startPositionPoll() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(_positionPollInterval, (_) => unawaited(_pollPosition()));
  }

  Future<void> _pollPosition() async {
    final int? playerId = _playerId;
    if (playerId == null || !acceptsEngineEvents) return;
    try {
      final Duration position = await _platform.getPosition(playerId);
      if (playerId != _playerId || !acceptsEngineEvents) return;
      if (position != _lastPosition) {
        _lastPosition = position;
        emitPositionChanged(position);
      }
    } catch (_) {
      // A player being torn down answers with an error; the next tick or
      // the close settles it.
    }
  }

  // ---------------------------------------------------------------------------
  // Engine events
  // ---------------------------------------------------------------------------

  void _onEvent(VideoEvent event) {
    switch (event.eventType) {
      case VideoEventType.initialized:
        final Size? size = event.size;
        if (size != null && size.width > 0 && size.height > 0) {
          _size.value = size;
          if (acceptsEngineEvents) emitVideoSizeChangedIfChanged(size.width.toInt(), size.height.toInt());
        }
        final Duration? duration = event.duration;
        if (duration != null && duration > Duration.zero && duration != _lastDuration) {
          _lastDuration = duration;
          if (acceptsEngineEvents) emitDurationChanged(duration);
        }
        final Completer<void>? initialized = _initialized;
        if (initialized != null && !initialized.isCompleted) initialized.complete();
      case VideoEventType.isPlayingStateUpdate:
        if (!acceptsEngineEvents) return;
        final bool playing = event.isPlaying ?? false;
        if (playing == _playingNow) return;
        // AVPlayer drops its rate while it waits for data: a pause during
        // buffering is not a user-visible pause.
        if (!playing && _buffering) return;
        _playingNow = playing;
        playing ? emitPlaying() : emitPaused();
      case VideoEventType.bufferingStart:
        if (!acceptsEngineEvents || _buffering) return;
        _buffering = true;
        emitBuffering(true);
      case VideoEventType.bufferingEnd:
        if (!acceptsEngineEvents || !_buffering) return;
        _buffering = false;
        emitBuffering(false, resumePlaying: state.playing);
      case VideoEventType.bufferingUpdate:
        if (!acceptsEngineEvents) return;
        final List<DurationRange>? buffered = event.buffered;
        if (buffered != null && buffered.isNotEmpty) {
          final Duration end = buffered.last.end;
          if (end != metrics.buffered) updateMetrics((m) => m.copyWith(buffered: end));
        }
      case VideoEventType.completed:
        if (!acceptsEngineEvents) return;
        _playingNow = false;
        emitCompleted();
      case VideoEventType.unknown:
        break;
    }
  }

  void _onEventError(Object error) {
    final String message = error is Exception || error is Error ? error.toString() : 'AVPlayer error: $error';
    final Completer<void>? initialized = _initialized;
    if (initialized != null && !initialized.isCompleted) {
      initialized.completeError(StateError(message));
    }
    if (_lastReportedError == message) return;
    _lastReportedError = message;
    if (acceptsEngineEvents) reportEngineError(message: message);
  }

  // ---------------------------------------------------------------------------
  // Capabilities
  // ---------------------------------------------------------------------------

  /// AVPlayer opens HLS and the common Apple containers; no FLV, no RTMP.
  static const PlayerAdapterCapabilities defaultCapabilities = PlayerAdapterCapabilities(
    supportsLive: true,
    supportsSeek: true,
    supportsPause: true,
    supportsStop: true,
    supportsRateControl: true,
    supportsVolumeControl: true,
    supportsMuteControl: true,
    supportsAudioOnly: false,
    supportsVideoFrameProgress: false,
    supportsVideoSizeChanged: true,
    supportsVideoReconfig: false,
    supportsHwdecInfo: false,
    supportsVideoFilters: false,
    supportsScreenshot: false,
    supportsAudioReconfig: false,
    supportsAudioDeviceSelection: false,
    supportsAudioFilters: false,
    supportsTrackSelection: false,
    supportsSubtitleTrack: false,
    supportsExternalSubtitle: false,
    supportsCacheState: false,
    supportsBufferingProgress: false,
    supportsChapterControl: false,
    supportsLoop: false,
    supportsMetadata: false,
    supportsPlaylist: false,
    supportsPlaylistControl: false,
    supportsClientMessage: false,
    supportsLogMessages: false,
    supportsHardwareDecoder: true,
    supportsSoftwareDecoder: false,
    supportsPictureInPicture: false,
    supportsFullscreen: true,
    supportedProtocols: {'http', 'https', 'file'},
    supportedFormats: {'m3u8', 'mp4', 'm4v', 'mov', 'm4a', 'aac', 'mp3', 'ts'},
    compositeSupport: CompositeSupport.none,
  );
}
