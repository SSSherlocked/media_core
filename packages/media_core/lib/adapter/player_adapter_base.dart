import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show protected;
import 'package:media_core/adapter/composite_support.dart';
import 'package:media_core/adapter/engine_option.dart';
import 'package:media_core/adapter/player_adapter.dart';
import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/adapter/player_adapter_context.dart';
import 'package:media_core/adapter/player_adapter_event.dart';
import 'package:media_core/adapter/player_adapter_exception.dart';
import 'package:media_core/adapter/player_adapter_metrics.dart';
import 'package:media_core/core/player_core_state.dart';
import 'package:media_core/core/player_error.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/playback/buffer_range.dart';
import 'package:media_core/screenshot/screenshot_request.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_source_bridge.dart';
import 'package:media_core/source/player_source.dart';

/// Template-method base for [PlayerAdapter] implementations.
///
/// [PlayerAdapterBase] owns the scaffolding every backend needs —
/// the event stream, the state machine, lifecycle guards,
/// source-scoped event acceptance and error normalization through
/// [PlayerError] — so a concrete adapter only overrides the engine
/// hooks:
///
/// - [onInitialize] creates the engine and binds its listeners
/// - [onBeforeOpen] / [onOpen] / [onAfterOpen] hand a source over
/// - [onPlay], [onPause], [onStop], [onSeek], [onSetVolume] and
///   [onSetRate] execute the playback commands
/// - [onClose] / [onDispose] release the engine
///
/// Engine callbacks report what happened through the `emit*`
/// helpers. Reports are dropped while the source gate is closed
/// (see [gatesSourceEvents]), and a failure arriving during the
/// open window is deferred until [open] settles, where it either
/// fails the open through [PlayerAdapterOpenException] or is
/// dropped when the engine reports the source as healthy.
///
/// Capability handling follows the single-source-of-truth rule:
/// the only place a `supportsXxx` flag exists is
/// [PlayerAdapterCapabilities]. This base reads [_capabilities]
/// directly and never re-exposes a capability as its own getter,
/// field, or constructor parameter.
///
/// Which `emit*` helpers are capability-gated:
///
/// - **Signal emits** are gated. They describe a signal the adapter
///   promised to produce, and a call without the corresponding
///   capability is a producer contract violation:
///   - [emitVideoFrameProgress] ↔ `supportsVideoFrameProgress`
///   - [emitVideoSizeChanged] ↔ `supportsVideoSizeChanged`
///   - `emitBuffering(progress: …)` ↔ `supportsBufferingProgress`
/// - **Fact emits** are not gated. They describe an engine state
///   transition that has already happened (`playing`, `paused`,
///   `positionChanged`, `volumeChanged`, …). A backend that pauses
///   without declaring `supportsPause` is describing a real event
///   and the report must not be suppressed.
/// - **Command capabilities** (`supportsSeek`, `supportsPause`,
///   `supportsRateControl`, `supportsVolumeControl`, `supportsAudioOnly`, …)
///   do not map to any `emit*` at all; consumers use them to decide which
///   commands to attempt.
///
/// Responsibilities:
///
/// - run the adapter lifecycle templates
/// - publish normalized adapter events
/// - normalize engine failures into [PlayerError]
///
/// It does not:
///
/// - create engine instances (that is [onInitialize])
/// - interpret engine payloads (that is the `emit*` callers)
/// - select backends or retry opens
///
/// Those belong to:
///
/// - PlayerAdapterFactory
/// - LivePlaybackController / FallbackManager
abstract base class PlayerAdapterBase implements PlayerAdapter {
  /// Creates the adapter.
  ///
  /// [capabilities] defaults to a conservative baseline: no optional
  /// capability is declared. Adapters that support more pass an
  /// explicit [PlayerAdapterCapabilities] instance.
  PlayerAdapterBase({String? id, PlayerAdapterCapabilities? capabilities})
    : _id = id ?? 'adapter',
      _capabilities = capabilities ?? const PlayerAdapterCapabilities();

  final String _id;
  final PlayerAdapterCapabilities _capabilities;

  PlayerCoreState _state = PlayerCoreState.idle;
  PlayerAdapterMetrics _metrics = const PlayerAdapterMetrics();

  Duration _position = Duration.zero;
  Duration? _duration;

  bool _initialized = false;
  bool _disposed = false;
  bool _audioOnly = false;

  // Source-scoped event acceptance with deferred open errors.
  bool _acceptSourceEvents = false;
  bool _sourceOpening = false;
  PlayerError? _deferredEngineError;

  // Last video geometry published for the current source; the
  // deduplicating size helper compares against it.
  int? _lastReportedWidth;
  int? _lastReportedHeight;

  final StreamController<PlayerAdapterEvent> _eventController = StreamController<PlayerAdapterEvent>.broadcast();

  @override
  String get id => _id;

  @override
  PlayerAdapterCapabilities get capabilities => _capabilities;

  @override
  PlayerCoreState get state => _state;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => _duration;

  @override
  PlayerAdapterMetrics get metrics => _metrics;

  @override
  Stream<PlayerAdapterEvent> get events => _eventController.stream;

  @override
  bool get initialized => _initialized;

  /// Whether the adapter has been disposed.
  @protected
  bool get isDisposed => _disposed;

  /// Whether playback is currently restricted to the audio track.
  ///
  /// This is runtime state, not a capability: the adapter that owns a
  /// video track reads it in [onAfterOpen] to re-apply the setting after
  /// a source was (re)opened behind the application's back.
  @protected
  bool get audioOnly => _audioOnly;

  /// Whether engine-reported events are scoped to the source
  /// currently being opened.
  ///
  /// When true (the default), engine reports published before the
  /// first [open] and after [stop] / [close] are dropped, so a
  /// previous source's late events never leak into the next
  /// generation. Engines whose event subscriptions are bound once
  /// for the whole adapter lifetime and rely on the engine itself to
  /// detach stale payloads can turn the gate off.
  @protected
  bool get gatesSourceEvents => true;

  /// Whether engine-originated reports may currently be published.
  @protected
  bool get acceptsEngineEvents => !_disposed && (!gatesSourceEvents || _acceptSourceEvents);

  /// Whether the engine still reports a failure for the source that
  /// [onOpen] just handed over.
  ///
  /// Only consulted when a deferred engine error arrived during the
  /// open window; a source the engine considers healthy accepts the
  /// open even if a stale error was seen while it was setting up.
  @protected
  bool get engineReportsOpenFailure => false;

  // ---------------------------------------------------------------------------
  // Lifecycle templates
  // ---------------------------------------------------------------------------

  @override
  Future<void> initialize(PlayerAdapterContext context) async {
    if (_initialized) return;

    await onInitialize(context);

    _state = _state.initializingState().readyState();
    _initialized = true;
  }

  @override
  Future<void> open(PlayerSource source) async {
    requireReady();

    // Composite-on-none is the failure the whole planner layer exists
    // to prevent, but open() is public and a caller can bypass
    // PlayerKernel.createFromMedia (or a resolver can hand the
    // bridged source straight to the wrong backend after a runtime
    // adapter swap). Refusing here — before the engine ever sees the
    // URL — is what guarantees a DASH pair can never degrade into
    // "video plays, audio silently missing".
    _rejectUnsupportedComposite(source);

    // Source-scoped reset: the previous source's late events must
    // not leak into this generation.
    _acceptSourceEvents = false;
    _deferredEngineError = null;
    _lastReportedWidth = null;
    _lastReportedHeight = null;
    _position = Duration.zero;
    _duration = null;

    try {
      await onBeforeOpen(source);

      // The engine can emit an exception while the source setup is
      // still pending. Bind that error to this source instead of
      // dropping the only event before the gate opens.
      _sourceOpening = true;
      _acceptSourceEvents = true;

      try {
        await onOpen(source);
      } finally {
        _sourceOpening = false;
      }

      final deferred = _deferredEngineError;
      _deferredEngineError = null;

      if (deferred != null && engineReportsOpenFailure) {
        _acceptSourceEvents = false;
        _fail(deferred);
        throw PlayerAdapterOpenException(deferred);
      }

      _state = _state.openingState().withSource(value: true).readyState();

      _addEvent(PlayerAdapterEvent.opened(source: source.id.value));

      await onAfterOpen(source);
    } catch (error, stackTrace) {
      _sourceOpening = false;
      _acceptSourceEvents = false;

      if (error is! PlayerAdapterOpenException) {
        _fail(
          PlayerError(
            code: PlayerErrorCode.backendOpenFailed,
            message: '$id open failed: $error',
            cause: error,
            stackTrace: stackTrace,
          ),
        );
      }

      rethrow;
    }
  }

  @override
  Future<void> play() async {
    requireReady();
    await onPlay();
  }

  @override
  Future<void> pause() async {
    requireReady();
    await onPause();
  }

  @override
  Future<void> stop() async {
    requireReady();

    _acceptSourceEvents = false;

    await onStop();

    _position = Duration.zero;
    _duration = null;

    _state = _state.stoppedState().withSource(value: false);

    _addEvent(const PlayerAdapterEvent.stopped());
  }

  @override
  Future<void> seek(Duration position) async {
    requireReady();

    await onSeek(position);

    // Do not emit positionChanged here.
    //
    // Completing the seek command only means that the backend accepted
    // the command. It does not guarantee that playback has actually
    // reached the requested position yet. The concrete backend should
    // report the real position through emitPositionChanged().
  }

  @override
  Future<void> setVolume(double volume) async {
    requireReady();
    await onSetVolume(volume);
  }

  @override
  Future<void> setRate(double rate) async {
    requireReady();

    await onSetRate(rate);

    // The rateChanged event should normally be emitted by the engine
    // callback after the backend has actually applied the new rate.
  }

  /// Restricts playback to the audio track.
  ///
  /// Gated by [PlayerAdapterCapabilities.supportsAudioOnly]: an adapter
  /// that cannot disable its video track is asserted in debug builds and
  /// left untouched in release builds, so a missing capability never
  /// turns into a silent "video still decoding" state.
  ///
  /// The setting is remembered in [audioOnly] for the whole adapter
  /// lifetime, so [onAfterOpen] can re-apply it after a recovery replay.
  @override
  Future<void> setAudioOnly({required bool audioOnly}) async {
    requireReady();

    assert(
      _capabilities.supportsAudioOnly,
      '$runtimeType received setAudioOnly but '
      'capabilities.supportsAudioOnly is false.',
    );

    if (!_capabilities.supportsAudioOnly) return;
    if (_audioOnly == audioOnly) return;

    _audioOnly = audioOnly;

    await onSetAudioOnly(audioOnly: audioOnly);
  }

  /// Engine options received before [onInitialize] built the engine.
  ///
  /// Held here so [applyEngineOptions] is safe to call at any point of the
  /// adapter's life; consumed through [consumeStashedEngineOptions] where
  /// the engine is created.
  List<EngineOption> _stashedEngineOptions = const <EngineOption>[];

  /// Applies raw engine options to the engine this adapter owns.
  ///
  /// Gated by [PlayerAdapterCapabilities.supportsEngineOptions] the same
  /// way [setAudioOnly] is gated by its own capability. Before the engine
  /// exists the options are stashed and answered
  /// [EngineOptionOutcome.stagedForNextOpen]; the engine creation path
  /// picks them up through [consumeStashedEngineOptions].
  @override
  Future<List<EngineOptionOutcome>> applyEngineOptions(List<EngineOption> options) async {
    assert(
      _capabilities.supportsEngineOptions,
      '$runtimeType received applyEngineOptions but '
      'capabilities.supportsEngineOptions is false.',
    );

    if (!_capabilities.supportsEngineOptions) {
      return List<EngineOptionOutcome>.filled(options.length, EngineOptionOutcome.unsupported);
    }

    if (!initialized) {
      _stashedEngineOptions = <EngineOption>[..._stashedEngineOptions, ...options];

      return List<EngineOptionOutcome>.filled(options.length, EngineOptionOutcome.stagedForNextOpen);
    }

    // Awaited instead of returned directly: staying `async` is what turns a
    // synchronously throwing engine hook into an error on the returned
    // Future, which is what every caller of an adapter awaits.
    final outcomes = await onApplyEngineOptions(options);

    return outcomes;
  }

  /// Engine-specific application of raw options.
  ///
  /// The engine exists when this runs; implementations translate the
  /// options into the engine's own calls and report what happened per
  /// option. The default answers [EngineOptionOutcome.unsupported] for
  /// everything, which is the honest answer for a backend without a
  /// runtime key/value surface.
  @protected
  Future<List<EngineOptionOutcome>> onApplyEngineOptions(List<EngineOption> options) async {
    return List<EngineOptionOutcome>.filled(options.length, EngineOptionOutcome.unsupported);
  }

  /// Takes the options stashed before the engine existed, if any.
  ///
  /// Call exactly where the engine is created, so the options take effect
  /// from the engine's first moment.
  @protected
  List<EngineOption> consumeStashedEngineOptions() {
    final stashed = _stashedEngineOptions;

    _stashedEngineOptions = const <EngineOption>[];

    return stashed;
  }

  /// Captures the current video frame with the backend's own API.
  ///
  /// Gated by [PlayerAdapterCapabilities.supportsScreenshot] the same way
  /// [setAudioOnly] is gated by its own capability: an adapter that cannot
  /// capture reports `false` and this method answers null without touching the
  /// engine, so an unsupported backend never throws on a user action.
  ///
  /// A null answer means "this route produced nothing" — not that the frame was
  /// black. The caller falls back to capturing the rendered surface.
  @override
  Future<Uint8List?> captureFrame(ScreenshotRequest request) async {
    if (!_initialized || _disposed || !_capabilities.supportsScreenshot) {
      return null;
    }

    // Awaited instead of returned directly, so a synchronously throwing
    // capture hook still reaches the caller as an error on the Future rather
    // than as a throw out of `captureFrame` itself.
    final bytes = await onCaptureFrame(request);

    return bytes;
  }

  @override
  Future<void> close() async {
    if (!_initialized || _disposed) return;

    _acceptSourceEvents = false;

    await onClose();

    _position = Duration.zero;
    _duration = null;

    _state = _state.stoppedState().withSource(value: false);

    _addEvent(const PlayerAdapterEvent.stopped());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;

    _state = _state.disposingState();

    await onDispose();

    _state = _state.disposedState();

    if (!_eventController.isClosed) {
      await _eventController.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Engine contract
  // ---------------------------------------------------------------------------

  /// Creates the engine and binds its listeners.
  @protected
  Future<void> onInitialize(PlayerAdapterContext context);

  /// Prepares engine options for the source about to open.
  ///
  /// Runs before the open window begins, so engine events fired here
  /// are still gated out.
  @protected
  Future<void> onBeforeOpen(PlayerSource source) async {}

  /// Hands the source to the engine.
  ///
  /// Runs inside the open window: engine reports arriving while this
  /// hook is pending defer their failures to the open outcome.
  @protected
  Future<void> onOpen(PlayerSource source);

  /// Adjusts playback after the source opened.
  @protected
  Future<void> onAfterOpen(PlayerSource source) async {}

  /// Starts playback on the engine.
  ///
  /// Called by [play] after the lifecycle guard. The transition itself is
  /// reported by the engine callback through [emitPlaying], never here, so a
  /// command the engine has not acted on yet must not fake the state.
  @protected
  Future<void> onPlay();

  /// Pauses playback on the engine.
  ///
  /// Called by [pause]; [emitPaused] is what publishes the transition, so an
  /// engine that pauses asynchronously reports it when it happens.
  @protected
  Future<void> onPause();

  /// Stops playback on the engine.
  ///
  /// Called by [stop] while the source event gate is already closed and
  /// before the position, duration and state are reset. Stopping is not
  /// releasing: [onClose] owns detaching the source.
  @protected
  Future<void> onStop();

  /// Moves the engine to [position].
  ///
  /// Called by [seek]. Returning only means the engine accepted the command —
  /// where playback actually landed is the engine's answer, published through
  /// [emitPositionChanged].
  @protected
  Future<void> onSeek(Duration position);

  /// Applies [volume] (0.0–1.0) to the engine.
  ///
  /// Called by [setVolume]; the value the engine ended up with comes back as
  /// [emitVolumeChanged].
  @protected
  Future<void> onSetVolume(double volume);

  /// Applies [rate] to the engine.
  ///
  /// Called by [setRate]; the applied rate is reported by the engine callback
  /// as a `rateChanged` event rather than asserted here.
  @protected
  Future<void> onSetRate(double rate);

  /// Applies [setAudioOnly] to the engine.
  ///
  /// Only called when the capability is declared and the value changed.
  @protected
  Future<void> onSetAudioOnly({required bool audioOnly}) async {}

  /// Captures a frame with the engine.
  ///
  /// Only called when [PlayerAdapterCapabilities.supportsScreenshot] is
  /// declared, the adapter is initialized and a source is open.
  ///
  /// Returning null is the honest answer for "the engine produced nothing
  /// here" — a platform where the capture API is unimplemented, an engine that
  /// cannot encode the requested format, or no decoded frame yet. Implement it
  /// in adapters that declare the capability.
  @protected
  Future<Uint8List?> onCaptureFrame(ScreenshotRequest request) async => null;

  /// Detaches the current source from the engine.
  ///
  /// Called by [close] (and only when the adapter is initialized and alive)
  /// with the source event gate already closed, before the position and
  /// duration are reset. The engine stays initialized, so a later [open] runs
  /// the full template again.
  @protected
  Future<void> onClose();

  /// Releases the engine and everything bound to it.
  ///
  /// Called by [dispose]; the event stream is closed as soon as it returns, so
  /// listeners bound in [onInitialize] and any native player they own have to
  /// be released here — nothing else runs afterwards.
  @protected
  Future<void> onDispose();

  /// Throws when [source] carries a composite this backend cannot
  /// consume.
  ///
  /// Progressive and non-bridged sources always pass. The check only
  /// fires for a [PlayerSource] that crossed [MediaSourceBridge] and
  /// whose [CompositeSupport] is [CompositeSupport.none]: playing its
  /// primary URL would silently drop the other essences, which is
  /// exactly the failure mode the planner layer was built to make
  /// loud instead of quiet.
  void _rejectUnsupportedComposite(PlayerSource source) {
    if (capabilities.supportsComposite) {
      return;
    }
    final mediaSource = MediaSourceBridge.fromPlayerSource(source);
    if (mediaSource is CompositeMediaSource) {
      throw UnsupportedError(
        'Adapter "$id" declares compositeSupport: none but was opened with a '
        'CompositeMediaSource (${mediaSource.videoTracks.length} video, '
        '${mediaSource.audioTracks.length} audio). Register a backend whose '
        'composite support is native or external-audio, or hand this adapter '
        'a single multiplexed URL.',
      );
    }
  }

  /// Throws when commands cannot be accepted.
  @protected
  void requireReady() {
    if (!_initialized || _disposed) {
      throw StateError('$runtimeType is not initialized or has been disposed.');
    }
  }

  // ---------------------------------------------------------------------------
  // Engine reports
  //
  // Fact emits (`playing`, `paused`, `completed`, `positionChanged`,
  // `durationChanged`, `volumeChanged`) publish an engine state
  // transition that has already happened. They are not gated by any
  // capability.
  //
  // Signal emits (`videoFrameProgress`, `videoSizeChanged`, and the
  // buffering progress ratio) publish a signal the adapter promised
  // to produce. They are gated by the corresponding
  // [PlayerAdapterCapabilities] field.
  // ---------------------------------------------------------------------------

  /// Reports that playback started.
  @protected
  void emitPlaying() {
    if (!acceptsEngineEvents) return;

    _state = _state.playingState();

    _addEvent(const PlayerAdapterEvent.playing());
  }

  /// Reports that playback paused.
  @protected
  void emitPaused() {
    if (!acceptsEngineEvents) return;

    _state = _state.pausedState();

    _addEvent(const PlayerAdapterEvent.paused());
  }

  /// Reports that playback completed.
  @protected
  void emitCompleted() {
    if (!acceptsEngineEvents) return;

    _state = _state.completedState();

    _addEvent(const PlayerAdapterEvent.completed());
  }

  /// Reports a buffering transition.
  ///
  /// While buffering starts the adapter enters the buffering state.
  /// When it ends, [resumePlaying] decides whether playback is
  /// reported as playing or paused; engines whose own state machine
  /// re-asserts the playback state separately leave it null.
  ///
  /// The transition itself is a fact and is always reported. The
  /// optional [progress] ratio is a signal: it is only forwarded when
  /// [PlayerAdapterCapabilities.supportsBufferingProgress] is true,
  /// because a backend that cannot measure the cache must not appear
  /// to report a ratio.
  @protected
  void emitBuffering({required bool buffering, bool? resumePlaying, double? progress}) {
    if (!acceptsEngineEvents) return;

    var forwardedProgress = progress;

    if (forwardedProgress != null) {
      assert(
        _capabilities.supportsBufferingProgress,
        '$runtimeType emitted buffering progress but '
        'capabilities.supportsBufferingProgress is false.',
      );

      if (!_capabilities.supportsBufferingProgress) {
        forwardedProgress = null;
      }
    }

    if (buffering) {
      _state = _state.bufferingState();
    } else if (resumePlaying != null) {
      _state = resumePlaying ? _state.playingState() : _state.pausedState();
    }

    _addEvent(PlayerAdapterEvent.buffering(buffering: buffering, progress: forwardedProgress));
  }

  /// Reports the stretches of media the engine can play without waiting.
  ///
  /// A signal the UI layer paints directly, so it is gated by
  /// [PlayerAdapterCapabilities.supportsBufferedRanges]: an engine
  /// that declared no range reporting must not put canonical ranges
  /// on the transport state, because an absent ahead-fill bar and a
  /// bar that says "nothing buffered" are different facts and only
  /// the capability knows which one is true. A violation is asserted
  /// in debug and dropped in release, matching the other gated
  /// emitters.
  ///
  /// Ranges arrive as the engine reported them; the transport state
  /// canonicalizes once on reduce.
  @protected
  void emitBufferedRanges(List<BufferRange> ranges) {
    if (!acceptsEngineEvents) return;

    assert(
      _capabilities.supportsBufferedRanges,
      '$runtimeType emitted buffered ranges but '
      'capabilities.supportsBufferedRanges is false.',
    );

    if (!_capabilities.supportsBufferedRanges) {
      return;
    }

    _addEvent(PlayerAdapterEvent.bufferedRangesChanged(ranges: ranges));
  }

  /// Reports decoded video dimensions.
  ///
  /// Geometry is a signal the adapter promised to produce, so publishing
  /// it is gated by
  /// [PlayerAdapterCapabilities.supportsVideoSizeChanged]. A call
  /// here without that capability is a producer contract violation:
  /// it is asserted in debug builds and dropped in release builds.
  ///
  /// The capability only gates the *signal*. The state transition it
  /// carries — the source has video — is applied either way, because a
  /// backend that cannot report geometry may still be decoding video,
  /// and `videoEnabled` must not depend on whether the dimensions are
  /// observable.
  ///
  /// Video geometry must never be used as a substitute for
  /// [emitVideoFrameProgress]; a size change does not prove that
  /// decoding is still progressing.
  @protected
  void emitVideoSizeChanged(int width, int height) {
    if (!acceptsEngineEvents) return;
    if (width <= 0 || height <= 0) return;

    // The source has video. That is a fact about the engine, applied
    // whether or not the adapter promised to report the geometry, so the
    // state never depends on the signal declaration.
    _state = _state.withVideoEnabled(value: true);

    assert(
      _capabilities.supportsVideoSizeChanged,
      '$runtimeType emitted videoSizeChanged but '
      'capabilities.supportsVideoSizeChanged is false.',
    );

    if (!_capabilities.supportsVideoSizeChanged) return;

    _addEvent(PlayerAdapterEvent.videoSizeChanged(width: width, height: height));
  }

  /// Reports decoded video dimensions, dropping repeats.
  ///
  /// The comparison resets on every [open], so the first geometry of
  /// each source is always published. Capability gating is delegated
  /// to [emitVideoSizeChanged].
  @protected
  void emitVideoSizeChangedIfChanged(int width, int height) {
    if (!acceptsEngineEvents) return;
    if (width <= 0 || height <= 0) return;

    if (width == _lastReportedWidth && height == _lastReportedHeight) {
      return;
    }

    _lastReportedWidth = width;
    _lastReportedHeight = height;

    emitVideoSizeChanged(width, height);
  }

  /// Reports that a decoded video frame has progressed.
  ///
  /// This is a heartbeat for the video-frame watchdog. It is
  /// intentionally separate from [emitVideoSizeChanged], because
  /// video dimensions describe geometry and do not prove that frames
  /// are still being decoded.
  ///
  /// The capability is read directly from [_capabilities];
  /// this base does not re-expose it as a getter, field, or constructor
  /// parameter. A call here without
  /// [PlayerAdapterCapabilities.supportsVideoFrameProgress] is a
  /// producer contract violation, so it is asserted in debug builds
  /// and silently dropped in release builds.
  @protected
  void emitVideoFrameProgress() {
    assert(
      _capabilities.supportsVideoFrameProgress,
      '$runtimeType emitted videoFrameProgress but '
      'capabilities.supportsVideoFrameProgress is false.',
    );

    if (!_capabilities.supportsVideoFrameProgress) return;
    if (!acceptsEngineEvents) return;

    _addEvent(const PlayerAdapterEvent.videoFrameProgress());
  }

  /// Reports the playback position.
  ///
  /// The value is stored as the adapter's current playback position
  /// and published as an adapter event.
  @protected
  void emitPositionChanged(Duration position) {
    if (!acceptsEngineEvents) return;

    _position = position;

    _addEvent(PlayerAdapterEvent.positionChanged(position: position));
  }

  /// Reports the media duration.
  ///
  /// The value is stored as the adapter's current media duration
  /// and published as an adapter event.
  @protected
  void emitDurationChanged(Duration duration) {
    if (!acceptsEngineEvents) return;

    _duration = duration;

    _addEvent(PlayerAdapterEvent.durationChanged(duration: duration));
  }

  /// Reports the output volume.
  @protected
  void emitVolumeChanged(double volume) {
    if (!acceptsEngineEvents) return;

    _addEvent(PlayerAdapterEvent.volumeChanged(volume: volume));
  }

  /// Reports an engine failure through the unified error model.
  ///
  /// Reports arriving while the source gate is closed are dropped;
  /// failures during the open window are deferred and surface
  /// through [open]'s deferred-error check.
  @protected
  void reportEngineError({
    required String message,
    PlayerErrorCode code = PlayerErrorCode.playbackFailed,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    if (_disposed) return;

    if (gatesSourceEvents && !_acceptSourceEvents) return;

    final error = PlayerError(code: code, message: message, cause: cause, stackTrace: stackTrace);

    if (_sourceOpening && gatesSourceEvents) {
      _deferredEngineError = error;
      return;
    }

    _fail(error);
  }

  /// Marks the adapter failed and publishes [error].
  @protected
  void fail(PlayerError error) => _fail(error);

  /// Replaces the metrics snapshot.
  @protected
  void updateMetrics(PlayerAdapterMetrics Function(PlayerAdapterMetrics metrics) transform) {
    _metrics = transform(_metrics);
  }

  /// Publishes an adapter event directly.
  ///
  /// Engine-originated payloads should go through the `emit*`
  /// helpers, which own the state transitions, the source gate, and
  /// capability gating. This escape hatch is for adapter-specific
  /// events that have no corresponding helper.
  @protected
  void emitEvent(PlayerAdapterEvent event) => _addEvent(event);

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _addEvent(PlayerAdapterEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void _fail(PlayerError error) {
    _state = _state.errorState();

    _addEvent(PlayerAdapterEvent.error(message: error.message, error: error, stackTrace: error.stackTrace));
  }
}
