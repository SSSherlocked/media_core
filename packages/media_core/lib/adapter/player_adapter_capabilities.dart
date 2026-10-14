import 'package:equatable/equatable.dart';
import 'package:media_core/adapter/composite_support.dart';
import 'package:media_core/media_core.dart'
    show CompositeMediaSource, PlayerAdapter, PlayerAdapterBufferedRangesChanged, PlayerAdapterEvent, UnsupportedPlan;

/// Describes capabilities of a player adapter.
///
/// [PlayerAdapterCapabilities] represents static features supported by a
/// playback backend. It is the **single source of truth** for adapter
/// capabilities: every other layer reads fields from an instance of this
/// class and must not re-declare a `supportsXxx` / `xxxSupported` field,
/// getter, or constructor parameter that mirrors a field here.
///
/// Examples:
///
/// - media_kit supports hardware decoding
/// - native player supports platform PiP
/// - a simple backend may not support seeking
///
/// Default values are deliberately conservative: every capability
/// defaults to `false` (or an empty set) except [supportsSoftwareDecoder],
/// which is assumed true because any backend that can decode at all can
/// decode in software. An adapter that supports more must opt in.
///
/// Responsibilities:
///
/// - describe backend features
/// - support adapter selection
///
/// It does not:
///
/// - store runtime state
/// - track playback metrics
/// - manage resources
///
/// Those belong to:
///
/// - PlayerAdapterState
/// - PlayerAdapterMetrics
final class PlayerAdapterCapabilities extends Equatable {
  /// Creates adapter capabilities.
  ///
  /// Defaults represent the minimal, "nothing declared yet" baseline.
  /// Adapters must explicitly opt in to any capability they provide.
  const PlayerAdapterCapabilities({
    // Core playback.
    this.supportsLive = false,
    this.supportsSeek = false,
    this.supportsPause = false,
    this.supportsStop = false,
    this.supportsRateControl = false,
    this.supportsVolumeControl = false,
    this.supportsMuteControl = false,
    this.supportsAudioOnly = false,
    this.supportsEngineOptions = false,

    // Video and rendering.
    this.supportsVideoFrameProgress = false,
    this.supportsVideoSizeChanged = false,
    this.supportsVideoReconfig = false,
    this.supportsHwdecInfo = false,
    this.supportsVideoFilters = false,
    this.supportsScreenshot = false,

    // Audio.
    this.supportsAudioReconfig = false,
    this.supportsAudioDeviceSelection = false,
    this.supportsAudioFilters = false,

    // Tracks and subtitles.
    this.supportsTrackSelection = false,
    this.supportsSubtitleTrack = false,
    this.supportsExternalSubtitle = false,

    // Playback state and buffering.
    this.supportsCacheState = false,
    this.supportsBufferingProgress = false,
    this.supportsBufferedRanges = false,
    this.supportsChapterControl = false,
    this.supportsLoop = false,

    // Metadata and playlist.
    this.supportsMetadata = false,
    this.supportsPlaylist = false,
    this.supportsPlaylistControl = false,

    // Diagnostics and integration.
    this.supportsClientMessage = false,
    this.supportsLogMessages = false,

    // Decoders.
    this.supportsHardwareDecoder = false,
    this.supportsSoftwareDecoder = true,

    // Presentation.
    this.supportsPictureInPicture = false,
    this.supportsFullscreen = false,

    // Source matching.
    this.supportedProtocols = const {},
    this.supportedFormats = const {},
    this.compositeSupport = CompositeSupport.none,
  });

  // ---------------------------------------------------------------------------
  // Core playback
  // ---------------------------------------------------------------------------

  /// Whether live playback is supported.
  final bool supportsLive;

  /// Whether seeking is supported.
  final bool supportsSeek;

  /// Whether pause is supported.
  final bool supportsPause;

  /// Whether an explicit stop command is supported.
  final bool supportsStop;

  /// Whether playback speed control is supported.
  final bool supportsRateControl;

  /// Whether volume control is supported.
  final bool supportsVolumeControl;

  /// Whether muting without changing the volume level is supported.
  final bool supportsMuteControl;

  /// Whether playback can be restricted to the audio track.
  ///
  /// Audio-only means the video track is disabled (not merely hidden):
  /// backends expose this through their own track switch, for example
  /// mpv's `vid` property or IJKPlayer's `disable-vid` option. An
  /// adapter that can only hide the video surface must declare `false`,
  /// because the decoder would keep running and the promise of the
  /// command would be a rendering trick rather than the real thing.
  ///
  /// Declaring `true` is what makes [PlayerAdapter.setAudioOnly] reach
  /// the backend; the base drops the command otherwise.
  final bool supportsAudioOnly;

  /// Whether raw engine options can be applied to a live engine.
  ///
  /// Declared by adapters whose engine has a runtime key/value surface
  /// (mpv properties, mdk properties, ijkplayer options). An adapter
  /// without the surface answers `unsupported` for every option instead
  /// of throwing.
  final bool supportsEngineOptions;

  // ---------------------------------------------------------------------------
  // Video and rendering
  // ---------------------------------------------------------------------------

  /// Whether the adapter can reliably emit
  /// [PlayerAdapterEvent.videoFrameProgress].
  ///
  /// This is a heartbeat for the video-frame watchdog and is distinct
  /// from geometry reports: video size does not prove that frames are
  /// still being decoded. The flag describes the adapter's signal, not
  /// any particular underlying callback name.
  ///
  /// - Backends with a reliable frame-progress signal (for example mpv,
  ///   which can derive a heartbeat from `estimated-vf-fps`) declare
  ///   this as `true`.
  /// - Backends that only report geometry, or whose frame notifications
  ///   are unreliable, must declare `false` so the watchdog is disabled
  ///   or downgraded instead of inferring stalls from a signal the
  ///   adapter was never going to emit.
  final bool supportsVideoFrameProgress;

  /// Whether decoded video dimensions are reported.
  final bool supportsVideoSizeChanged;

  /// Whether video output reconfiguration events are reported.
  ///
  /// Backends such as mpv surface this through
  /// `MPV_EVENT_VIDEO_RECONFIG`, which fires when the video output or
  /// filter chain changes (resolution, pixel format, rotation).
  final bool supportsVideoReconfig;

  /// Whether the current hardware decoder state can be observed.
  ///
  /// Backends such as mpv expose this through the `hwdec-current`
  /// property, reporting whether hardware decoding is actually active
  /// for the current source.
  final bool supportsHwdecInfo;

  /// Whether dynamic video filters can be added or removed at runtime.
  ///
  /// Backends such as mpv expose this through the `vf` property.
  final bool supportsVideoFilters;

  /// Whether frame capture is supported.
  ///
  /// Backends such as mpv expose this through the `screenshot`,
  /// `screenshot-to-file` and `screenshot-raw` commands.
  final bool supportsScreenshot;

  // ---------------------------------------------------------------------------
  // Audio
  // ---------------------------------------------------------------------------

  /// Whether audio output reconfiguration events are reported.
  ///
  /// Backends such as mpv surface this through
  /// `MPV_EVENT_AUDIO_RECONFIG`.
  final bool supportsAudioReconfig;

  /// Whether audio output devices can be enumerated and selected.
  ///
  /// Backends such as mpv expose this through the `audio-device` and
  /// `audio-device-list` properties.
  final bool supportsAudioDeviceSelection;

  /// Whether dynamic audio filters can be added or removed at runtime.
  ///
  /// Backends such as mpv expose this through the `af` property.
  final bool supportsAudioFilters;

  // ---------------------------------------------------------------------------
  // Tracks and subtitles
  // ---------------------------------------------------------------------------

  /// Whether audio/video/subtitle tracks can be selected at runtime.
  ///
  /// Backends such as mpv expose this through the `vid`, `aid` and
  /// `sid` properties.
  final bool supportsTrackSelection;

  /// Whether the currently displayed subtitle text is observable.
  ///
  /// Backends such as mpv expose this through the `sub-text` property.
  final bool supportsSubtitleTrack;

  /// Whether external subtitle files can be loaded at runtime.
  final bool supportsExternalSubtitle;

  // ---------------------------------------------------------------------------
  // Playback state and buffering
  // ---------------------------------------------------------------------------

  /// Whether cache and buffering state is observable.
  ///
  /// Backends such as mpv expose this through `cache-buffering-state`,
  /// `demuxer-cache-duration` and `paused-for-cache`.
  final bool supportsCacheState;

  /// Whether a buffering progress ratio can be reported.
  ///
  /// Backends such as mpv expose this through `cache-buffering-state`
  /// (0..100).
  final bool supportsBufferingProgress;

  /// Whether the backend reports which stretches of media are
  /// already downloaded.
  ///
  /// A scalar progress figure cannot drive a scrubber: the UI needs
  /// to paint ahead-fill and to know whether the position a drag is
  /// hovering over is already buffered. Engines that can report
  /// ranges (media_kit's buffered positions, platform players'
  /// `buffered` TimeRanges) declare this `true`; the base drops
  /// [PlayerAdapterBufferedRangesChanged] otherwise, so a UI that
  /// reads the flag always knows why a bar is absent rather than
  /// guessing whether the engine is broken or just unreported.
  final bool supportsBufferedRanges;

  /// Whether chapter navigation is supported.
  ///
  /// Backends such as mpv expose this through the `chapter` property
  /// and the `chapter` command.
  final bool supportsChapterControl;

  /// Whether loop control is supported.
  ///
  /// Backends such as mpv expose this through the `loop-file` and
  /// `loop-playlist` properties.
  final bool supportsLoop;

  // ---------------------------------------------------------------------------
  // Metadata and playlist
  // ---------------------------------------------------------------------------

  /// Whether media metadata is observable.
  ///
  /// Backends such as mpv expose this through the `metadata` property.
  final bool supportsMetadata;

  /// Whether a playlist is managed by the backend.
  ///
  /// Backends such as mpv expose this through the `playlist`,
  /// `playlist-pos` and `playlist-count` properties, together with
  /// `MPV_EVENT_START_FILE` and `MPV_EVENT_END_FILE`.
  final bool supportsPlaylist;

  /// Whether the playlist can be modified at runtime.
  ///
  /// Backends such as mpv expose this through commands like
  /// `playlist-next`, `playlist-prev`, `playlist-move` and
  /// `playlist-remove`.
  final bool supportsPlaylistControl;

  // ---------------------------------------------------------------------------
  // Diagnostics and integration
  // ---------------------------------------------------------------------------

  /// Whether the backend can emit client messages to the host.
  ///
  /// Backends such as mpv surface this through
  /// `MPV_EVENT_CLIENT_MESSAGE`, which is used for script and host
  /// communication.
  final bool supportsClientMessage;

  /// Whether backend log messages can be observed.
  ///
  /// Backends such as mpv surface this through
  /// `MPV_EVENT_LOG_MESSAGE`, useful for debugging and advanced
  /// monitoring.
  final bool supportsLogMessages;

  // ---------------------------------------------------------------------------
  // Decoders
  // ---------------------------------------------------------------------------

  /// Whether hardware decoding is supported.
  final bool supportsHardwareDecoder;

  /// Whether software decoding is supported.
  ///
  /// Defaults to `true`: any backend that can decode at all can decode
  /// in software. A backend with no decoder whatsoever should declare
  /// this as `false` explicitly.
  final bool supportsSoftwareDecoder;

  // ---------------------------------------------------------------------------
  // Presentation
  // ---------------------------------------------------------------------------

  /// Whether Picture-in-Picture is supported.
  final bool supportsPictureInPicture;

  /// Whether fullscreen presentation is supported.
  final bool supportsFullscreen;

  // ---------------------------------------------------------------------------
  // Source matching
  // ---------------------------------------------------------------------------

  /// Supported protocols.
  ///
  /// Example:
  ///
  /// - http
  /// - https
  /// - rtmp
  final Set<String> supportedProtocols;

  /// Supported formats.
  ///
  /// Example:
  ///
  /// - hls
  /// - flv
  /// - mp4
  final Set<String> supportedFormats;

  /// How this backend consumes a [CompositeMediaSource].
  ///
  /// The distinction matters because "supports composite" is not one
  /// capability but two, and they need different handling above the
  /// adapter:
  ///
  /// - [CompositeSupport.native] — Media3 / ExoPlayer's
  ///   `MergingMediaSource`, so the planner forwards the whole
  ///   composite and the engine merges internally.
  /// - [CompositeSupport.externalAudio] — MPV's `audio-files` /
  ///   secondary-track channel, so the planner picks a primary video
  ///   essence for the main URL and routes the extra audio through the
  ///   side channel.
  /// - [CompositeSupport.none] — FijkPlayer and any other single-URL
  ///   engine; the planner answers [UnsupportedPlan] for a composite,
  ///   because nothing in the stack folds two essences into one stream.
  ///
  /// Defaults to [CompositeSupport.none] to match this class's
  /// conservative baseline; adapters that can do better opt in.
  final CompositeSupport compositeSupport;

  /// Whether this backend can consume composite sources at all.
  ///
  /// Derived from [compositeSupport] so callers never see a
  /// `supportsComposite` boolean drift out of sync with the enum it
  /// summarises.
  bool get supportsComposite => compositeSupport != CompositeSupport.none;

  /// Whether adapter can handle protocol.
  bool supportsProtocol(String protocol) {
    return supportedProtocols.contains(protocol.toLowerCase());
  }

  /// Whether adapter can handle format.
  bool supportsFormat(String format) {
    return supportedFormats.contains(format.toLowerCase());
  }

  /// Creates a copy with modifications.
  PlayerAdapterCapabilities copyWith({
    bool? supportsLive,
    bool? supportsSeek,
    bool? supportsPause,
    bool? supportsStop,
    bool? supportsRateControl,
    bool? supportsVolumeControl,
    bool? supportsMuteControl,
    bool? supportsAudioOnly,
    bool? supportsEngineOptions,
    bool? supportsVideoFrameProgress,
    bool? supportsVideoSizeChanged,
    bool? supportsVideoReconfig,
    bool? supportsHwdecInfo,
    bool? supportsVideoFilters,
    bool? supportsScreenshot,
    bool? supportsAudioReconfig,
    bool? supportsAudioDeviceSelection,
    bool? supportsAudioFilters,
    bool? supportsTrackSelection,
    bool? supportsSubtitleTrack,
    bool? supportsExternalSubtitle,
    bool? supportsCacheState,
    bool? supportsBufferingProgress,
    bool? supportsBufferedRanges,
    bool? supportsChapterControl,
    bool? supportsLoop,
    bool? supportsMetadata,
    bool? supportsPlaylist,
    bool? supportsPlaylistControl,
    bool? supportsClientMessage,
    bool? supportsLogMessages,
    bool? supportsHardwareDecoder,
    bool? supportsSoftwareDecoder,
    bool? supportsPictureInPicture,
    bool? supportsFullscreen,
    Set<String>? supportedProtocols,
    Set<String>? supportedFormats,
    CompositeSupport? compositeSupport,
  }) {
    return PlayerAdapterCapabilities(
      supportsLive: supportsLive ?? this.supportsLive,
      supportsSeek: supportsSeek ?? this.supportsSeek,
      supportsPause: supportsPause ?? this.supportsPause,
      supportsStop: supportsStop ?? this.supportsStop,
      supportsRateControl: supportsRateControl ?? this.supportsRateControl,
      supportsVolumeControl: supportsVolumeControl ?? this.supportsVolumeControl,
      supportsMuteControl: supportsMuteControl ?? this.supportsMuteControl,
      supportsAudioOnly: supportsAudioOnly ?? this.supportsAudioOnly,
      supportsEngineOptions: supportsEngineOptions ?? this.supportsEngineOptions,
      supportsVideoFrameProgress: supportsVideoFrameProgress ?? this.supportsVideoFrameProgress,
      supportsVideoSizeChanged: supportsVideoSizeChanged ?? this.supportsVideoSizeChanged,
      supportsVideoReconfig: supportsVideoReconfig ?? this.supportsVideoReconfig,
      supportsHwdecInfo: supportsHwdecInfo ?? this.supportsHwdecInfo,
      supportsVideoFilters: supportsVideoFilters ?? this.supportsVideoFilters,
      supportsScreenshot: supportsScreenshot ?? this.supportsScreenshot,
      supportsAudioReconfig: supportsAudioReconfig ?? this.supportsAudioReconfig,
      supportsAudioDeviceSelection: supportsAudioDeviceSelection ?? this.supportsAudioDeviceSelection,
      supportsAudioFilters: supportsAudioFilters ?? this.supportsAudioFilters,
      supportsTrackSelection: supportsTrackSelection ?? this.supportsTrackSelection,
      supportsSubtitleTrack: supportsSubtitleTrack ?? this.supportsSubtitleTrack,
      supportsExternalSubtitle: supportsExternalSubtitle ?? this.supportsExternalSubtitle,
      supportsCacheState: supportsCacheState ?? this.supportsCacheState,
      supportsBufferingProgress: supportsBufferingProgress ?? this.supportsBufferingProgress,
      supportsBufferedRanges: supportsBufferedRanges ?? this.supportsBufferedRanges,
      supportsChapterControl: supportsChapterControl ?? this.supportsChapterControl,
      supportsLoop: supportsLoop ?? this.supportsLoop,
      supportsMetadata: supportsMetadata ?? this.supportsMetadata,
      supportsPlaylist: supportsPlaylist ?? this.supportsPlaylist,
      supportsPlaylistControl: supportsPlaylistControl ?? this.supportsPlaylistControl,
      supportsClientMessage: supportsClientMessage ?? this.supportsClientMessage,
      supportsLogMessages: supportsLogMessages ?? this.supportsLogMessages,
      supportsHardwareDecoder: supportsHardwareDecoder ?? this.supportsHardwareDecoder,
      supportsSoftwareDecoder: supportsSoftwareDecoder ?? this.supportsSoftwareDecoder,
      supportsPictureInPicture: supportsPictureInPicture ?? this.supportsPictureInPicture,
      supportsFullscreen: supportsFullscreen ?? this.supportsFullscreen,
      supportedProtocols: supportedProtocols ?? this.supportedProtocols,
      supportedFormats: supportedFormats ?? this.supportedFormats,
      compositeSupport: compositeSupport ?? this.compositeSupport,
    );
  }

  @override
  List<Object?> get props => [
    supportsLive,
    supportsSeek,
    supportsPause,
    supportsStop,
    supportsRateControl,
    supportsVolumeControl,
    supportsMuteControl,
    supportsAudioOnly,
    supportsEngineOptions,
    supportsVideoFrameProgress,
    supportsVideoSizeChanged,
    supportsVideoReconfig,
    supportsHwdecInfo,
    supportsVideoFilters,
    supportsScreenshot,
    supportsAudioReconfig,
    supportsAudioDeviceSelection,
    supportsAudioFilters,
    supportsTrackSelection,
    supportsSubtitleTrack,
    supportsExternalSubtitle,
    supportsCacheState,
    supportsBufferingProgress,
    supportsBufferedRanges,
    supportsChapterControl,
    supportsLoop,
    supportsMetadata,
    supportsPlaylist,
    supportsPlaylistControl,
    supportsClientMessage,
    supportsLogMessages,
    supportsHardwareDecoder,
    supportsSoftwareDecoder,
    supportsPictureInPicture,
    supportsFullscreen,
    supportedProtocols,
    supportedFormats,
    compositeSupport,
  ];
}
