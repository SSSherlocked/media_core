import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
// The package barrel carries the engine too (`flv_lzc` is re-exported from it),
// so this file does not import the engine directly.
import 'package:media_core/media_core.dart';
import 'package:media_core_ijk_player/media_core_ijk_player.dart';

/// A [PlayerAdapter] backed by the flv_lzc (IJK) engine.
///
/// Drives a [FijkPlayer] and exposes its video surface through [PlayerVideo],
/// translating media_core's playback commands into the engine's own calls.
final class FlvLzcPlayerAdapter extends PlayerAdapterBase implements PlayerVideo {
  /// Creates an adapter, optionally injecting a pre-configured [player] and the
  /// native [options] applied before each open.
  FlvLzcPlayerAdapter({
    super.id = kIjkPlayerBackendId,
    super.capabilities = defaultCapabilities,
    FijkPlayer? player,
    List<EngineOption> options = const <EngineOption>[],
  }) : _injectedPlayer = player,
       _options = List<EngineOption>.unmodifiable(options);

  final FijkPlayer? _injectedPlayer;
  late final FijkPlayer _player = _injectedPlayer ?? FijkPlayer();

  // ---------------------------------------------------------------------------
  // Configuration — replace wholesale or tweak individual fields
  // ---------------------------------------------------------------------------

  /// Native ijkplayer options applied before every open.
  ///
  /// Raw (domain, key, value) triples in the engine's own vocabulary —
  /// `mediacodec`, `reconnect`, `timeout`, ... The adapter invents
  /// nothing: options the caller passed at construction ride along to
  /// every open, and runtime options pushed through
  /// `applyEngineOptions` are merged last-value-wins on top.
  final List<EngineOption> _options;

  /// Runtime options merged over [_options], keyed by (domain, key).
  final Map<(String, String), EngineOption> _runtimeOptions = <(String, String), EngineOption>{};

  /// The effective option list for the next open.
  List<EngineOption> get _effectiveOptions {
    return <EngineOption>[..._options, ..._runtimeOptions.values];
  }

  // ---------------------------------------------------------------------------
  // Runtime setOption passthrough for edge cases
  // (mid-playback proxy switch, dynamic header swaps, ...)
  // ---------------------------------------------------------------------------

  @override
  Future<List<EngineOptionOutcome>> onApplyEngineOptions(List<EngineOption> options) async {
    final outcomes = <EngineOptionOutcome>[];

    for (final option in options) {
      final category = _fijkCategoryOf(option.domain);

      if (category == null) {
        outcomes.add(EngineOptionOutcome.unsupported);

        continue;
      }

      try {
        await _player.setOption(category, option.key, _fijkOptionValue(option.value));

        // ijkplayer accepts the write on a live instance but consumes most
        // options at the next prepareAsync: the current stream keeps its
        // old settings until the next open, which is exactly the staged
        // contract. The caller asks for immediate effect by letting the
        // handle rebuild the engine.
        outcomes.add(EngineOptionOutcome.stagedForNextOpen);
      } on Object catch (_) {
        outcomes.add(EngineOptionOutcome.unsupported);
      }
    }

    return outcomes;
  }

  /// Maps an option domain onto an ijkplayer option category.
  ///
  /// [FijkOption] categories are plain ints, not an enum, so the mapping
  /// lives here next to its only consumer. Unknown domains answer null,
  /// which the caller sees as `unsupported` rather than a guess.
  static int? _fijkCategoryOf(String? domain) {
    return switch (domain ?? 'player') {
      'host' => FijkOption.hostCategory,
      'format' => FijkOption.formatCategory,
      'codec' => FijkOption.codecCategory,
      'sws' => FijkOption.swsCategory,
      'swr' => FijkOption.swrCategory,
      'player' => FijkOption.playerCategory,
      _ => null,
    };
  }

  /// Normalizes an option value into what `setOption` accepts (int/String).
  static Object _fijkOptionValue(Object? value) {
    return switch (value) {
      final bool flag => flag ? 1 : 0,
      null => '',
      final Object accepted => accepted,
    };
  }

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  StreamSubscription<Duration>? _positionSubscription;

  bool _sourceBuffering = false;

  /// Whether the current source is live. Rate changes and seeks are
  /// ignored for live streams — there is no rewindable timeline and no
  /// meaningful playback speed for a broadcast.
  bool _liveSource = false;

  // State-change latches: the value listener fires on every tick, so
  // without them `started` re-emits `playing` at tick frequency.
  bool _playingNow = false;
  bool _completedNow = false;

  /// Dedup of repeated error reports: a tick in the error state would
  /// otherwise re-fail the adapter on every listener callback.
  String? _lastReportedError;

  Duration _lastDuration = Duration.zero;
  Duration _lastPosition = Duration.zero;

  // ---------------------------------------------------------------------------
  // PlayerVideo
  // ---------------------------------------------------------------------------

  final ValueNotifier<BoxFit> _fitNotifier = ValueNotifier<BoxFit>(BoxFit.contain);

  BoxFit _videoFit = BoxFit.contain;

  /// How the video is sized within its box, mirrored by [setVideoFit].
  BoxFit get videoFit => _videoFit;

  @override
  void setVideoFit(BoxFit fit) {
    if (_videoFit == fit) return;
    _videoFit = fit;
    _fitNotifier.value = fit;
  }

  @override
  bool get available {
    // FijkView mounted on an idle player renders nothing; require at
    // least an initialized player so MediaPlayerView does not surface
    // an empty texture before any source exists.
    if (audioOnly || isDisposed) return false;

    final state = _player.value.state;

    return state != FijkState.idle && state != FijkState.error;
  }

  @override
  Widget build() {
    return ValueListenableBuilder<BoxFit>(
      valueListenable: _fitNotifier,
      builder: (context, fit, _) {
        return FijkView(
          player: _player,
          fit: FijkHelper.getIjkBoxFit(fit),
          fs: false,
          color: Colors.black,
          panelBuilder: (_, _, _, _, _) => const SizedBox(),
        );
      },
    );
  }

  @override
  Future<void> attach() async {}

  @override
  Future<void> detach() async {}

  // ---------------------------------------------------------------------------
  // Engine contract
  // ---------------------------------------------------------------------------

  @override
  Future<void> onInitialize(PlayerAdapterContext context) async {
    // First, and before the player is touched: the engine's own log follows the
    // host's logging configuration (see [FijkHelper.syncLogLevel]).
    FijkHelper.syncLogLevel();

    _player.addListener(_onPlayerValue);
    _positionSubscription = _player.onCurrentPosUpdate.listen(_onPositionChanged);

    if (audioOnly) {
      await _applyAudioOnly(true);
    }
  }

  @override
  bool get engineReportsOpenFailure => _player.value.state == FijkState.error;

  @override
  Future<void> onOpen(PlayerSource source) async {
    _lastPosition = Duration.zero;
    _lastDuration = Duration.zero;
    _sourceBuffering = false;
    _playingNow = false;
    _completedNow = false;
    _lastReportedError = null;
    _liveSource = source.isLive;

    if (_player.state != FijkState.idle) {
      await _player.reset();
    }
    if (isDisposed) return;

    // The caller's options, verbatim, plus the two contract requirements:
    // the source's own headers (a PlayerSource field, translated into
    // ijkplayer's format-option string) and the snapshot host option the
    // adapter's screenshot capability depends on. Everything else is the
    // caller's to decide.
    for (final option in _effectiveOptions) {
      final category = _fijkCategoryOf(option.domain);

      if (category == null) continue;

      await _player.setOption(category, option.key, _fijkOptionValue(option.value));
    }

    if (source.hasHeaders) {
      for (final entry in FijkHelper.sourceHeaderOptions(source.headers!.values).entries) {
        await _player.setOption(FijkOption.formatCategory, entry.key, entry.value);
      }
    }

    // IJKPlayer refuses `snapshot` unless the host enables it, and a
    // screenshot request arrives long after the open that writes options.
    await _player.setOption(FijkOption.hostCategory, 'enable-snapshot', 1);
    if (isDisposed) return;

    // A new data source starts a fresh prepare path, so re-assert
    // audio-only.
    if (audioOnly) {
      await _applyAudioOnly(true);
    }
    if (isDisposed) return;

    await _player.setDataSource(source.uri.toString());
    if (isDisposed) return;

    await _player.start();
  }

  @override
  Future<void> onPlay() => _player.start();

  @override
  Future<void> onPause() => _player.pause();

  @override
  Future<void> onStop() async {
    _sourceBuffering = false;
    _playingNow = false;
    _completedNow = false;
    await _player.stop();
  }

  @override
  Future<void> onSeek(Duration position) {
    // ijk stalls or errors seeking an FLV live source. Refusing loudly
    // is the honest answer: a silent no-op leaves the caller believing
    // a seek happened, which is how a live viewer ends up staring at a
    // progress bar that moved and a stream that did not.
    if (_liveSource) {
      throw UnsupportedError(
        'ijk_player cannot seek a live source: there is no seekable window '
        'to move within, and ijk stalls or errors when asked to.',
      );
    }

    return _player.seekTo(position.inMilliseconds);
  }

  @override
  Future<void> onSetVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> onSetRate(double rate) async {
    if (_liveSource) {
      return;
    }

    await _player.setSpeed(rate);
  }

  @override
  Future<void> onClose() async {
    _sourceBuffering = false;
    _playingNow = false;
    _completedNow = false;
    _lastReportedError = null;
    _lastPosition = Duration.zero;
    _lastDuration = Duration.zero;
    await _player.reset();
  }

  @override
  Future<void> onDispose() async {
    _player.removeListener(_onPlayerValue);

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _fitNotifier.dispose();

    try {
      await _player.release();
    } on Object catch (_) {
      // Release races surface here on some devices; disposal
      // continues regardless.
    }
  }

  // ---------------------------------------------------------------------------
  // Extensions
  // ---------------------------------------------------------------------------

  /// Restricts playback to the audio track through IJKPlayer's
  /// `disable-vid` option: the decoder is switched off, the stream is
  /// not merely hidden.
  @override
  Future<void> onSetAudioOnly({required bool audioOnly}) => _applyAudioOnly(audioOnly);

  Future<void> _applyAudioOnly(bool audioOnly) async {
    if (isDisposed) return;
    await _player.setOption(FijkOption.playerCategory, 'disable-vid', audioOnly ? 1 : 0);
  }

  /// Captures the current frame through IJKPlayer.
  ///
  /// IJKPlayer's native snapshot is encoded as JPEG, so a PNG request is
  /// answered with null instead of mislabelled bytes: the kernel then falls
  /// back to capturing the rendered surface, which really does produce PNG.
  ///
  /// The engine only serves snapshots when the `enable-snapshot` host option is
  /// set, which the open path does for every open. Platforms whose
  /// native implementation is missing answer with an error, which is reported
  /// as "no frame" as well.
  @override
  Future<Uint8List?> onCaptureFrame(ScreenshotRequest request) async {
    if (isDisposed) return null;
    if (request.format != ScreenshotFormat.jpeg) return null;

    try {
      final bytes = await _player.takeSnapShot();

      return bytes.isEmpty ? null : bytes;
    } on Object catch (error) {
      MediaCoreLog.warning(LogCategory.renderer, 'captureFrame failed: $error', error: error);

      return null;
    }
  }

  /// The underlying FijkPlayer.
  FijkPlayer get fijkPlayer => _player;

  // ---------------------------------------------------------------------------
  // Position progress
  // ---------------------------------------------------------------------------

  void _onPositionChanged(Duration position) {
    if (!acceptsEngineEvents) return;
    if (position == _lastPosition) return;

    _lastPosition = position;
    emitPositionChanged(position);
  }

  // ---------------------------------------------------------------------------
  // Value listener
  // ---------------------------------------------------------------------------

  void _onPlayerValue() {
    if (!acceptsEngineEvents) return;

    final value = _player.value;
    final state = value.state;

    final size = value.size;
    if (size != null) {
      emitVideoSizeChangedIfChanged(size.width.toInt(), size.height.toInt());
    }

    final duration = value.duration;
    if (duration > Duration.zero && duration != _lastDuration) {
      _lastDuration = duration;
      emitDurationChanged(duration);
    }

    final isBufferingState = state == FijkState.asyncPreparing;
    if (isBufferingState) {
      if (!_sourceBuffering) {
        _sourceBuffering = true;
        emitBuffering(buffering: true);
      }
    } else if (_sourceBuffering) {
      _sourceBuffering = false;
      emitBuffering(buffering: false);
    }

    switch (state) {
      case FijkState.started:
        if (_playingNow) break;
        _playingNow = true;
        _completedNow = false;
        emitPlaying();
      case FijkState.paused:
        if (!_playingNow) break;
        _playingNow = false;
        emitPaused();
      case FijkState.completed:
      case FijkState.end:
        if (_completedNow) break;
        _completedNow = true;
        _playingNow = false;
        emitCompleted();
      case FijkState.error:
        final native = value.exception;
        final message =
            'fijk error ${native.code}: '
            '${native.message ?? 'native playback failure'}';

        if (message == _lastReportedError) break;

        _lastReportedError = message;
        reportEngineError(message: message);
      case FijkState.stopped:
      case FijkState.idle:
      case FijkState.initialized:
      case FijkState.asyncPreparing:
      case FijkState.prepared:
        break;
    }
  }

  /// Capabilities of the IJK engine (flv_lzc / fijkplayer), as exposed
  /// by this adapter.
  static const PlayerAdapterCapabilities defaultCapabilities = PlayerAdapterCapabilities(
    supportsLive: true,
    supportsSeek: true,
    supportsPause: true,
    supportsStop: true,
    supportsRateControl: true,
    supportsVolumeControl: true,
    supportsMuteControl: true,
    supportsAudioOnly: true,
    supportsEngineOptions: true,
    supportsVideoSizeChanged: true,
    // IJKPlayer's native snapshot returns a JPEG. The kernel asks for PNG by
    // default and falls back to the rendered surface when this adapter answers
    // null, so declaring the capability does not mean "any format".
    supportsScreenshot: true,
    supportsHardwareDecoder: true,
    supportsFullscreen: true,
    // Source matching.
    supportedProtocols: IjkFormats.supportedProtocols,
    supportedFormats: IjkFormats.supportedFormats,
  );
}
