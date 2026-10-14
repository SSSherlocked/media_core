import 'package:equatable/equatable.dart';
import 'package:media_core/core/library.dart' show PlayerCapabilities, PlayerCoreState;
import 'package:media_core/core/media_capabilities.dart';
import 'package:media_core/core/player_constants.dart';
import 'package:media_core/core/player_media_type.dart';
import 'package:media_core/identity/source_id.dart';

/// Defines the immutable configuration of a player.
///
/// [PlayerConfig] describes how a player should be created and its initial
/// operating preferences.
///
/// Runtime state belongs to [PlayerCoreState].
/// Implementation capabilities belong to [PlayerCapabilities].
/// Runtime policy and orchestration belong to their respective modules.
///
/// [PlayerConfig] intentionally contains no runtime session, adapter,
/// operation, or playback-controller references.
final class PlayerConfig extends Equatable {
  /// Creates an immutable player configuration.
  const PlayerConfig({
    this.name,
    this.mediaType,
    this.mediaCapabilities,
    this.sourceId,
    this.autoInitialize = true,
    this.autoPlay = false,
    this.loop = false,
    this.muted = false,
    this.volume = PlayerConstants.defaultVolume,
    this.playbackRate = PlayerConstants.defaultPlaybackRate,
    this.preload = true,
    this.keepAlive = true,
    this.pauseWhenBackgrounded,
    this.preferHardwareDecoding = true,
    this.enableAudio = true,
    this.enableVideo = true,
    this.enableSubtitles = true,
    this.enableBuffering = true,
    this.enableRecovery = true,
    this.enableFallback = true,
    this.enableMetrics = true,
    this.enableDiagnostics = false,
    this.maxRecoveryAttempts = PlayerConstants.maxRecoveryAttempts,
    this.maxFallbackAttempts = PlayerConstants.maxFallbackAttempts,
  }) : assert(
         volume >= PlayerConstants.minVolume && volume <= PlayerConstants.maxVolume,
         'Volume must be between 0.0 and 1.0.',
       ),
       assert(
         playbackRate >= PlayerConstants.minPlaybackRate && playbackRate <= PlayerConstants.maxPlaybackRate,
         'Playback rate is outside the supported range.',
       ),
       assert(maxRecoveryAttempts >= 0, 'Max recovery attempts must not be negative.'),
       assert(maxFallbackAttempts >= 0, 'Max fallback attempts must not be negative.');

  /// Whether leaving the app pauses this player.
  ///
  /// Null defers to `KernelOptions.pauseWhenBackgrounded` (which is on). This is
  /// the per-player exception: a feed page and the wall players next to it should
  /// stop with the app, while the one narration track the viewer is listening to
  /// keeps going — and only the playback owner knows which is which.
  final bool? pauseWhenBackgrounded;

  /// Optional human-readable player name.
  final String? name;

  /// Declared media type.
  final PlayerMediaType? mediaType;

  /// Detailed media capabilities.
  final MediaCapabilities? mediaCapabilities;

  /// Optional source identifier associated with this configuration.
  final SourceId? sourceId;

  /// Whether the player should initialize automatically.
  final bool autoInitialize;

  /// Whether playback should start automatically after opening.
  final bool autoPlay;

  /// Whether playback should restart automatically after completion.
  final bool loop;

  /// Whether audio output should initially be muted.
  final bool muted;

  /// Initial volume in the range from 0.0 to 1.0.
  final double volume;

  /// Initial playback rate.
  final double playbackRate;

  /// Whether media should be preloaded when possible.
  final bool preload;

  /// Whether player resources should remain alive while detached.
  final bool keepAlive;

  /// Whether hardware decoding should be preferred.
  final bool preferHardwareDecoding;

  /// Whether audio output is enabled.
  final bool enableAudio;

  /// Whether video output is enabled.
  final bool enableVideo;

  /// Whether subtitle processing is enabled.
  final bool enableSubtitles;

  /// Whether buffering support is enabled.
  final bool enableBuffering;

  /// Whether automatic recovery is enabled.
  ///
  /// Recovery orchestration itself does not belong to [PlayerConfig].
  final bool enableRecovery;

  /// Whether backend/source fallback is enabled.
  ///
  /// Fallback orchestration itself does not belong to [PlayerConfig].
  final bool enableFallback;

  /// Whether runtime metrics collection is enabled.
  final bool enableMetrics;

  /// Whether diagnostic collection is enabled.
  final bool enableDiagnostics;

  /// Maximum number of recovery attempts.
  final int maxRecoveryAttempts;

  /// Maximum number of fallback attempts.
  final int maxFallbackAttempts;

  /// Whether a non-empty name has been configured.
  bool get hasName => name != null && name!.trim().isNotEmpty;

  /// Whether a media type has been configured.
  bool get hasMediaType => mediaType != null;

  /// Whether media capabilities have been configured.
  bool get hasMediaCapabilities => mediaCapabilities != null;

  /// Whether a source has been associated.
  bool get hasSource => sourceId != null;

  /// Whether audio output is enabled.
  bool get hasAudio => enableAudio;

  /// Whether video output is enabled.
  bool get hasVideo => enableVideo;

  /// Returns whether this configuration represents audio-only playback.
  bool get isAudioOnly {
    final capabilities = mediaCapabilities;
    if (capabilities != null) {
      return capabilities.isAudioOnly;
    }

    final type = mediaType;
    if (type != null) {
      return type.isAudioOnly;
    }

    return enableAudio && !enableVideo;
  }

  /// Returns whether this configuration represents video-only playback.
  bool get isVideoOnly {
    final capabilities = mediaCapabilities;
    if (capabilities != null) {
      return capabilities.isVideoOnly;
    }

    final type = mediaType;
    if (type != null) {
      return type.isVideoOnly;
    }

    return enableVideo && !enableAudio;
  }

  /// Returns whether this configuration represents audio-video playback.
  bool get isAudioVideo {
    final capabilities = mediaCapabilities;
    if (capabilities != null) {
      return capabilities.isAudioVideo;
    }

    final type = mediaType;
    if (type != null) {
      return type.isAudioVideo;
    }

    return enableAudio && enableVideo;
  }

  /// Whether a video renderer is required.
  bool get requiresVideoRenderer {
    final capabilities = mediaCapabilities;
    if (capabilities != null) {
      return capabilities.requiresVideoRenderer;
    }

    final type = mediaType;
    if (type != null) {
      return type.requiresVideoRenderer;
    }

    return enableVideo;
  }

  /// Whether audio output is available.
  bool get hasAudioOutput => enableAudio;

  /// Whether video output is available.
  bool get hasVideoOutput => enableVideo;

  /// Whether automatic recovery is configured and allowed.
  bool get canRecover {
    return enableRecovery && maxRecoveryAttempts > 0;
  }

  /// Whether fallback is configured and allowed.
  bool get canFallback {
    return enableFallback && maxFallbackAttempts > 0;
  }

  /// Whether diagnostics are enabled.
  bool get hasDiagnostics => enableDiagnostics;

  /// Whether playback uses the normal playback rate.
  bool get isNormalPlaybackRate {
    return playbackRate == PlayerConstants.defaultPlaybackRate;
  }

  /// Whether playback is faster than normal.
  bool get isFastPlayback {
    return playbackRate > PlayerConstants.defaultPlaybackRate;
  }

  /// Whether playback is slower than normal.
  bool get isSlowPlayback {
    return playbackRate < PlayerConstants.defaultPlaybackRate;
  }

  /// Whether the initial state is muted.
  bool get isMuted => muted;

  /// Whether this configuration uses the minimal feature set.
  bool get isMinimal {
    return !autoPlay &&
        !loop &&
        !preload &&
        !enableSubtitles &&
        !enableRecovery &&
        !enableFallback &&
        !enableMetrics &&
        !enableDiagnostics;
  }

  /// Creates a copy with selectively replaced values.
  ///
  /// Null values retain the existing values.
  PlayerConfig copyWith({
    String? name,
    PlayerMediaType? mediaType,
    MediaCapabilities? mediaCapabilities,
    SourceId? sourceId,
    bool? autoInitialize,
    bool? autoPlay,
    bool? loop,
    bool? muted,
    double? volume,
    double? playbackRate,
    bool? preload,
    bool? keepAlive,
    bool? pauseWhenBackgrounded,
    bool? preferHardwareDecoding,
    bool? enableAudio,
    bool? enableVideo,
    bool? enableSubtitles,
    bool? enableBuffering,
    bool? enableRecovery,
    bool? enableFallback,
    bool? enableMetrics,
    bool? enableDiagnostics,
    int? maxRecoveryAttempts,
    int? maxFallbackAttempts,
  }) {
    return PlayerConfig(
      name: name ?? this.name,
      mediaType: mediaType ?? this.mediaType,
      mediaCapabilities: mediaCapabilities ?? this.mediaCapabilities,
      sourceId: sourceId ?? this.sourceId,
      autoInitialize: autoInitialize ?? this.autoInitialize,
      autoPlay: autoPlay ?? this.autoPlay,
      loop: loop ?? this.loop,
      muted: muted ?? this.muted,
      volume: volume ?? this.volume,
      playbackRate: playbackRate ?? this.playbackRate,
      preload: preload ?? this.preload,
      keepAlive: keepAlive ?? this.keepAlive,
      pauseWhenBackgrounded: pauseWhenBackgrounded ?? this.pauseWhenBackgrounded,
      preferHardwareDecoding: preferHardwareDecoding ?? this.preferHardwareDecoding,
      enableAudio: enableAudio ?? this.enableAudio,
      enableVideo: enableVideo ?? this.enableVideo,
      enableSubtitles: enableSubtitles ?? this.enableSubtitles,
      enableBuffering: enableBuffering ?? this.enableBuffering,
      enableRecovery: enableRecovery ?? this.enableRecovery,
      enableFallback: enableFallback ?? this.enableFallback,
      enableMetrics: enableMetrics ?? this.enableMetrics,
      enableDiagnostics: enableDiagnostics ?? this.enableDiagnostics,
      maxRecoveryAttempts: maxRecoveryAttempts ?? this.maxRecoveryAttempts,
      maxFallbackAttempts: maxFallbackAttempts ?? this.maxFallbackAttempts,
    );
  }

  /// Returns a configuration with the supplied name.
  PlayerConfig withName(String value) {
    return copyWith(name: value);
  }

  /// Returns a configuration for the supplied media type.
  PlayerConfig withMediaType(PlayerMediaType value) {
    return copyWith(mediaType: value);
  }

  /// Returns a configuration with detailed media capabilities.
  PlayerConfig withMediaCapabilities(MediaCapabilities value) {
    return copyWith(mediaCapabilities: value);
  }

  /// Returns a configuration associated with [value].
  PlayerConfig withSource(SourceId value) {
    return copyWith(sourceId: value);
  }

  /// Returns a configuration without a source.
  PlayerConfig withoutSource() {
    return PlayerConfig(
      name: name,
      mediaType: mediaType,
      mediaCapabilities: mediaCapabilities,
      autoInitialize: autoInitialize,
      autoPlay: autoPlay,
      loop: loop,
      muted: muted,
      volume: volume,
      playbackRate: playbackRate,
      preload: preload,
      keepAlive: keepAlive,
      preferHardwareDecoding: preferHardwareDecoding,
      enableAudio: enableAudio,
      enableVideo: enableVideo,
      enableSubtitles: enableSubtitles,
      enableBuffering: enableBuffering,
      enableRecovery: enableRecovery,
      enableFallback: enableFallback,
      enableMetrics: enableMetrics,
      enableDiagnostics: enableDiagnostics,
      maxRecoveryAttempts: maxRecoveryAttempts,
      maxFallbackAttempts: maxFallbackAttempts,
    );
  }

  /// Returns a configuration with automatic initialization changed.
  PlayerConfig withAutoInitialize({required bool value}) {
    return copyWith(autoInitialize: value);
  }

  /// Returns a configuration with automatic playback changed.
  PlayerConfig withAutoPlay({required bool value}) {
    return copyWith(autoPlay: value);
  }

  /// Returns a configuration with looping changed.
  PlayerConfig withLoop({required bool value}) {
    return copyWith(loop: value);
  }

  /// Returns a configuration with mute state changed.
  PlayerConfig withMuted({required bool value}) {
    return copyWith(muted: value);
  }

  /// Returns a configuration with volume clamped to the valid range.
  PlayerConfig withVolume(double value) {
    return copyWith(volume: PlayerConstants.clampVolume(value));
  }

  /// Returns a configuration with playback rate clamped to the valid range.
  PlayerConfig withPlaybackRate(double value) {
    return copyWith(playbackRate: PlayerConstants.clampPlaybackRate(value));
  }

  /// Returns a configuration with preloading changed.
  PlayerConfig withPreload({required bool value}) {
    return copyWith(preload: value);
  }

  /// Returns a configuration with keep-alive behavior changed.
  PlayerConfig withKeepAlive({required bool value}) {
    return copyWith(keepAlive: value);
  }

  /// Returns a configuration with hardware decoding preference changed.
  PlayerConfig withHardwareDecoding({required bool value}) {
    return copyWith(preferHardwareDecoding: value);
  }

  /// Returns a configuration with audio output changed.
  PlayerConfig withAudio({required bool value}) {
    return copyWith(enableAudio: value);
  }

  /// Returns a configuration with video output changed.
  PlayerConfig withVideo({required bool value}) {
    return copyWith(enableVideo: value);
  }

  /// Returns a configuration with subtitle processing changed.
  PlayerConfig withSubtitles({required bool value}) {
    return copyWith(enableSubtitles: value);
  }

  /// Returns a configuration with buffering changed.
  PlayerConfig withBuffering({required bool value}) {
    return copyWith(enableBuffering: value);
  }

  /// Returns a configuration with recovery changed.
  PlayerConfig withRecovery({required bool value}) {
    return copyWith(enableRecovery: value);
  }

  /// Returns a configuration with fallback changed.
  PlayerConfig withFallback({required bool value}) {
    return copyWith(enableFallback: value);
  }

  /// Returns a configuration with metrics collection changed.
  PlayerConfig withMetrics({required bool value}) {
    return copyWith(enableMetrics: value);
  }

  /// Returns a configuration with diagnostics changed.
  PlayerConfig withDiagnostics({required bool value}) {
    return copyWith(enableDiagnostics: value);
  }

  /// Returns an audio-only configuration.
  PlayerConfig asAudioOnly() {
    return copyWith(
      mediaType: PlayerMediaType.audio,
      mediaCapabilities: MediaCapabilities.audioOnly,
      enableAudio: true,
      enableVideo: false,
      enableSubtitles: false,
    );
  }

  /// Returns a video-only configuration.
  PlayerConfig asVideoOnly() {
    return copyWith(
      mediaType: PlayerMediaType.video,
      mediaCapabilities: MediaCapabilities.videoOnly,
      enableAudio: false,
      enableVideo: true,
    );
  }

  /// Returns an audio-video configuration.
  PlayerConfig asAudioVideo() {
    return copyWith(
      mediaType: PlayerMediaType.audioVideo,
      mediaCapabilities: MediaCapabilities.audioVideo,
      enableAudio: true,
      enableVideo: true,
    );
  }

  /// Default player configuration.
  static const PlayerConfig defaults = PlayerConfig();

  /// Minimal player configuration.
  static const PlayerConfig minimal = PlayerConfig(
    preload: false,
    keepAlive: false,
    enableSubtitles: false,
    enableRecovery: false,
    enableFallback: false,
    enableMetrics: false,
    maxRecoveryAttempts: 0,
    maxFallbackAttempts: 0,
  );

  /// Audio-only player configuration.
  static const PlayerConfig audioOnly = PlayerConfig(
    mediaType: PlayerMediaType.audio,
    mediaCapabilities: MediaCapabilities.audioOnly,
    enableVideo: false,
    enableSubtitles: false,
  );

  /// Video-only player configuration.
  static const PlayerConfig videoOnly = PlayerConfig(
    mediaType: PlayerMediaType.video,
    mediaCapabilities: MediaCapabilities.videoOnly,
    enableAudio: false,
  );

  /// Audio-video player configuration.
  static const PlayerConfig audioVideo = PlayerConfig(
    mediaType: PlayerMediaType.audioVideo,
    mediaCapabilities: MediaCapabilities.audioVideo,
  );

  /// Returns whether two configurations describe the same media mode.
  bool isSameMedia(PlayerConfig other) {
    return mediaType == other.mediaType &&
        mediaCapabilities == other.mediaCapabilities &&
        enableAudio == other.enableAudio &&
        enableVideo == other.enableVideo;
  }

  /// Returns whether two configurations reference the same source.
  bool isSameSource(PlayerConfig other) {
    return sourceId == other.sourceId;
  }

  @override
  List<Object?> get props => <Object?>[
    name,
    mediaType,
    mediaCapabilities,
    sourceId,
    autoInitialize,
    autoPlay,
    loop,
    muted,
    volume,
    playbackRate,
    preload,
    keepAlive,
    preferHardwareDecoding,
    enableAudio,
    enableVideo,
    enableSubtitles,
    enableBuffering,
    enableRecovery,
    enableFallback,
    enableMetrics,
    enableDiagnostics,
    maxRecoveryAttempts,
    maxFallbackAttempts,
  ];

  @override
  String toString() {
    return 'PlayerConfig('
        'name: $name, '
        'mediaType: $mediaType, '
        'mediaCapabilities: $mediaCapabilities, '
        'sourceId: $sourceId, '
        'autoInitialize: $autoInitialize, '
        'autoPlay: $autoPlay, '
        'loop: $loop, '
        'muted: $muted, '
        'volume: $volume, '
        'playbackRate: $playbackRate, '
        'preload: $preload, '
        'keepAlive: $keepAlive, '
        'preferHardwareDecoding: $preferHardwareDecoding, '
        'enableAudio: $enableAudio, '
        'enableVideo: $enableVideo, '
        'enableSubtitles: $enableSubtitles, '
        'enableBuffering: $enableBuffering, '
        'enableRecovery: $enableRecovery, '
        'enableFallback: $enableFallback, '
        'enableMetrics: $enableMetrics, '
        'enableDiagnostics: $enableDiagnostics, '
        'maxRecoveryAttempts: $maxRecoveryAttempts, '
        'maxFallbackAttempts: $maxFallbackAttempts'
        ')';
  }
}
