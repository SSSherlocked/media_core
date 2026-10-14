import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:media_core_media_kit/media_core_media_kit.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform, ValueListenable;


/// [PlayerAdapter] implementation backed by the local media_kit
/// snapshot — the MPV engine.
///
/// This adapter also owns its video surface: it implements
/// [PlayerVideo] directly, so there is exactly one place that knows
/// how the texture is produced.
///
/// **Platform-specific settings:**
/// The adapter configures nothing on its own: [playerConfiguration] and
/// [videoControllerConfiguration] are media_kit's own types passed
/// verbatim, and every runtime tuning value arrives as an engine option
/// (an mpv property) from the caller.

// Engine creation (the caller's native configurations, verbatim) and the
// native property writer live in the `part` file next to this one:
// `media_kit_player_adapter_engine.dart`. Overrides, stream wiring, the
// public surface and the capability table stay in the class body — the
// stream handlers call the protected `PlayerAdapterBase` emit API, which
// only the class itself may touch.
part 'media_kit_player_adapter_engine.dart';
final class MediaKitPlayerAdapter extends PlayerAdapterBase implements PlayerVideo {
  /// Creates the adapter.
  ///
  /// [playerConfiguration] and [videoControllerConfiguration] are
  /// media_kit's own configuration types, applied verbatim at engine
  /// creation; null uses the engine's defaults.
  ///
  /// [capabilities] is normalised before being handed to the base: see
  /// [_honestCapabilities]. A caller may pass a declaration that claims
  /// video-frame progress on a platform where the observer is never
  /// started, and the base must not report a capability the adapter
  /// cannot honour.
  MediaKitPlayerAdapter({
    super.id = kMediaKitPlayerBackendId,
    PlayerAdapterCapabilities capabilities = defaultCapabilities,
    mk.Player? player,
    this.playerConfiguration,
    this.videoControllerConfiguration,
    this.customInputOpener,
    this.beforeOpen,
  }) : _injectedPlayer = player,
       super(capabilities: _honestCapabilities(capabilities));

  /// Native media_kit player configuration, applied verbatim at engine
  /// creation.
  ///
  /// Null uses media_kit's own defaults. Runtime changes travel as
  /// engine options (mpv properties), not through this field.
  final mk.PlayerConfiguration? playerConfiguration;

  /// Native media_kit_video controller configuration, applied verbatim
  /// at engine creation.
  final mkv.VideoControllerConfiguration? videoControllerConfiguration;

  /// Opener for app-owned inputs, injected by the host.
  ///
  /// A source carrying the [kMediaKitCustomInputKey] recipe in its
  /// metadata is opened through this callback instead of
  /// `player.open(Media)` — the host owns the input (a loopback lease,
  /// a relay socket) and hands it to the engine itself. Contract glue,
  /// not configuration: the adapter stores nothing and decides nothing
  /// about the input's contents.
  final Future<void> Function(mk.Player player, Object recipe)? customInputOpener;

  /// Per-source engine properties, injected by the host.
  ///
  /// Runs from [onBeforeOpen]: after the engine exists and before it is handed
  /// the URL, so a property the host derives from the source itself (a demuxer
  /// it already knows from the platform's manifest, a proxy that must not apply
  /// to a loopback input) lands on the open that needs it. Assembly-time engine
  /// options cannot express this — they are one value for the adapter's whole
  /// lifetime, while the answer here changes with each source.
  ///
  /// Contract glue like [customInputOpener]: the adapter stores nothing and
  /// decides nothing about which properties the host wants applied.
  final Future<void> Function(mk.Player player, PlayerSource source)? beforeOpen;

  /// Narrows [capabilities] to what this platform actually implements.
  ///
  /// The decoded-frame heartbeat is Windows-only (see
  /// [_frameProgressSupported]), so on every other platform
  /// `supportsVideoFrameProgress` must be reported as `false`.
  ///
  /// This matters beyond bookkeeping: the live watchdog bundle arms a
  /// frame-stall timer from this flag alone. Reporting `true` where no
  /// heartbeat can ever arrive makes the watchdog declare a stall on a
  /// perfectly healthy stream, and recovery then tears the stream down
  /// and reopens it on every timeout, forever.
  ///
  /// `supportsScreenshot` is narrowed the same way: mpv's `screenshot`
  /// needs the native backend, so the web build must not claim it. Engine
  /// options are property writes through the same surface and are
  /// narrowed with it.
  static PlayerAdapterCapabilities _honestCapabilities(PlayerAdapterCapabilities capabilities) {
    var result = capabilities;

    if (!_frameProgressSupported && result.supportsVideoFrameProgress) {
      result = result.copyWith(supportsVideoFrameProgress: false);
    }

    if (kIsWeb && result.supportsScreenshot) {
      result = result.copyWith(supportsScreenshot: false);
    }

    // Engine options are mpv property writes through NativePlayer, so the
    // web build has no surface to write to; every option would come back
    // `unsupported` and the caller would rebuild players for nothing.
    if (kIsWeb && result.supportsEngineOptions) {
      result = result.copyWith(supportsEngineOptions: false);
    }

    // The composite side channel is mpv's `audio-files` / `sub-files` list,
    // reached through NativePlayer commands. On web media_kit drives an HTML
    // video element with no such platform surface, so keeping the declared
    // externalAudio support would let the planner route a DASH pair here and
    // then drop the audio at the first null platform — a silent failure with
    // a permission slip. Web takes the honest `none`, so a composite source
    // there is refused with a reason instead of playing video-only.
    if (kIsWeb && result.compositeSupport != CompositeSupport.none) {
      result = result.copyWith(compositeSupport: CompositeSupport.none);
    }

    return result;
  }

  /// Whether this platform starts the decoded-frame observer.
  static bool get _frameProgressSupported => defaultTargetPlatform == TargetPlatform.windows;

  final mk.Player? _injectedPlayer;

  // ---------------------------------------------------------------------------
  // Surface
  // ---------------------------------------------------------------------------

  /// Resizes the native render target without recreating the player.
  ///
  /// Pass null to return to the intrinsic decoded size. Delegates to the
  /// video controller's native resize; the surface picks the change up in
  /// place.
  Future<void> setRenderTargetSize({int? width, int? height}) async {
    final controller = _videoController;
    if (controller == null) return;
    await controller.setSize(width: width, height: height);
  }

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  mk.Player? _player;
  mkv.VideoController? _videoController;

  final List<StreamSubscription<dynamic>> _subscriptions = [];


  /// What the device is, as far as the platform probe could say.
  ///
  /// Falls back to the process's own CPU count when nothing was probed, which
  /// is the one device fact a Dart process can read by itself.

  /// What the device can decode, and in hardware or not.
  ///
  /// Unknown when the host attached no provider; the adapter then leaves the
  /// engine's own behaviour alone instead of guessing.
  PlatformCodecCapabilities _codecs = PlatformCodecCapabilities.unknown;

  /// Codec of the video track mpv reported for the current source.
  ///
  /// The container says nothing about this: an MP4 carries H.264, HEVC or AV1,
  /// and which decoder to reach for depends on the codec.

  // ignore: unused_field
  bool _audioOutputSuppressed = false;


  /// Whether the current source is a live (non-seekable) stream.
  ///
  /// Rate changes are ignored for live sources: mpv would happily
  /// pitch-shift a broadcast that has no meaningful playback speed.
  bool _liveSource = false;

  bool _playingNow = false;
  bool _bufferingNow = false;
  bool _hasOpened = false;

  int? _width;
  int? _height;

  double _lastEmittedVolume = -1.0;

  BoxFit _videoFit = BoxFit.contain;

  /// Fit as a listenable, so a custom [build] implementation can react
  /// to [setVideoFit] without owning the notifier.
  ValueListenable<BoxFit> get fitListenable => _fitNotifier;

  /// mpv events are consumed through subscriptions bound once for the
  /// whole adapter lifetime, so the base's source gate stays open.
  @override
  bool get gatesSourceEvents => false;

  // ---------------------------------------------------------------------------
  // PlayerVideo
  // ---------------------------------------------------------------------------

  final ValueNotifier<BoxFit> _fitNotifier = ValueNotifier<BoxFit>(BoxFit.contain);

  /// The current viewport fit.
  BoxFit get videoFit => _videoFit;

  /// Applies the viewport fit through the surface.
  @override
  void setVideoFit(BoxFit fit) {
    if (_fitNotifier.value == fit) return;

    _videoFit = fit;
    _fitNotifier.value = fit;
  }

  /// Whether this adapter currently owns a video surface.
  @override
  bool get available => !isDisposed && !audioOnly && _videoController != null;

  /// Builds the video output widget.
  ///
  /// Deliberately bare: the surface's looks (fill, alignment, controls,
  /// subtitle view, fullscreen behaviour) belong to the host's widget,
  /// not to the adapter. Hosts that want the full native surface mount
  /// [MediaKitVideoView] with their own parameters, or build their own
  /// `mkv.Video` from [videoController].
  @override
  Widget build() {
    final controller = _videoController;

    if (controller == null) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<BoxFit>(
      valueListenable: _fitNotifier,
      builder: (context, fit, _) {
        return mkv.Video(
          controller: controller,
          fit: fit,
          controls: mkv.NoVideoControls,
          onEnterFullscreen: mkv.defaultEnterNativeFullscreen,
          onExitFullscreen: mkv.defaultExitNativeFullscreen,
        );
      },
    );
  }

  /// No-op: [mkv.Video] owns its own surface lifecycle.
  @override
  Future<void> attach() async {}

  /// Symmetric no-op for [attach].
  @override
  Future<void> detach() async {}

  // ---------------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------------

  /// The underlying media_kit player.
  ///
  /// Throws [StateError] before [onInitialize].
  mk.Player get player {
    final p = _player;

    if (p == null) {
      throw StateError('MediaKitPlayerAdapter has not been initialized.');
    }

    return p;
  }

  /// The video controller surface widgets bind to.
  mkv.VideoController? get videoController => _videoController;

  /// Whether decoded video frames have been observed for the current
  /// source.
  bool get hasDecodedVideoFrame => _hasDecodedVideoFrame;

  bool _hasDecodedVideoFrame = false;

  /// Minimum spacing between published decoded-frame heartbeats.
  static const int frameHeartbeatIntervalMs = 1000;

  final Stopwatch _frameHeartbeatClock = Stopwatch();

  int _lastFrameHeartbeatMs = -frameHeartbeatIntervalMs;

  /// Whether the current platform drives the compat-mode surface.

  /// Whether the current platform supports the video frame progress
  /// heartbeat implementation.
  ///
  /// The native `estimated-vf-fps` observation is intentionally limited
  /// to Windows. Other platforms do not start the observer and do not
  /// emit video frame progress events.
  bool get _supportsVideoFrameProgress => _frameProgressSupported;

  /// Ensures the media_kit native libraries are loaded.
  static void ensureInitialized() {
    mk.MediaKit.ensureInitialized();
  }

  // ---------------------------------------------------------------------------
  // Engine contract
  // ---------------------------------------------------------------------------

  @override
  Future<void> onInitialize(PlayerAdapterContext context) async {
    _player = _injectedPlayer ?? mk.Player(configuration: playerConfiguration ?? const mk.PlayerConfiguration());

    // The device budget must be known before the video controller and the
    // native property contract are built, because both branch on it. It now
    // arrives with the adapter context: the kernel stamps what the platform
    // probe answered into every session.
    _codecs = context.codecs;

    _videoController = _buildVideoController();

    _subscribeStreams();

    // Video frame progress is intentionally Windows-only.
    if (_supportsVideoFrameProgress) {
      _observeDecodedFrames();
    }

    // Options the caller pushed before this adapter was initialized ride
    // along to the engine's first moment.
    for (final option in consumeStashedEngineOptions()) {
      await _applyNativeOption(option);
    }
  }

  @override
  Future<List<EngineOptionOutcome>> onApplyEngineOptions(List<EngineOption> options) async {
    final outcomes = <EngineOptionOutcome>[];

    for (final option in options) {
      // mpv takes property writes on a running player through
      // `NativePlayer.setProperty`; the request is delivered to the live
      // instance and the engine applies what its runtime allows. An
      // option the engine refuses is reported as unsupported rather than
      // applied, so the caller can rebuild the player with it instead of
      // assuming the tuning landed. A list value is not a property write:
      // see [mpvListOptionCommands].
      final applied = await _applyNativeOption(option);

      outcomes.add(
        applied ? EngineOptionOutcome.appliedLive : EngineOptionOutcome.unsupported,
      );
    }

    return outcomes;
  }

  /// Normalizes a scalar option value into mpv's string dialect.
  ///
  /// A [List] does not come through here: mpv has no string form for a list
  /// property write, so those travel as commands instead — see
  /// [mpvListOptionCommands].
  String _mpvOptionValue(Object? value) {
    return switch (value) {
      null => '',
      bool flag => flag ? 'yes' : 'no',
      final String text => text,
      final other => '$other',
    };
  }

  @override
  Future<void> onBeforeOpen(PlayerSource source) async {
    _liveSource = source.isLive;
    _hasDecodedVideoFrame = false;
    _lastFrameHeartbeatMs = -frameHeartbeatIntervalMs;

    final hook = beforeOpen;
    if (hook != null) await hook(player, source);
  }

  @override
  Future<void> onOpen(PlayerSource source) async {
    final recipe = source.metadata[kMediaKitCustomInputKey];
    final opener = customInputOpener;

    if (recipe != null || source.protocol == SourceProtocol.custom) {
      if (opener == null || recipe == null) {
        throw UnsupportedError(
          'Source carries a $kMediaKitCustomInputKey recipe but no '
          'customInputOpener is registered on the adapter.',
        );
      }

      await opener(player, recipe);
    } else {
      await player.open(
        mk.Media(source.uri.toString(), httpHeaders: source.hasHeaders ? source.headers!.values : null),
        play: true,
      );
      // A composite (Bilibili DASH: video.m4s + audio.m4s) arrives here with
      // the primary video URI flattened by [MediaSourceBridge] and the full
      // track list parked in metadata. MPV has no native merge, so the extra
      // audio essences ride mpv's side channel: `--audio-file` (append through
      // the mpv `audio-files` list). The primary video is the open() target;
      // every remaining audio track is attached on top of it.
      await _attachCompositeAudio(source);
    }

    _hasOpened = true;

    if (audioOnly) {
      await _applyAudioOnly(true);
    }
  }

  /// Routes a [CompositeMediaSource]'s extra essences through MPV's
  /// external `audio-files` / `sub-files` side channels.
  ///
  /// No-op for progressive sources and for composites with at most one audio
  /// track already served by the primary. Attachment is best-effort — a
  /// rejected URL must not kill the primary video — but never silent: every
  /// failure is logged with the track and the mpv error, because "the video
  /// plays and nobody noticed the audio is gone" is the one outcome this
  /// whole composite model exists to make loud.
  Future<void> _attachCompositeAudio(PlayerSource source) async {
    final composite = MediaSourceBridge.compositeFromPlayerSource(source);
    if (composite == null) return;

    // DASH representations need not start at the same instant; MPV has no
    // per-external-file offset option, so the shared-clock alignment the
    // composition layer computed is applied as the one global knob that
    // means the same thing: `audio-delay` (seconds, audio lags when
    // positive). Zero for the ordinary same-period pair, so the property is
    // left alone unless something actually trails.
    final timeline = MediaTimeline.from(composite);
    final videoEntry = timeline.primary;

    final primaryUri = composite.primaryVideo?.uri ?? composite.primaryAudio?.uri;
    var firstAudio = true;
    for (final track in composite.audioTracks) {
      if (track.uri == primaryUri) continue; // already the open() target
      final url = track.uri.toString();
      if (url.isEmpty) continue;
      final native = _player?.platform;
      if (native == null) {
        _warnNoSideChannel();
        return;
      }

      if (firstAudio) {
        await _applyAudioAlignment(native, timeline, videoEntry);
        firstAudio = false;
      }

      // mpv fetches an external `audio-files` entry with its GLOBAL network
      // options, not the per-Media httpHeaders the primary open() carried, so
      // mirror the track's request headers onto the player first (Referer /
      // Cookie via http-header-fields; User-Agent via its own option).
      await _applyTrackNetworkHeaders(native, track.headers?.values ?? const <String, String>{});
      await _sideChannelAppend(native, 'audio-files', url, track);
    }

    // Subtitles ride the same side channel. mpv's `sub-files` takes file
    // URLs; a DASH `text` representation served as WebVTT is exactly such a
    // file, so declaring the essence and never attaching it was just a gap
    // in this loop, not a limit of the engine.
    for (final track in composite.subtitleTracks) {
      final url = track.uri.toString();
      if (url.isEmpty) continue;
      final native = _player?.platform;
      if (native == null) {
        _warnNoSideChannel();
        return;
      }
      await _applyTrackNetworkHeaders(native, track.headers?.values ?? const <String, String>{});
      await _sideChannelAppend(native, 'sub-files', url, track);
    }
  }

  /// The composite side channel needs mpv's native command surface; say so
  /// once instead of dropping the remaining essences in silence.
  void _warnNoSideChannel() {
    MediaCoreLog.warning(
      LogCategory.renderer,
      'composite side channel unavailable: no mpv NativePlayer on this '
      'platform; extra audio and subtitle essences were not attached',
    );
  }

  /// Appends one URL to an mpv list option, logging rather than throwing.
  Future<void> _sideChannelAppend(
    dynamic native,
    String list,
    String url,
    MediaTrack track,
  ) async {
    try {
      // ignore: avoid_dynamic_calls
      await (native as dynamic).command(<Object>['change-list', list, 'append', url]);
    } catch (error) {
      MediaCoreLog.warning(
        LogCategory.renderer,
        'composite $list attach failed for $url: $error',
        fields: <String, Object?>{
          'list': list,
          'kind': track.kind.name,
          if (track.language != null) 'language': track.language,
        },
      );
    }
  }

  /// Applies the composition layer's alignment as mpv's `audio-delay`.
  Future<void> _applyAudioAlignment(
    dynamic native,
    MediaTimeline timeline,
    TimelineTrack? video,
  ) async {
    if (video == null) {
      return;
    }
    final audio = timeline.tracks
        .where((entry) => entry.track.kind == MediaTrackType.audio)
        .firstOrNull;
    if (audio == null || audio.offset == video.offset) {
      return; // aligned; leave the user's own delay untouched
    }
    final seconds = (audio.offset - video.offset).inMicroseconds / 1000000;
    try {
      // ignore: avoid_dynamic_calls
      await (native as dynamic).setProperty('audio-delay', seconds);
    } catch (error) {
      MediaCoreLog.warning(
        LogCategory.renderer,
        'composite audio-delay ${seconds}s rejected by mpv: $error',
      );
    }
  }

  /// Sets the player-global HTTP headers MPV uses for side-channel inputs.
  /// `user-agent` is its own option; every other header goes into the
  /// `http-header-fields` list as a `Name: value` line (replaced wholesale so
  /// a re-attach never stacks duplicates).
  ///
  /// Validation is the framework's single rule — see [HttpHeaderSanitizer].
  /// A header that cannot be sent exactly as given is refused here rather
  /// than dropped: this path feeds the side-channel essences, so a silently
  /// missing Referer shows up as an audio track that 403s while the video
  /// keeps playing.
  Future<void> _applyTrackNetworkHeaders(dynamic native, Map<String, String> headers) async {
    if (headers.isEmpty) return;

    final sanitized = HttpHeaderSanitizer.sanitize(headers);
    final userAgent = sanitized.remove('user-agent');

    if (userAgent != null) {
      try {
        // ignore: avoid_dynamic_calls
        await (native as dynamic).setProperty('user-agent', userAgent);
      } catch (error) {
        // The side-channel fetch runs without a user agent, which is exactly
        // the request a CDN answers with 403; the audio track then fails for
        // a reason nothing else would report.
        MediaCoreLog.warning(
          LogCategory.network,
          'side-channel user-agent was not applied: $error',
          error: error,
        );
      }
    }

    if (sanitized.isEmpty) return;
    final fields = HttpHeaderSanitizer.mpvFields(sanitized);
    try {
      // ignore: avoid_dynamic_calls
      await (native as dynamic).setProperty('http-header-fields', fields);
    } catch (error) {
      // Older mpv builds take a comma-joined string; best-effort fallback.
      try {
        // ignore: avoid_dynamic_calls
        await (native as dynamic).setProperty('http-header-fields', fields.join(','));
      } catch (fallbackError) {
        MediaCoreLog.warning(
          LogCategory.network,
          'side-channel request headers were not applied in either form '
              '($error / $fallbackError); the extra essences will be '
              'fetched without Referer or Cookie',
          error: fallbackError,
        );
      }
    }
  }

  @override
  Future<void> onPlay() async {
    await player.play();
    emitPlaying();
  }

  @override
  Future<void> onPause() async {
    await player.pause();
    emitPaused();
  }

  @override
  Future<void> onStop() async {
    await player.stop();

    _playingNow = false;
    _bufferingNow = false;
    _hasOpened = false;

    _hasDecodedVideoFrame = false;
    _width = null;
    _height = null;

    _lastFrameHeartbeatMs = -frameHeartbeatIntervalMs;
  }

  @override
  Future<void> onSeek(Duration position) => player.seek(position);

  @override
  Future<void> onSetVolume(double volume) => player.setVolume(volume.clamp(0.0, 1.0) * 100.0);

  @override
  Future<void> onSetRate(double rate) {
    // Live streams have no meaningful playback speed; honouring the
    // command would pitch-shift a broadcast.
    if (_liveSource) {
      return Future<void>.value();
    }

    return player.setRate(rate);
  }

  @override
  Future<void> onClose() async {
    await player.stop();

    _hasOpened = false;
    _playingNow = false;
    _bufferingNow = false;

    // Reset all source-scoped presentation state so the next source
    // cannot inherit the previous source's frame / geometry state.
    _hasDecodedVideoFrame = false;
    _width = null;
    _height = null;

    _lastFrameHeartbeatMs = -frameHeartbeatIntervalMs;
  }

  @override
  Future<void> onDispose() async {
    await Future.wait(_subscriptions.map((subscription) => subscription.cancel()));

    _subscriptions.clear();

    // Stop the frame heartbeat clock before tearing down the player.
    if (_frameHeartbeatClock.isRunning) {
      _frameHeartbeatClock.stop();
    }

    _fitNotifier.dispose();

    // A player supplied through the constructor may be owned by the
    // caller. Only dispose players that were created by this adapter.
    if (_injectedPlayer == null) {
      await _player?.dispose();
    }

    _player = null;
    _videoController = null;
  }

  // ---------------------------------------------------------------------------
  // Extensions
  // ---------------------------------------------------------------------------

  /// Suppresses audio output for the next open.
  Future<void> setAudioOutputSuppressed(bool suppressed) async {
    _audioOutputSuppressed = suppressed;

    if (suppressed) {
      try {
        await player.setAudioTrack(mk.AudioTrack.no());
      } catch (_) {
        // Best-effort; some builds reject track selection before open.
      }
    }
  }

  @override
  Future<void> onAfterOpen(PlayerSource source) async {
    // The suppression flag belongs to the source lifecycle: a fresh open
    // (including a recovery replay of the same source) rebuilds the audio
    // pipeline, so it must be suppressed again or sound comes back.
    if (_audioOutputSuppressed) {
      try {
        await player.setAudioTrack(mk.AudioTrack.no());
      } catch (_) {
        // Best-effort.
      }
    }
  }

  @override
  Future<void> onSetAudioOnly(bool audioOnly) => _applyAudioOnly(audioOnly);

  Future<void> _applyAudioOnly(bool audioOnly) async {
    await player.setVideoTrack(audioOnly ? mk.VideoTrack.no() : mk.VideoTrack.auto());
  }

  /// Captures the current frame through mpv.
  ///
  /// mpv encodes the frame itself, so this returns the decoded picture at the
  /// stream's resolution — no widget needs to be on screen and no surface must
  /// be read. `image/jpeg` is what mpv encodes most cheaply, but PNG is
  /// available too, so both requested formats are honoured.
  ///
  /// Subtitles are included only when the adapter runs mpv's own subtitle
  /// renderer and the caller asked for them: burning them in is a deliberate
  /// choice, not a side effect of taking a screenshot.
  @override
  Future<Uint8List?> onCaptureFrame(ScreenshotRequest request) async {
    if (!_hasOpened) {
      return null;
    }

    final p = _player;

    if (p == null) {
      return null;
    }

    try {
      return await p.screenshot(
        format: request.mimeType,
        includeLibassSubtitles: request.includeSubtitles && _libassEnabled,
      );
    } catch (error) {
      // The web backend throws instead of declaring no capability; the caller
      // falls back to the rendered surface, which is the only route there.
      MediaCoreLog.warning(LogCategory.renderer, 'captureFrame failed: $error', error: error);

      return null;
    }
  }

  /// Whether mpv renders subtitles itself.
  ///
  /// Only then can `screenshot` burn them into the image. Read from the live
  /// player rather than from this package's config, because libass is a
  /// media_kit-level setting an injector can change.
  bool get _libassEnabled {
    final configuration = _player?.platform?.configuration;

    return configuration?.libass ?? false;
  }

  // Stream wiring
  // ---------------------------------------------------------------------------

  void _subscribeStreams() {
    final s = player.stream;

    _subscriptions.add(s.playing.listen(_onPlaying));

    _subscriptions.add(s.completed.listen(_onCompleted));

    _subscriptions.add(s.buffering.listen(_onBuffering));

    _subscriptions.add(s.position.listen(_onPosition));

    _subscriptions.add(s.duration.listen(_onDuration));

    _subscriptions.add(s.volume.listen(_onVolume));

    _subscriptions.add(s.width.listen(_onWidth));

    _subscriptions.add(s.height.listen(_onHeight));

    _subscriptions.add(s.error.listen(_onError));

    _subscriptions.add(s.buffer.listen(_onBuffer));

    // The track list is where the codec becomes known, and the codec is what
    // decides whether hardware decoding was ever possible.
    _subscriptions.add(s.tracks.listen(_onTracks));
  }

  /// Reports a video codec this device has no hardware decoder for.
  ///
  /// media_kit chooses the decoder through `videoControllerConfiguration`
  /// when the player is constructed, so there is no mid-playback
  /// switchover to perform here — claiming one would be a capability the
  /// surface cannot honor. What the track list can do is make the
  /// mismatch visible: without this, a device that cannot decode the
  /// stream in hardware just shows no frames and nothing says why.
  void _onTracks(mk.Tracks tracks) {
    for (final track in tracks.video) {
      final codec = VideoCodec.tryParse(track.codec);

      if (codec == null) {
        continue;
      }

      final hardware = _codecs.canDecodeInHardware(codec, width: _width ?? 0, height: _height ?? 0);

      if (hardware != false) {
        return;
      }

      MediaCoreLog.warning(
        LogCategory.renderer,
        'no hardware decoder for ${track.codec} on this device; frames '
            'depend on software decoding',
        fields: <String, Object?>{'codec': track.codec},
      );
      return;
    }
  }

  /// Starts the decoded-video heartbeat observer.
  ///
  /// This functionality is intentionally Windows-only.
  ///
  /// `estimated-vf-fps` is used as a video-output heartbeat. It is not
  /// treated as an exact decoded-frame counter.
  void _observeDecodedFrames() {
    if (!_supportsVideoFrameProgress) {
      return;
    }

    if (_frameHeartbeatClock.isRunning) {
      return;
    }

    _frameHeartbeatClock.start();

    const property = 'estimated-vf-fps';

    try {
      final native = player.platform;

      // `estimated-vf-fps` is used only as a video-output heartbeat.
      // It is not treated as an exact decoded-frame counter.
      //
      // Do not replace this with position / width / height changes:
      // those signals do not prove that video frames are progressing.
      // ignore: avoid_dynamic_calls
      (native as dynamic).observeProperty?.call(property, (dynamic value) async {
        _onNativeFrameSignal(property, value?.toString() ?? '');
      });
    } catch (error, stackTrace) {
      MediaCoreLog.warning(
        LogCategory.renderer,
        'observeProperty failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _onNativeFrameSignal(String property, String value) {
    // Frame progress is Windows-only.
    if (!_supportsVideoFrameProgress) {
      return;
    }

    if (isDisposed) return;
    if (!_hasOpened || !_playingNow) return;
    if (property != 'estimated-vf-fps') return;

    final fps = double.tryParse(value.trim());

    if (fps == null || fps <= 0) return;

    final now = _frameHeartbeatClock.elapsedMilliseconds;

    if (now - _lastFrameHeartbeatMs < frameHeartbeatIntervalMs) {
      return;
    }

    _lastFrameHeartbeatMs = now;

    _hasDecodedVideoFrame = true;

    emitVideoFrameProgress();
  }

  void _onPlaying(bool playing) {
    if (_playingNow == playing) return;

    _playingNow = playing;

    if (playing) {
      emitPlaying();
    } else if (_hasOpened && !state.stopped && !state.completed) {
      emitPaused();
    }
  }

  void _onCompleted(bool completed) {
    if (!completed) return;

    _playingNow = false;

    emitCompleted();
  }

  void _onBuffering(bool buffering) {
    if (_bufferingNow == buffering) return;

    _bufferingNow = buffering;

    emitBuffering(buffering, resumePlaying: buffering ? null : _playingNow);
  }

  void _onPosition(Duration position) {
    // media_kit replays zeroed position/duration on stop(); without this
    // guard the previous source's teardown leaks into the next generation.
    if (!_hasOpened) return;

    emitPositionChanged(position);
  }

  void _onDuration(Duration duration) {
    if (!_hasOpened) return;

    emitDurationChanged(duration);
  }

  void _onVolume(double v) {
    final normalised = (v / 100.0).clamp(0.0, 1.0);

    if (normalised == _lastEmittedVolume) {
      return;
    }

    _lastEmittedVolume = normalised;

    emitVolumeChanged(normalised);
  }

  void _onWidth(int? w) {
    if (!_hasOpened) return;

    _width = w;
    _maybeEmitSize();
  }

  void _onHeight(int? h) {
    if (!_hasOpened) return;

    _height = h;
    _maybeEmitSize();
  }

  void _maybeEmitSize() {
    final w = _width;
    final h = _height;

    if (w == null || h == null || w <= 0 || h <= 0) {
      return;
    }

    emitVideoSizeChangedIfChanged(w, h);
  }

  void _onError(String message) {
    if (isRefusedSeekMessage(message)) {
      // media_kit forwards every error-level `cplayer` log line as an error,
      // including mpv refusing a seek on a stream it does not consider
      // seekable. Nothing failed: playback carries on. media_kit's Android
      // output seeks to the current position whenever it attaches its
      // surface, so on a live stream this line came with every cold start
      // and the sweep condemned a healthy line for it.
      MediaCoreLog.info(LogCategory.error, 'ignored: $message');
      return;
    }

    MediaCoreLog.warning(LogCategory.error, message);

    reportEngineError(message: message);
  }

  /// mpv's two error lines for a refused seek
  /// (`Cannot seek in this stream.` and the `--force-seekable` hint).
  @visibleForTesting
  static bool isRefusedSeekMessage(String message) {
    final text = message.trim();
    return text.startsWith('Cannot seek') || text.contains('--force-seekable');
  }

  void _onBuffer(Duration buffered) {
    updateMetrics((m) => m.copyWith(buffered: buffered));
  }

  // ---------------------------------------------------------------------------
  // Capabilities
  // ---------------------------------------------------------------------------

  static const PlayerAdapterCapabilities defaultCapabilities = PlayerAdapterCapabilities(
    // Core playback.
    supportsLive: true,
    supportsSeek: true,
    supportsPause: true,
    supportsStop: true,
    supportsRateControl: true,
    supportsVolumeControl: true,
    supportsMuteControl: false,
    supportsAudioOnly: true,
    supportsEngineOptions: true,

    // Video and rendering.
    //
    // Frame progress is declared optimistically here and narrowed per
    // platform by the constructor: the heartbeat is Windows-only, so the
    // instance reports `true` on Windows and `false` everywhere else. Do
    // not read this constant as the running adapter's answer — read
    // `adapter.capabilities`.
    supportsVideoFrameProgress: true,
    supportsVideoSizeChanged: true,
    supportsVideoReconfig: false,
    supportsHwdecInfo: false,
    supportsVideoFilters: false,
    supportsScreenshot: true,

    // Audio.
    supportsAudioReconfig: false,
    supportsAudioDeviceSelection: false,
    supportsAudioFilters: false,

    // Tracks and subtitles.
    supportsTrackSelection: false,
    supportsSubtitleTrack: false,
    supportsExternalSubtitle: false,

    // Playback state and buffering.
    supportsCacheState: false,
    supportsBufferingProgress: false,
    supportsChapterControl: false,
    supportsLoop: false,

    // Metadata and playlist.
    supportsMetadata: false,
    supportsPlaylist: false,
    supportsPlaylistControl: false,

    // Diagnostics and integration.
    supportsClientMessage: false,
    supportsLogMessages: false,

    // Decoders.
    supportsHardwareDecoder: true,
    supportsSoftwareDecoder: true,

    // Presentation.
    supportsPictureInPicture: false,
    supportsFullscreen: true,

    // Source matching.
    supportedProtocols: MediaKitFormats.supportedProtocols,
    supportedFormats: MediaKitFormats.supportedFormats,
    // media_kit wraps libmpv on every target, and MPV combines a
    // primary URL with side-channel audio files (`--audio-file`,
    // `secondary-sid`), not a native merging API. Providers should
    // read the composite from MediaSourceBridge metadata and route
    // extra audio through mpv's side channel.
    compositeSupport: CompositeSupport.externalAudio,
  );
}
