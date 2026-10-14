import 'package:equatable/equatable.dart';
import 'package:media_core/core/player_capabilities.dart' show PlayerCapabilities;
import 'package:media_core/core/player_constants.dart';
import 'package:media_core/identity/source_id.dart';

/// Defines immutable runtime options used to configure a player.
///
/// [PlayerOptions] describes how a player should operate.
///
/// It contains playback preferences, media output preferences, and feature
/// switches. [PlayerCapabilities] describes what the player implementation
/// is capable of doing.
///
/// Recovery, fallback, metrics, and diagnostics options are retained here for
/// compatibility with the current core API. Their execution and runtime state
/// belong to their respective modules.
final class PlayerOptions extends Equatable {
  /// Creates immutable player options.
  const PlayerOptions({
    this.autoPlay = false,
    this.autoInitialize = true,
    this.loop = false,
    this.muted = false,
    this.volume = PlayerConstants.defaultVolume,
    this.playbackRate = PlayerConstants.defaultPlaybackRate,
    this.preload = true,
    this.keepAlive = true,
    this.preferHardwareDecoding = true,
    this.enableAudio = true,
    this.enableVideo = true,
    this.enableSubtitles = true,
    this.enableBuffering = true,
    this.enableRecovery = true,
    this.enableFallback = true,
    this.enableMetrics = true,
    this.enableDiagnostics = false,
    this.sourceId,
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

  /// Whether playback should start automatically after opening.
  final bool autoPlay;

  /// Whether the player should initialize automatically.
  final bool autoInitialize;

  /// Whether playback should restart automatically after completion.
  final bool loop;

  /// Whether audio output should initially be muted.
  final bool muted;

  /// Initial player volume in the range from 0.0 to 1.0.
  final double volume;

  /// Initial playback rate.
  final double playbackRate;

  /// Whether the player should preload media data.
  final bool preload;

  /// Whether the player should keep its resources alive when temporarily
  /// detached from presentation.
  final bool keepAlive;

  /// Whether hardware decoding should be preferred when available.
  final bool preferHardwareDecoding;

  /// Whether audio output is enabled.
  final bool enableAudio;

  /// Whether video output is enabled.
  final bool enableVideo;

  /// Whether subtitle processing and presentation are enabled.
  final bool enableSubtitles;

  /// Whether buffering is enabled.
  final bool enableBuffering;

  /// Whether automatic recovery is enabled.
  final bool enableRecovery;

  /// Whether fallback handling is enabled.
  final bool enableFallback;

  /// Whether runtime metrics collection is enabled.
  final bool enableMetrics;

  /// Whether verbose diagnostics are enabled.
  final bool enableDiagnostics;

  /// Optional source identifier associated with these options.
  final SourceId? sourceId;

  /// Maximum number of recovery attempts allowed for an operation.
  final int maxRecoveryAttempts;

  /// Maximum number of fallback attempts allowed for an operation.
  final int maxFallbackAttempts;

  /// Whether a source identifier has been configured.
  bool get hasSource => sourceId != null;

  /// Whether audio output is enabled.
  bool get hasAudioOutput => enableAudio;

  /// Whether video output is enabled.
  bool get hasVideoOutput => enableVideo;

  /// Whether the options allow automatic recovery.
  ///
  /// This only describes configuration. Recovery execution belongs to the
  /// recovery module.
  bool get canRecover {
    return enableRecovery && maxRecoveryAttempts > 0;
  }

  /// Whether the options allow fallback.
  ///
  /// This only describes configuration. Fallback execution belongs to the
  /// fallback module.
  bool get canFallback {
    return enableFallback && maxFallbackAttempts > 0;
  }

  /// Whether diagnostics are enabled.
  bool get hasDiagnostics => enableDiagnostics;

  /// Whether the playback rate is normal.
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

  /// Whether the configured volume is muted.
  bool get isMuted => muted;

  /// Whether this represents the minimal preset.
  bool get isMinimal {
    return this == PlayerOptions.minimal;
  }

  /// Creates a copy with selectively replaced values.
  ///
  /// Null values retain the existing values.
  PlayerOptions copyWith({
    bool? autoPlay,
    bool? autoInitialize,
    bool? loop,
    bool? muted,
    double? volume,
    double? playbackRate,
    bool? preload,
    bool? keepAlive,
    bool? preferHardwareDecoding,
    bool? enableAudio,
    bool? enableVideo,
    bool? enableSubtitles,
    bool? enableBuffering,
    bool? enableRecovery,
    bool? enableFallback,
    bool? enableMetrics,
    bool? enableDiagnostics,
    SourceId? sourceId,
    int? maxRecoveryAttempts,
    int? maxFallbackAttempts,
  }) {
    return PlayerOptions(
      autoPlay: autoPlay ?? this.autoPlay,
      autoInitialize: autoInitialize ?? this.autoInitialize,
      loop: loop ?? this.loop,
      muted: muted ?? this.muted,
      volume: volume ?? this.volume,
      playbackRate: playbackRate ?? this.playbackRate,
      preload: preload ?? this.preload,
      keepAlive: keepAlive ?? this.keepAlive,
      preferHardwareDecoding: preferHardwareDecoding ?? this.preferHardwareDecoding,
      enableAudio: enableAudio ?? this.enableAudio,
      enableVideo: enableVideo ?? this.enableVideo,
      enableSubtitles: enableSubtitles ?? this.enableSubtitles,
      enableBuffering: enableBuffering ?? this.enableBuffering,
      enableRecovery: enableRecovery ?? this.enableRecovery,
      enableFallback: enableFallback ?? this.enableFallback,
      enableMetrics: enableMetrics ?? this.enableMetrics,
      enableDiagnostics: enableDiagnostics ?? this.enableDiagnostics,
      sourceId: sourceId ?? this.sourceId,
      maxRecoveryAttempts: maxRecoveryAttempts ?? this.maxRecoveryAttempts,
      maxFallbackAttempts: maxFallbackAttempts ?? this.maxFallbackAttempts,
    );
  }

  /// Returns options with automatic playback enabled or disabled.
  PlayerOptions withAutoPlay({required bool value}) {
    return copyWith(autoPlay: value);
  }

  /// Returns options with automatic initialization enabled or disabled.
  PlayerOptions withAutoInitialize({required bool value}) {
    return copyWith(autoInitialize: value);
  }

  /// Returns options with looping enabled or disabled.
  PlayerOptions withLoop({required bool value}) {
    return copyWith(loop: value);
  }

  /// Returns options with the requested mute state.
  PlayerOptions withMuted({required bool value}) {
    return copyWith(muted: value);
  }

  /// Returns options with a clamped volume.
  PlayerOptions withVolume(double value) {
    return copyWith(volume: PlayerConstants.clampVolume(value));
  }

  /// Returns options with a clamped playback rate.
  PlayerOptions withPlaybackRate(double value) {
    return copyWith(playbackRate: PlayerConstants.clampPlaybackRate(value));
  }

  /// Returns options with preloading enabled or disabled.
  PlayerOptions withPreload({required bool value}) {
    return copyWith(preload: value);
  }

  /// Returns options with keep-alive behavior enabled or disabled.
  PlayerOptions withKeepAlive({required bool value}) {
    return copyWith(keepAlive: value);
  }

  /// Returns options with hardware decoding preference changed.
  PlayerOptions withHardwareDecoding({required bool value}) {
    return copyWith(preferHardwareDecoding: value);
  }

  /// Returns options with audio output enabled or disabled.
  PlayerOptions withAudio({required bool value}) {
    return copyWith(enableAudio: value);
  }

  /// Returns options with video output enabled or disabled.
  PlayerOptions withVideo({required bool value}) {
    return copyWith(enableVideo: value);
  }

  /// Returns options with subtitle support enabled or disabled.
  PlayerOptions withSubtitles({required bool value}) {
    return copyWith(enableSubtitles: value);
  }

  /// Returns options with buffering enabled or disabled.
  PlayerOptions withBuffering({required bool value}) {
    return copyWith(enableBuffering: value);
  }

  /// Returns options with recovery enabled or disabled.
  PlayerOptions withRecovery({required bool value}) {
    return copyWith(enableRecovery: value);
  }

  /// Returns options with fallback enabled or disabled.
  PlayerOptions withFallback({required bool value}) {
    return copyWith(enableFallback: value);
  }

  /// Returns options with metrics collection enabled or disabled.
  PlayerOptions withMetrics({required bool value}) {
    return copyWith(enableMetrics: value);
  }

  /// Returns options with diagnostics enabled or disabled.
  PlayerOptions withDiagnostics({required bool value}) {
    return copyWith(enableDiagnostics: value);
  }

  /// Returns options associated with the supplied source identifier.
  PlayerOptions withSource(SourceId value) {
    return copyWith(sourceId: value);
  }

  /// Returns options without a source identifier.
  PlayerOptions withoutSource() {
    return PlayerOptions(
      autoPlay: autoPlay,
      autoInitialize: autoInitialize,
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

  /// Returns options for audio-only playback.
  PlayerOptions asAudioOnly() {
    return copyWith(enableAudio: true, enableVideo: false, enableSubtitles: false);
  }

  /// Returns options for video-only playback.
  PlayerOptions asVideoOnly() {
    return copyWith(enableAudio: false, enableVideo: true);
  }

  /// Returns options for combined audio-video playback.
  PlayerOptions asAudioVideo() {
    return copyWith(enableAudio: true, enableVideo: true);
  }

  /// Default player options.
  static const PlayerOptions defaults = PlayerOptions();

  /// Minimal player options.
  static const PlayerOptions minimal = PlayerOptions(
    preload: false,
    keepAlive: false,
    enableSubtitles: false,
    enableRecovery: false,
    enableFallback: false,
    enableMetrics: false,
    maxRecoveryAttempts: 0,
    maxFallbackAttempts: 0,
  );

  /// Options optimized for audio-only playback.
  static const PlayerOptions audioOnly = PlayerOptions(enableVideo: false, enableSubtitles: false);

  /// Options optimized for video-only playback.
  static const PlayerOptions videoOnly = PlayerOptions(enableAudio: false);

  /// Options optimized for combined audio-video playback.
  static const PlayerOptions audioVideo = PlayerOptions();

  /// Whether two option sets configure the same media outputs.
  bool isSameMedia(PlayerOptions other) {
    return enableAudio == other.enableAudio &&
        enableVideo == other.enableVideo &&
        enableSubtitles == other.enableSubtitles;
  }

  /// Whether two option sets reference the same source.
  bool isSameSource(PlayerOptions other) {
    return sourceId == other.sourceId;
  }

  @override
  List<Object?> get props => <Object?>[
    autoPlay,
    autoInitialize,
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
    sourceId,
    maxRecoveryAttempts,
    maxFallbackAttempts,
  ];

  @override
  String toString() {
    return 'PlayerOptions('
        'autoPlay: $autoPlay, '
        'autoInitialize: $autoInitialize, '
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
        'sourceId: $sourceId, '
        'maxRecoveryAttempts: $maxRecoveryAttempts, '
        'maxFallbackAttempts: $maxFallbackAttempts'
        ')';
  }
}
