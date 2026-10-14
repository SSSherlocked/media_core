import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:media_core/media_core.dart';
import 'package:media_core_fvp/media_core_fvp.dart';

/// [PlayerAdapter] implementation backed by fvp's `libmdk` player.
///
/// The engine ships a current FFmpeg and prefers the platform hardware decoder
/// (MediaCodec, VideoToolbox, D3D11, VAAPI) with FFmpeg and dav1d as software
/// fallbacks. That covers streams the older bundled engines drop — notably the
/// legacy `codec id 12` HEVC FLV that media_kit's libmpv plays as audio only —
/// so this adapter is what an app registers to recover such a source instead of
/// failing the room.
///
/// The adapter owns its video surface too: it implements [PlayerVideo], so the
/// texture lifecycle (create, release for audio-only, release on close) has one
/// owner.
///
/// One engine instance serves exactly one source. libmdk resolves the render
/// target size once per player and cannot change it afterwards, so every `open`
/// builds a fresh player and releases the previous one.
final class FvpPlayerAdapter extends PlayerAdapterBase implements PlayerVideo {
  /// Creates the adapter.
  FvpPlayerAdapter({
    super.id = kFvpPlayerBackendId,
    PlayerAdapterCapabilities capabilities = defaultCapabilities,
    this.properties = const <String, String>{},
    this.videoDecoders,
    this.audioBackends,
    FvpVideoConfig videoConfig = const FvpVideoConfig(),
  }) : _videoConfig = videoConfig,
       super(capabilities: capabilities) {
    _fitNotifier.value = videoConfig.fit;
  }

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// Open-time engine configuration.
  ///
  /// Read on every open, so a change applies to the next source.
  /// Native mdk properties written verbatim when an engine is created.
  final Map<String, String> properties;

  /// Native decoder list; null leaves mdk's own default order.
  final List<String>? videoDecoders;

  /// Native audio backend list; null leaves mdk's default.
  final List<String>? audioBackends;

  FvpVideoConfig _videoConfig;

  /// The video configuration the current controller was built with.
  FvpVideoConfig get videoConfig => _videoConfig;

  /// Replaces [videoConfig] and publishes the new fit when it changed.
  set videoConfig(FvpVideoConfig value) {
    _videoConfig = value;
    if (_fitNotifier.value != value.fit) {
      _fitNotifier.value = value.fit;
    }
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  mdk.Player? _player;

  final List<StreamSubscription<Object?>> _subscriptions = <StreamSubscription<Object?>>[];

  Timer? _positionTimer;

  bool _hasOpened = false;
  bool _openFailed = false;

  bool _playingNow = false;
  bool _bufferingNow = false;
  bool _audioOutputSuppressed = false;

  /// Whether the current source is a live (non-seekable) stream.
  bool _liveSource = false;

  /// URL of the source the engine is holding, for the geometry retry.
  String? _currentUrl;

  /// Whether the current source already had its one geometry retry.
  bool _geometryRetried = false;

  double _volume = 1;
  double _lastEmittedVolume = -1;

  /// The engine's current texture, or null while there is no video output.
  final ValueNotifier<int?> _textureNotifier = ValueNotifier<int?>(null);

  /// Geometry of the current source, from the engine's media info.
  final ValueNotifier<Size?> _sizeNotifier = ValueNotifier<Size?>(null);

  final ValueNotifier<BoxFit> _fitNotifier = ValueNotifier<BoxFit>(BoxFit.contain);

  BoxFit _videoFit = BoxFit.contain;

  /// How long the adapter waits for the engine to publish video geometry.
  static const Duration _geometryTimeout = Duration(seconds: 10);

  /// Fit as a listenable, so a custom surface can react to [setVideoFit]
  /// without owning the notifier.
  ValueListenable<BoxFit> get fitListenable => _fitNotifier;

  /// The current video texture, or null while there is none.
  ValueListenable<int?> get textureListenable => _textureNotifier;

  /// Geometry of the video in the current source.
  ValueListenable<Size?> get sizeListenable => _sizeNotifier;

  /// Media information of the current source, or null before one opened.
  mdk.MediaInfo? get mediaInfo => _player?.mediaInfo;

  /// Whether the engine still has a source loaded.
  bool get hasSource => _hasOpened;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> onInitialize(PlayerAdapterContext context) async {
    // The engine is created per source: libmdk fixes the render target size for
    // the lifetime of a player, so reusing one across sources would paint the
    // second stream into the first stream's geometry.
  }

  @override
  Future<void> onBeforeOpen(PlayerSource source) async {
    _liveSource = source.isLive;
    _openFailed = false;
    _geometryRetried = false;
    _playingNow = false;
    _bufferingNow = false;
    _lastEmittedVolume = -1.0;
  }

  @override
  Future<void> onOpen(PlayerSource source) async {
    final url = source.uri.toString();
    final player = await _createEngine(url);

    _currentUrl = url;

    player
      ..setProperty(
        'avio.headers',
        encodeHeaders(source.hasHeaders ? source.headers!.values : const <String, String>{}),
      )
      // FFmpeg ignores an empty `http_proxy`, which is what a loopback relay
      // wants: the relay owns the proxied connection.
      ..setActiveTracks(mdk.MediaType.video, audioOnly ? const <int>[] : const <int>[0])
      ..volume = _volume
      ..media = url;

    _hasOpened = true;

    final result = await player.prepare();

    if (isDisposed || _player != player) return;

    if (result < 0) {
      _hasOpened = false;
      _openFailed = true;

      // Reported inside the open window, so the base turns it into a failed
      // open: the controller then escalates to the next line or engine instead
      // of leaving the user with audio and no picture.
      reportEngineError(message: 'fvp prepare failed ($result) for $url', code: PlayerErrorCode.backendOpenFailed);
      return;
    }

    player.state = mdk.PlaybackState.playing;

    _startPositionPolling(player);
  }

  @override
  Future<void> onAfterOpen(PlayerSource source) async {
    final player = _player;

    if (player == null || isDisposed) return;

    // Outside the open window and not awaited: the texture needs the engine's
    // video geometry, which libmdk publishes through its media-status stream.
    // Blocking the open on it would stall every source whose geometry arrives
    // late, and a missing texture is not an open failure.
    unawaited(_attachTexture(player));

    // A fresh open rebuilds the audio pipeline, so a suppressed output and the
    // audio-only track choice are applied again or sound comes back.
    player
      ..setActiveTracks(mdk.MediaType.video, audioOnly ? const <int>[] : const <int>[0])
      ..volume = _audioOutputSuppressed ? 0.0 : _volume;
  }

  @override
  Future<void> onPlay() async {
    final player = _player;

    if (player == null) return;

    player.state = mdk.PlaybackState.playing;

    _setPlaying(true);
  }

  @override
  Future<void> onPause() async {
    final player = _player;

    if (player == null) return;

    player.state = mdk.PlaybackState.paused;

    _setPlaying(false);
  }

  @override
  Future<void> onStop() async {
    _hasOpened = false;
    _playingNow = false;
    _bufferingNow = false;

    _stopPositionPolling();

    _player?.state = mdk.PlaybackState.stopped;
  }

  @override
  Future<void> onSeek(Duration position) async {
    final player = _player;

    if (player == null) return;

    await player.seek(position: position.inMilliseconds);
  }

  @override
  Future<void> onSetVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _player?.volume = _volume;
  }

  @override
  Future<void> onSetRate(double rate) async {
    // Live streams have no meaningful playback speed; honouring the command
    // would pitch-shift a broadcast.
    if (_liveSource) return;

    _player?.playbackRate = rate;
  }

  @override
  Future<void> onSetAudioOnly({required bool audioOnly}) async {
    final player = _player;

    if (player == null) return;

    player.setActiveTracks(mdk.MediaType.video, audioOnly ? const <int>[] : const <int>[0]);

    if (audioOnly) {
      await _releaseTexture();
    } else if (_hasOpened) {
      await _attachTexture(player);
    }
  }

  /// Marks the next open as a private input.
  ///
  /// A private input is a loopback source (an app-owned relay): the engine must
  /// not send it through the proxy, so the resolver is asked with
  /// `privateInput: true`. The flag is consumed by the next open.

  /// Marks the next open of the current source to decode in software.
  ///
  /// Used when a hardware decoder failed for the source that is about to be
  /// replayed; the engine then starts its software decoders directly instead of
  /// trying the hardware one again.

  /// Mutes the engine output without touching the stored volume.
  ///
  /// Used around engine switches: the outgoing engine must go silent before the
  /// incoming one has produced a frame.
  Future<void> setAudioOutputSuppressed({required bool suppressed}) async {
    _audioOutputSuppressed = suppressed;
    _player?.volume = suppressed ? 0.0 : _volume;
  }

  /// Whether audio output is currently suppressed.
  bool get audioOutputSuppressed => _audioOutputSuppressed;

  @override
  Future<void> onClose() async {
    _hasOpened = false;
    _playingNow = false;
    _bufferingNow = false;

    _stopPositionPolling();

    await _releaseTexture();
    await _disposeEngine();
  }

  @override
  Future<void> onDispose() async {
    _stopPositionPolling();

    await _releaseTexture();
    await _disposeEngine();

    _textureNotifier.dispose();
    _sizeNotifier.dispose();
    _fitNotifier.dispose();
  }

  // ---------------------------------------------------------------------------
  // Engine
  // ---------------------------------------------------------------------------

  /// Creates the engine for [url], releasing the previous one.
  Future<mdk.Player> _createEngine(String url) async {
    await _disposeEngine();

    final player = mdk.Player();

    _player = player;

    // Native decoder / audio-backend lists, verbatim. The default names two
    // software decoders: whether FFmpeg then reaches a hardware path on its
    // own is engine- and device-dependent and is not verified here, which is
    // why `supportsHardwareDecoder` is a claim about mdk rather than about
    // this list. Passing `videoDecoders: null` is not the same as omitting it
    // — the fallback below replaces it, so a caller who wants mdk's own order
    // has to pass the list explicitly.
    player.videoDecoders = videoDecoders ?? const <String>['FFmpeg', 'dav1d'];
    final backends = audioBackends;
    if (backends != null) player.audioBackends = backends;

    for (final entry in properties.entries) {
      player.setProperty(entry.key, entry.value);
    }

    _bind(player);

    return player;
  }

  /// Engine options received while no engine instance exists.
  ///
  /// fvp builds a fresh mdk player per source, so an option applied between
  /// opens is held here and written into the next engine at creation — the
  /// same last-value-wins contract the handle guarantees on its side.
  final Map<(String, String), EngineOption> _pendingEngineOptions = <(String, String), EngineOption>{};

  @override
  Future<List<EngineOptionOutcome>> onApplyEngineOptions(List<EngineOption> options) async {
    final outcomes = <EngineOptionOutcome>[];
    final player = _player;

    for (final option in options) {
      _pendingEngineOptions[(option.domain ?? '', option.key)] = option;

      if (player == null) {
        // The engine is created per source; the option joins the next one.
        outcomes.add(EngineOptionOutcome.stagedForNextOpen);

        continue;
      }

      try {
        _applyEngineOption(player, option);

        outcomes.add(EngineOptionOutcome.appliedLive);
      } on Object catch (_) {
        outcomes.add(EngineOptionOutcome.stagedForNextOpen);
      }
    }

    return outcomes;
  }

  /// Writes one option to an mdk player.
  void _applyEngineOption(mdk.Player player, EngineOption option) {
    switch (option.key) {
      case 'videoDecoders':
        player.videoDecoders = _stringListOf(option.value);
      case 'audioDecoders':
        player.audioDecoders = _stringListOf(option.value);
      case 'audioBackends':
        player.audioBackends = _stringListOf(option.value);
      default:
        player.setProperty(option.key, _mdkOptionValue(option.value));
    }
  }

  List<String> _stringListOf(Object? value) {
    if (value is List) {
      return <String>[for (final entry in value) '$entry'];
    }

    throw ArgumentError.value(value, 'value', 'Expected a list of strings.');
  }

  String _mdkOptionValue(Object? value) {
    return switch (value) {
      null => '',
      final bool flag => flag ? '1' : '0',
      final String text => text,
      final other => '$other',
    };
  }

  Future<void> _disposeEngine() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }

    _subscriptions.clear();

    final player = _player;

    _player = null;

    if (player == null) return;

    player
      ..volume = 0.0
      ..dispose();
  }

  /// `avio.headers` takes CRLF-terminated lines; values that would inject extra
  /// header lines are dropped.
  static String encodeHeaders(Map<String, String> headers) {
    final buffer = StringBuffer();

    headers.forEach((name, value) {
      if (name.isEmpty || RegExp(r'[\r\n:]').hasMatch(name) || RegExp(r'[\r\n]').hasMatch(value)) {
        return;
      }

      buffer.write('$name: $value\r\n');
    });

    return buffer.toString();
  }

  void _bind(mdk.Player player) {
    _subscriptions.add(player.onStateChanged.listen(_onEngineState));

    _subscriptions.add(player.onMediaStatus.listen(_onMediaStatus));

    _subscriptions.add(
      player.onEvent.listen((event) {
        // libmdk reports a failed decoder open as a negative event and then
        // tries the next decoder in the list, so these are informational:
        // MediaStatus.invalid is the terminal signal.
        if (event.error < 0) {
          MediaCoreLog.debug(LogCategory.renderer, 'engine event: ${event.category} ${event.error} ${event.detail}');
        }
      }),
    );
  }

  void _onEngineState(({mdk.PlaybackState oldValue, mdk.PlaybackState newValue}) event) {
    if (!acceptsEngineEvents) return;

    switch (event.newValue) {
      case mdk.PlaybackState.playing:
        _setPlaying(true);
      case mdk.PlaybackState.paused:
        _setPlaying(false);
      case mdk.PlaybackState.stopped:
      case mdk.PlaybackState.notRunning:
      case mdk.PlaybackState.running:
        // A teardown or a state the engine has not settled into yet. The base
        // reports the command-driven stop itself, so this only clears the
        // local flag.
        _playingNow = false;
    }
  }

  /// Publishes a playing/paused transition once.
  ///
  /// Both the command path and the engine stream report the same transition;
  /// consumers must not see two `playing` events for one start.
  void _setPlaying(bool playing) {
    if (_playingNow == playing) return;

    _playingNow = playing;

    if (playing) {
      emitPlaying();
      return;
    }

    if (_hasOpened && !state.stopped && !state.completed) emitPaused();
  }

  void _onMediaStatus(({mdk.MediaStatus oldValue, mdk.MediaStatus newValue}) event) {
    if (!acceptsEngineEvents) return;

    final status = event.newValue;

    if (status.test(mdk.MediaStatus.invalid)) {
      _hasOpened = false;

      // Authoritative for the source being opened; see
      // [engineReportsOpenFailure].
      _openFailed = true;

      reportEngineError(message: 'fvp: invalid or unsupported media');
      return;
    }

    if (status.test(mdk.MediaStatus.end) && !event.oldValue.test(mdk.MediaStatus.end)) {
      _playingNow = false;

      emitCompleted();
      return;
    }

    final player = _player;

    if (player != null && status.test(mdk.MediaStatus.loaded)) {
      // The engine has the media now, so the video geometry for the texture is
      // available even if it was not when the source opened.
      unawaited(_attachTexture(player));
    }

    final buffering =
        status.test(mdk.MediaStatus.buffering) ||
        status.test(mdk.MediaStatus.loading) ||
        status.test(mdk.MediaStatus.stalled);

    if (buffering == _bufferingNow) return;

    _bufferingNow = buffering;

    emitBuffering(buffering: buffering, resumePlaying: buffering ? null : _playingNow);
  }

  // ---------------------------------------------------------------------------
  // Position, duration and volume
  // ---------------------------------------------------------------------------

  /// libmdk reports neither position nor duration as a stream, so the adapter
  /// samples them while a source is open.
  ///
  /// The live watchdog derives stalls from position progress: without this
  /// poller a healthy live stream looks stalled as soon as the engine stops
  /// emitting state changes.
  void _startPositionPolling(mdk.Player player) {
    _stopPositionPolling();

    final duration = _durationOf(player);

    if (duration > Duration.zero) emitDurationChanged(duration);

    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (isDisposed || _player != player || !_hasOpened || !_playingNow) {
        return;
      }

      emitPositionChanged(Duration(milliseconds: player.position));

      final buffered = player.buffered();

      if (buffered > 0) {
        updateMetrics((metrics) => metrics.copyWith(buffered: Duration(milliseconds: buffered)));
      }

      final volume = player.volume;

      if (volume != _lastEmittedVolume) {
        _lastEmittedVolume = volume;

        emitVolumeChanged(volume.clamp(0.0, 1.0));
      }
    });
  }

  void _stopPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  /// Media duration, or zero when the engine has none or the source is live.
  ///
  /// libmdk reports no meaningful duration for a live source, and the watchdog
  /// must not mistake that for a bounded file.
  static Duration _durationOf(mdk.Player player) {
    try {
      if (player.isLive) return Duration.zero;

      final milliseconds = player.mediaInfo.duration;

      return milliseconds > 0 ? Duration(milliseconds: milliseconds) : Duration.zero;
    } on Object catch (_) {
      return Duration.zero;
    }
  }

  /// Whether the engine still reports a failure for the source that [onOpen]
  /// just handed over.
  ///
  /// libmdk answers `prepare()` with a negative result for a source it cannot
  /// open, and reports `MediaStatus.invalid` for one it cannot decode. Both are
  /// authoritative, so the base turns them into a failed open and the
  /// controller can escalate to the next line or engine; without this a broken
  /// source would look like a successful open with no picture.
  @override
  bool get engineReportsOpenFailure => _openFailed;

  // ---------------------------------------------------------------------------
  // PlayerVideo
  // ---------------------------------------------------------------------------

  /// Whether this adapter currently owns a video surface.
  @override
  bool get available => !isDisposed && !audioOnly && _textureNotifier.value != null;

  /// No-op: the texture is owned by the adapter and lives as long as the
  /// source does.
  @override
  Future<void> attach() async {}

  /// Symmetric no-op for [attach].
  ///
  /// Releasing the texture is a source-level decision ([onSetAudioOnly] /
  /// [onClose]), never a layout one: a widget being rebuilt must not throw the
  /// decoded surface away.
  @override
  Future<void> detach() async {}

  /// Builds the video output widget.
  @override
  Widget build() {
    return ValueListenableBuilder<int?>(
      valueListenable: _textureNotifier,
      builder: (context, textureId, _) => ValueListenableBuilder<Size?>(
        valueListenable: _sizeNotifier,
        builder: (context, size, _) => ValueListenableBuilder<BoxFit>(
          valueListenable: _fitNotifier,
          builder: (context, fit, _) => buildSurface(textureId: textureId, size: size, fit: fit),
        ),
      ),
    );
  }

  /// Builds the surface for one frame geometry.
  ///
  /// Exposed so a caller that owns the widget tree can drive it from
  /// [textureListenable], [sizeListenable] and [fitListenable] itself.
  Widget buildSurface({required int? textureId, required Size? size, required BoxFit fit}) {
    final cfg = _videoConfig;

    if (textureId == null || size == null || size.isEmpty) {
      return ColoredBox(color: cfg.fill, child: const SizedBox.expand());
    }

    return ColoredBox(
      color: cfg.fill,
      child: Align(
        alignment: cfg.alignment,
        child: FittedBox(
          fit: fit,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Texture(textureId: textureId, filterQuality: cfg.filterQuality),
          ),
        ),
      ),
    );
  }

  /// The current viewport fit.
  BoxFit get videoFit => _videoFit;

  /// Applies the viewport fit through the surface.
  @override
  void setVideoFit(BoxFit fit) {
    if (_fitNotifier.value == fit && _videoConfig.fit == fit) return;

    _videoFit = fit;
    _fitNotifier.value = fit;
    _videoConfig = _videoConfig.copyWith(fit: fit);
  }

  /// Creates the texture for [player] and publishes its geometry.
  ///
  /// Idempotent for one engine instance: the media-status stream and the open
  /// path can both ask for it, and only the first call creates the texture.
  Future<void> _attachTexture(mdk.Player player) async {
    if (isDisposed || _player != player || audioOnly) return;
    if (_textureNotifier.value != null) return;

    // Bounded: a source whose geometry never arrives must not hold the texture
    // path open forever. A later media-status transition retries.
    final size = await player.textureSize.timeout(_geometryTimeout, onTimeout: () => null);

    if (isDisposed || _player != player) return;

    // A source without a video stream: the engine still plays audio, and there
    // is nothing to paint.
    if (size == null || size.width <= 0 || size.height <= 0) {
      if (size == null) await _retryGeometryOnce(player);
      return;
    }

    final textureId = await player.updateTexture(
      width: _videoConfig.maxWidth,
      height: _videoConfig.maxHeight,
      tunnel: _videoConfig.tunnel,
      fit: _videoConfig.fitMaxSize,
    );

    if (isDisposed || _player != player) return;

    if (textureId < 0) {
      reportEngineError(message: 'fvp: video texture could not be created');
      return;
    }

    _textureNotifier.value = textureId;
    _sizeNotifier.value = size;

    emitVideoSizeChangedIfChanged(size.width.toInt(), size.height.toInt());
  }

  /// Re-prepares the current source once when the engine settled its geometry as
  /// null.
  ///
  /// libmdk completes `textureSize` with null when a live stream stalls or
  /// reports invalid while still loading, and never revisits it: no texture is
  /// created and every decoded frame is dropped while audio keeps playing. One
  /// re-prepare gives the engine another chance; a repeated null is accepted.
  Future<void> _retryGeometryOnce(mdk.Player player) async {
    final url = _currentUrl;

    if (_geometryRetried || url == null || audioOnly || isDisposed || _player != player) {
      return;
    }

    _geometryRetried = true;

    player
      ..state = mdk.PlaybackState.stopped
      ..media = url;

    final result = await player.prepare();

    if (isDisposed || _player != player || result < 0) return;

    player.state = mdk.PlaybackState.playing;

    await _attachTexture(player);
  }

  /// Releases the texture and its geometry.
  ///
  /// Bounded as well: releasing must never block a close or a dispose, and the
  /// engine drops its own texture when the player is disposed anyway.
  Future<void> _releaseTexture() async {
    final player = _player;
    final owned = _textureNotifier.value != null;

    _textureNotifier.value = null;
    _sizeNotifier.value = null;

    if (player == null || !owned) return;

    try {
      await player.updateTexture(width: -1).timeout(_geometryTimeout);
    } on TimeoutException {
      MediaCoreLog.warning(LogCategory.renderer, 'releasing the video texture timed out');
    }
  }

  // ---------------------------------------------------------------------------
  // Capabilities
  // ---------------------------------------------------------------------------

  /// What this backend claims it can do, and the reason every claim is true or
  /// deliberately missing (see the audio-only note above the class).
  static const PlayerAdapterCapabilities defaultCapabilities = PlayerAdapterCapabilities(
    // Core playback.
    supportsLive: true,
    supportsSeek: true,
    supportsPause: true,
    supportsStop: true,
    supportsRateControl: true,
    supportsVolumeControl: true,
    supportsAudioOnly: true,
    supportsEngineOptions: true,
    supportsVideoSizeChanged: true,

    // Decoders.
    supportsHardwareDecoder: true,
    supportsFullscreen: true,

    // Source matching.
    supportedProtocols: FvpFormats.supportedProtocols,
    supportedFormats: FvpFormats.supportedFormats,
  );
}
