import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_better_player/media_core_better_player.dart';

// The package barrel carries the engine too (`better_player_plus` is
// re-exported from it), so this file does not import the engine directly.

/// Rewrites the data source a [BetterPlayerAdapter] is about to set up.
///
/// Receives the framework [PlayerSource] and the data source the adapter
/// mapped from it, returns the one to actually use.
typedef BetterPlayerDataSourceBuilder =
    BetterPlayerDataSource Function(PlayerSource source, BetterPlayerDataSource dataSource);

/// [PlayerAdapter] implementation backed by better_player_plus —
/// the  BetterPlayer engine.
///
/// This adapter also owns its video surface: it implements
/// [PlayerVideo] directly, so there is exactly one place that knows
/// how the texture is produced.
///
/// Engine semantics:
///
/// - source-scoped event acceptance with deferred errors
///   ( BetterPlayer can emit an exception synchronously while
///   setupDataSource is still pending) — provided by the base
/// - fit applied through `setOverriddenFit`, never a wrapper widget
/// - audio-output suppression starts the source muted, avoiding
///   an audible burst during initialization
/// - live streams flagged through the data source
/// - `play` / `pause` de-duplicated with a buffering guard:  BetterPlayer's
///   `onIsPlayingChanged` folds BUFFERING into `!isPlaying`, so a live
///   stream that briefly stalls flips play/pause at buffer frequency.
///   Those flips are not user-visible state changes, and forwarding
///   them verbatim drove downstream observers (facade → wallpaper
///   layer) into tearing down and rebuilding the background decoder
///   on every tick. Buffering is expressed through
///   [PlayerAdapterEvent.buffering] instead.
/// - an honest capability declaration ([BetterPlayerAdapter.defaultCapabilities])
final class BetterPlayerAdapter extends PlayerAdapterBase implements PlayerVideo {
  /// Creates a better_player adapter.
  ///
  /// A native [controller] may be injected; otherwise one is built from
  /// [configuration], [playlistConfiguration] and [dataSource], with
  /// [configureDataSource] as a last-chance transform per setup.
  BetterPlayerAdapter({
    super.id = kBetterPlayerBackendId,
    super.capabilities = defaultCapabilities,
    BetterPlayerController? controller,
    this.configuration,
    this.playlistConfiguration,
    this.dataSource,
    this.configureDataSource,
  }) : _injectedController = controller;

  final BetterPlayerController? _injectedController;

  BetterPlayerController? _controller;
  PlayerAdapterContext? _context;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// Native better_player configuration, applied verbatim when the
  /// controller is created; null uses the adapter's integration defaults.
  BetterPlayerConfiguration? configuration;

  /// Native playlist configuration, passed to the controller verbatim.
  BetterPlayerPlaylistConfiguration? playlistConfiguration;

  /// Native data source used ahead of any opened [PlayerSource].
  BetterPlayerDataSource? dataSource;

  /// Last-chance transform applied to every data source before setup.
  BetterPlayerDataSourceBuilder? configureDataSource;

  /// How the video is sized within its box, mirrored by [setVideoFit].
  BoxFit get videoFit => _videoFit;

  /// Applies the viewport fit through `setOverriddenFit`.
  ///
  /// Safe to call before [onInitialize]: the value is remembered and
  /// applied when the controller is created.
  @override
  void setVideoFit(BoxFit fit) {
    if (_videoFit == fit) return;

    _videoFit = fit;
    _controller?.setOverriddenFit(fit);
  }

  /// Replaces the engine configuration for later (re)creations.
  ///
  /// better_player locks its configuration at controller construction, so
  /// this only feeds the *next* controller. To make a new configuration
  /// effective on a running player, follow it with
  /// `handle.rebuildEngine()` — the fresh adapter created by the rebuild
  /// reads this config.
  void updateConfiguration({
    BetterPlayerConfiguration? configuration,
    BetterPlayerPlaylistConfiguration? playlistConfiguration,
    BetterPlayerDataSource? dataSource,
    BetterPlayerDataSourceBuilder? configureDataSource,
  }) {
    this.configuration = configuration ?? this.configuration;
    this.playlistConfiguration = playlistConfiguration ?? this.playlistConfiguration;
    this.dataSource = dataSource ?? this.dataSource;
    this.configureDataSource = configureDataSource ?? this.configureDataSource;
  }

  @override
  Future<List<EngineOptionOutcome>> onApplyEngineOptions(List<EngineOption> options) async {
    final controller = _controller;
    final outcomes = <EngineOptionOutcome>[];

    for (final option in options) {
      if (controller == null) {
        // The controller is born from the native configuration; raw options have
        // no creation-time surface here, so they cannot ride along.
        outcomes.add(EngineOptionOutcome.unsupported);

        continue;
      }

      // better_player has no key/value surface: a small set of options maps
      // onto live controller commands, everything else needs a rebuild.
      switch (option.key) {
        case 'volume':
          await controller.setVolume((option.value as num?)?.toDouble() ?? 1.0);
          outcomes.add(EngineOptionOutcome.appliedLive);

        case 'speed':
          await controller.setSpeed((option.value as num?)?.toDouble() ?? 1.0);
          outcomes.add(EngineOptionOutcome.appliedLive);

        case 'looping':
          await controller.setLooping(option.value == true);
          outcomes.add(EngineOptionOutcome.appliedLive);

        case 'mixWithOthers':
          controller.setMixWithOthers(option.value == true);
          outcomes.add(EngineOptionOutcome.appliedLive);

        default:
          outcomes.add(EngineOptionOutcome.needsRebuild);
      }
    }

    return outcomes;
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// Suppresses this engine's audio output: the volume is forced to zero when the
  /// source opens and auto-play is held back, which is what a video that plays
  /// behind another surface needs.
  bool audioOutputSuppressed = false;
  BoxFit _videoFit = BoxFit.contain;

  /// Whether the current source is live. Rate changes on a live stream
  /// are ignored — there is no meaningful playback speed for a broadcast.
  bool _liveSource = false;

  // Value-diff state. BetterPlayerEvent only carries *transitions*;
  // position / duration / buffered change silently between events and
  // are diffed off the wrapped controller's value below.
  Duration _lastPosition = Duration.zero;
  Duration? _lastDuration;

  // Prevents the same native exception from being reported through
  // both the BetterPlayer event stream and the open-failure state.
  String? _lastReportedError;

  /// Last "actually playing" state reported by the engine.
  ///
  ///  BetterPlayer's `onIsPlayingChanged` treats BUFFERING as not playing,
  /// so a live stream that briefly stalls emits pause + play at buffer
  /// frequency. Without de-duplication those events would be forwarded
  /// 1:1 as [PlayerAdapterEvent.playing] / [PlayerAdapterEvent.paused]
  /// transitions, which downstream consumers read as a real state
  /// change. Mirrors the guard in `MediaKitPlayerAdapter`.
  bool _playingNow = false;

  /// The underlying [BetterPlayerController].
  ///
  /// Throws [StateError] before [onInitialize].
  BetterPlayerController get controller {
    final c = _controller;

    if (c == null) {
      throw StateError('BetterPlayerAdapter has not been initialized.');
    }

    return c;
  }

  /// The underlying controller, or `null` before [onInitialize].
  BetterPlayerController? get controllerOrNull => _controller;

  // ---------------------------------------------------------------------------
  // PlayerVideo
  // ---------------------------------------------------------------------------

  /// Whether this adapter currently owns a video surface.
  ///
  /// False until [onInitialize] created the controller, and false
  /// after the adapter has been disposed.
  @override
  bool get available => !isDisposed && _controller != null;

  /// Builds the video output widget.
  ///
  /// The returned widget is owned by this adapter and must be inserted
  /// into the application's widget tree by the surface layer.
  @override
  Widget build() {
    final c = _controller;
    if (c == null) {
      return const SizedBox.shrink();
    }
    return BetterPlayer(controller: c);
  }

  /// No-op: BetterPlayer owns its own surface lifecycle.
  @override
  Future<void> attach() async {}

  /// Symmetric no-op for [attach].
  @override
  Future<void> detach() async {}

  // ---------------------------------------------------------------------------
  // Engine contract
  // ---------------------------------------------------------------------------

  @override
  Future<void> onInitialize(PlayerAdapterContext context) async {
    _context = context;
    _lastReportedError = null;

    final injected = _injectedController;

    if (injected != null) {
      _controller = injected;

      // The injected controller is externally created, but the adapter
      // still owns the presentation fit requested through PlayerVideo.
      injected.setOverriddenFit(_videoFit);
    } else {
      final base =
          configuration ??
          const BetterPlayerConfiguration(
            handleLifecycle: false,
            controlsConfiguration: BetterPlayerControlsConfiguration(showControls: false),
          );

      _controller = BetterPlayerController(
        base.copyWith(autoPlay: base.autoPlay && !audioOutputSuppressed, fit: _videoFit),
        betterPlayerPlaylistConfiguration: playlistConfiguration,
        betterPlayerDataSource: dataSource,
      );
    }

    controller.addEventsListener(_onEngineEvent);
  }

  @override
  bool get engineReportsOpenFailure {
    if (_controller?.videoPlayerController?.value.hasError == true) {
      return true;
    }

    // Some failures surface as an exception event while hasError is
    // still false (source-type errors, for example).
    return _lastReportedError != null;
  }

  @override
  Future<void> onOpen(PlayerSource source) async {
    // A new source starts a new error reporting scope.
    _lastReportedError = null;
    _liveSource = source.isLive;

    // A controller can be reused for multiple sources. Make sure the
    // value listener is registered exactly once for the current source.
    final oldVpc = controller.videoPlayerController;
    oldVpc?.removeListener(_onValueChange);

    // Prefer an explicitly configured data source; otherwise map the
    // framework-provided source.
    var resolvedDataSource = dataSource;

    if (resolvedDataSource == null) {
      final resolved = _resolveSource(source);

      if (resolved == null) {
        throw StateError(
          'BetterPlayerAdapter cannot open ${source.uri} '
          '(unsupported source type).',
        );
      }

      resolvedDataSource = BetterPlayerDataSource(
        resolved.$1,
        resolved.$2,
        headers: source.hasHeaders ? Map<String, String>.from(source.headers!.values) : null,
        // `isLive` is a source-level hint; do not hardcode it.
        liveStream: source.isLive,
      );
    }

    // Per-open rewrite on top of whichever source was chosen above.
    final transform = configureDataSource;

    if (transform != null) {
      resolvedDataSource = transform(source, resolvedDataSource);
    }

    await controller.setupDataSource(resolvedDataSource);

    if (isDisposed) return;

    // Attach the value listener only after setupDataSource so the first
    // snapshot reflects an initialized controller.
    final vpc = controller.videoPlayerController;

    if (vpc != null) {
      vpc
        ..removeListener(_onValueChange)
        ..addListener(_onValueChange);

      final value = vpc.value;

      _lastPosition = value.position;
      _lastDuration = value.duration;

      final size = value.size;

      if (size != null && size.width > 0 && size.height > 0) {
        emitVideoSizeChangedIfChanged(size.width.toInt(), size.height.toInt());
      }

      // A progressive source (mp4 over https) finishes initialization inside
      // setupDataSource, so its duration is already present in the value
      // above. Seeding the diff latch with it means _onValueChange can never
      // observe a duration CHANGE, and emitDurationChanged would never fire
      // for the whole playback. The gate is open inside onOpen, so the
      // known duration is emitted here — mirroring the size handling above.
      final duration = value.duration;

      if (duration != null && duration > Duration.zero) {
        emitDurationChanged(duration);
      }
    }

    if (isDisposed) return;

    // Apply the context config once — nothing in better_player_plus
    // does this automatically.
    final contextConfig = _context?.config ?? const PlayerAdapterConfig();

    if (contextConfig.volume != 1.0) {
      await controller.setVolume(contextConfig.volume);
    }

    if (isDisposed) return;

    if (contextConfig.playbackRate != 1.0) {
      await controller.setSpeed(contextConfig.playbackRate);
    }
  }

  @override
  Future<void> onAfterOpen(PlayerSource source) async {
    // Audio suppression is intentionally applied after the source has
    // been created, so the native player never emits audible output
    // during source initialization. Otherwise the volume configured on
    // the adapter context is restored — an unconditional 1.0 used to
    // reset any non-default volume on every open.
    final contextConfig = _context?.config ?? const PlayerAdapterConfig();

    await setVolume(audioOutputSuppressed ? 0.0 : contextConfig.volume);

    if (isDisposed) return;

    // A suppressed open used to force autoplay, ignoring the caller's
    // autoPlay: false. Start playback only when the caller asked for it.
    final autoPlay = _context?.playerConfig?.autoPlay ?? true;

    if (audioOutputSuppressed && autoPlay) {
      await play();
    }
  }

  @override
  Future<void> onPlay() => controller.play();

  @override
  Future<void> onPause() => controller.pause();

  @override
  Future<void> onStop() async {
    await controller.pause();

    if (isDisposed) return;

    // The pause event above may have been filtered as buffering noise,
    // so reset the latch explicitly instead of relying on event order.
    _playingNow = false;

    // A live stream has no rewindable timeline: seeking to zero either
    // restarts the DVR window or is rejected outright.
    if (_liveSource) return;

    await controller.seekTo(Duration.zero);
  }

  @override
  Future<void> onSeek(Duration position) => controller.seekTo(position);

  @override
  Future<void> onSetVolume(double volume) => controller.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> onSetRate(double rate) => controller.setSpeed(rate);

  @override
  Future<void> onClose() async {
    // Detach the value listener before winding the controller down so a
    // late tick cannot leak into the next source's diff state.
    controller.videoPlayerController?.removeListener(_onValueChange);

    _lastPosition = Duration.zero;
    _lastDuration = null;
    _lastReportedError = null;
    _playingNow = false;

    await controller.pause();

    if (isDisposed) return;

    // Reset the native position when possible. A source that has already
    // failed may reject seekTo, so closing should not be made fragile by
    // a best-effort cleanup operation.
    try {
      await controller.seekTo(Duration.zero);
    } on Object catch (_) {
      // Best-effort cleanup.
    }
  }

  @override
  Future<void> onDispose() async {
    // better_player returns early from dispose() when autoDispose is false,
    // and this adapter sets it false to own the lifecycle itself. Without
    // forceDispose the native  BetterPlayer survives — decoder, surface and
    // audio included — so the next engine switch fights it for the hardware
    // decoder and a closed room keeps playing behind the UI.
    final controller = _controller;
    _controller = null;

    if (controller != null) {
      controller
        ..videoPlayerController?.removeListener(_onValueChange)
        ..removeEventsListener(_onEngineEvent)
        ..dispose(forceDispose: true);
    }

    _context = null;
    _lastPosition = Duration.zero;
    _lastDuration = null;
    _lastReportedError = null;
    _playingNow = false;
  }

  // ---------------------------------------------------------------------------
  // Extensions
  // ---------------------------------------------------------------------------

  // Audio-only is not implemented for this engine, and the capability
  // declaration says so: better_player_plus exposes no video-track
  // control at any layer — `setTrack` only picks among adaptive video
  // variants, and the platform channel behind it has no "disable video
  // renderer" method — so the decoder cannot be switched off. The
  // audio-only playback mode is therefore honored by the presentation
  // layer, which stops mounting this engine's surface and shows the
  // audio panel instead; video keeps decoding underneath.

  // ---------------------------------------------------------------------------
  // Source resolution
  // ---------------------------------------------------------------------------

  /// Maps a [PlayerSource] onto a better_player data-source type + URI.
  ///
  /// Returns `null` for unsupported schemes so [onOpen] can fail
  /// loudly instead of handing garbage to  BetterPlayer.
  (BetterPlayerDataSourceType, String)? _resolveSource(PlayerSource source) {
    if (source.isFile) {
      return (BetterPlayerDataSourceType.file, source.uri.toFilePath());
    }

    if (source.isNetworkSource) {
      return (BetterPlayerDataSourceType.network, source.uri.toString());
    }

    // The installed better_player_plus version exposes:
    //
    //   network
    //   file
    //   memory
    //
    // It does NOT expose an `asset` data-source type. If asset playback
    // is required later, the asset bytes must first be loaded and passed
    // through the memory data-source API.
    if (source.isAsset) {
      return null;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Engine events (transitions only)
  // ---------------------------------------------------------------------------

  void _onEngineEvent(BetterPlayerEvent event) {
    if (!acceptsEngineEvents) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
      case BetterPlayerEventType.changedResolution:
        final size = _controller?.videoPlayerController?.value.size;

        if (size != null && size.width > 0 && size.height > 0) {
          emitVideoSizeChangedIfChanged(size.width.toInt(), size.height.toInt());
        }

      case BetterPlayerEventType.play:
        if (_playingNow) return;

        _playingNow = true;
        emitPlaying();

      case BetterPlayerEventType.pause:
        // A "pause" that lands while the player is buffering is not a
        // user-visible pause:  BetterPlayer reports !isPlaying during
        // BUFFERING and replays a matching `play` once the buffer
        // recovers. Dropping it here keeps the latch accurate and lets
        // bufferingStart / bufferingEnd express the stall instead.
        final buffering = _controller?.videoPlayerController?.value.isBuffering ?? false;

        if (buffering) return;

        if (!_playingNow) return;

        _playingNow = false;
        emitPaused();

      case BetterPlayerEventType.bufferingStart:
        emitBuffering(buffering: true);

      case BetterPlayerEventType.bufferingEnd:
        emitBuffering(buffering: false, resumePlaying: state.playing);

      case BetterPlayerEventType.finished:
        emitCompleted();

      case BetterPlayerEventType.exception:
        final message = event.parameters?['exception']?.toString() ?? 'BetterPlayer Error';

        // BetterPlayer may expose the same native failure both as an
        // exception event and through videoPlayerController.value.hasError.
        // Keep one error flowing into media_core for the same message.
        if (_lastReportedError == message) return;

        _lastReportedError = message;
        reportEngineError(message: message);

      // BetterPlayerEventType may carry members this adapter intentionally
      // ignores (and can gain more across engine releases); a default drops
      // them rather than breaking here.
      // ignore: no_default_cases
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Value listener (position / duration / buffered)
  //
  // The engine events above only tell us *what mode* the player is in.
  // The wrapped controller's value is where the numbers live.
  // ---------------------------------------------------------------------------

  void _onValueChange() {
    if (!acceptsEngineEvents) return;

    final vpc = _controller?.videoPlayerController;

    if (vpc == null) return;

    final v = vpc.value;

    // Position.
    if (v.position != _lastPosition) {
      _lastPosition = v.position;
      emitPositionChanged(v.position);
    }

    // Duration (live streams report zero or null).
    final duration = v.duration;

    if (duration != _lastDuration) {
      _lastDuration = duration;

      if (duration != null && duration > Duration.zero) {
        emitDurationChanged(duration);
      }
    }

    // Buffered range → metrics. Never emitted as a ratio, so
    // supportsBufferingProgress stays false.
    if (v.buffered.isNotEmpty) {
      final end = v.buffered.last.end;

      if (end != metrics.buffered) {
        updateMetrics((m) => m.copyWith(buffered: end));
      }
    }

    // Size. Also emitted here (not only on the change events) because a
    // mid-stream reconfig can land on a value tick before any
    // changedResolution event arrives.
    final size = v.size;

    if (size != null && size.width > 0 && size.height > 0) {
      emitVideoSizeChangedIfChanged(size.width.toInt(), size.height.toInt());
    }
  }

  // ---------------------------------------------------------------------------
  // Capabilities
  // ---------------------------------------------------------------------------

  /// Capabilities of the  BetterPlayer engine, as exposed by this adapter.
  static const PlayerAdapterCapabilities defaultCapabilities = PlayerAdapterCapabilities(
    // Core playback.
    supportsLive: true,
    supportsSeek: true,
    supportsPause: true,
    supportsStop: true,
    supportsRateControl: true,
    supportsVolumeControl: true,
    supportsMuteControl: true,
    supportsVideoSizeChanged: true,

    // Decoders.
    supportsHardwareDecoder: true,
    supportsSoftwareDecoder: false,
    supportsFullscreen: true,

    // Source matching.
    supportedProtocols: BetterPlayerFormats.supportedProtocols,
    supportedFormats: BetterPlayerFormats.supportedFormats,
  );
}
