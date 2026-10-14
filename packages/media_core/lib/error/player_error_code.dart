import 'package:equatable/equatable.dart';
import 'package:media_core/error/player_error_category.dart' show PlayerErrorCategory;

/// Stable machine-readable error code used by the media player core.
///
/// Error codes represent specific failures. They are intentionally separated
/// from [PlayerErrorCategory], which represents a broader classification.
///
/// This class is implemented as a value type instead of an enum so that
/// applications and adapters can define custom error codes when necessary.
///
/// Error codes are:
///
/// - immutable;
/// - value-based;
/// - stable across serialization;
/// - independent from error classification;
/// - independent from retry/fallback policy.
final class PlayerErrorCode extends Equatable implements Comparable<PlayerErrorCode> {
  const PlayerErrorCode._(this.value, this.name);

  /// Creates a custom player error code.
  ///
  /// Custom codes are preserved after trimming and are considered
  /// non-built-in codes.
  factory PlayerErrorCode.custom(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'PlayerIdentity error code cannot be empty.');
    }

    return PlayerErrorCode._(normalized, normalized);
  }

  // ===========================================================================
  // General
  // ===========================================================================

  /// No more specific code describes the failure.
  static const PlayerErrorCode unknown = PlayerErrorCode._('PLAYER_UNKNOWN', 'unknown');

  /// A caller-supplied argument was rejected before the operation started.
  static const PlayerErrorCode invalidArgument = PlayerErrorCode._('PLAYER_INVALID_ARGUMENT', 'invalidArgument');

  /// The operation was issued while the player was in a state that cannot accept it.
  static const PlayerErrorCode invalidState = PlayerErrorCode._('PLAYER_INVALID_STATE', 'invalidState');

  /// The requested capability is not offered by the current configuration.
  static const PlayerErrorCode unsupported = PlayerErrorCode._('PLAYER_UNSUPPORTED', 'unsupported');

  /// An operation was explicitly cancelled through the public API.
  static const PlayerErrorCode cancelled = PlayerErrorCode._('PLAYER_CANCELLED', 'cancelled');

  /// An operation exceeded its allotted time; the caller retries via the code-specific retry path.
  static const PlayerErrorCode timeout = PlayerErrorCode._('PLAYER_TIMEOUT', 'timeout');

  /// A late result belongs to a player generation that has since been replaced.
  static const PlayerErrorCode staleGeneration = PlayerErrorCode._('PLAYER_STALE_GENERATION', 'staleGeneration');

  /// A newer command for the same target made the pending one irrelevant.
  static const PlayerErrorCode superseded = PlayerErrorCode._('PLAYER_SUPERSEDED', 'superseded');

  /// An unexpected condition inside the core; indicates a defect rather than an operational failure.
  static const PlayerErrorCode internal = PlayerErrorCode._('PLAYER_INTERNAL', 'internal');

  // ===========================================================================
  // Source
  // ===========================================================================

  /// Media playback was started without a source having been set.
  static const PlayerErrorCode sourceMissing = PlayerErrorCode._('SOURCE_MISSING', 'sourceMissing');

  /// The source URI is malformed, unsupported, or resolves to nothing playable.
  static const PlayerErrorCode sourceInvalid = PlayerErrorCode._('SOURCE_INVALID', 'sourceInvalid');

  /// URI resolution or redirect following failed before any bytes were read.
  static const PlayerErrorCode sourceResolveFailed = PlayerErrorCode._('SOURCE_RESOLVE_FAILED', 'sourceResolveFailed');

  /// The source could not be probed for duration, streams, or format before playback.
  static const PlayerErrorCode sourceInspectFailed = PlayerErrorCode._('SOURCE_INSPECT_FAILED', 'sourceInspectFailed');

  /// The source was inspected but did not pass the configured validation rules.
  static const PlayerErrorCode sourceValidationFailed = PlayerErrorCode._(
    'SOURCE_VALIDATION_FAILED',
    'sourceValidationFailed',
  );

  /// The URI scheme, for example an unimplemented streaming protocol, is not supported.
  static const PlayerErrorCode sourceProtocolUnsupported = PlayerErrorCode._(
    'SOURCE_PROTOCOL_UNSUPPORTED',
    'sourceProtocolUnsupported',
  );

  /// The container or media type is not among the types the active adapter handles.
  static const PlayerErrorCode sourceMediaTypeUnsupported = PlayerErrorCode._(
    'SOURCE_MEDIA_TYPE_UNSUPPORTED',
    'sourceMediaTypeUnsupported',
  );

  /// A specific media format was rejected even though the general media type is known.
  static const PlayerErrorCode sourceFormatUnsupported = PlayerErrorCode._(
    'SOURCE_FORMAT_UNSUPPORTED',
    'sourceFormatUnsupported',
  );

  // ===========================================================================
  // Network / HTTP / Authentication
  // ===========================================================================

  /// A network failure occurred that no more specific network code describes.
  static const PlayerErrorCode network = PlayerErrorCode._('NETWORK_ERROR', 'network');

  /// No usable network interface was available when the request was issued.
  static const PlayerErrorCode networkUnavailable = PlayerErrorCode._('NETWORK_UNAVAILABLE', 'networkUnavailable');

  /// Reading from the network exceeded its deadline; distinct from a whole-operation timeout.
  static const PlayerErrorCode networkTimeout = PlayerErrorCode._('NETWORK_TIMEOUT', 'networkTimeout');

  /// The host of the media URL could not be resolved.
  static const PlayerErrorCode networkDnsFailed = PlayerErrorCode._('NETWORK_DNS_FAILED', 'networkDnsFailed');

  /// The media connection could not be established or was lost while streaming.
  static const PlayerErrorCode networkConnectionFailed = PlayerErrorCode._(
    'NETWORK_CONNECTION_FAILED',
    'networkConnectionFailed',
  );

  /// The remote endpoint actively refused the media connection.
  static const PlayerErrorCode networkConnectionRefused = PlayerErrorCode._(
    'NETWORK_CONNECTION_REFUSED',
    'networkConnectionRefused',
  );

  /// The transport aborted the transfer, typically because a local command replaced it.
  static const PlayerErrorCode networkAborted = PlayerErrorCode._('NETWORK_ABORTED', 'networkAborted');

  /// The server answered with a non-success HTTP status for the media request.
  static const PlayerErrorCode httpError = PlayerErrorCode._('HTTP_ERROR', 'httpError');

  /// The server asked for credentials that were not supplied with the request.
  static const PlayerErrorCode authenticationRequired = PlayerErrorCode._(
    'AUTHENTICATION_REQUIRED',
    'authenticationRequired',
  );

  /// The credentials supplied with the request were rejected by the server.
  static const PlayerErrorCode authenticationFailed = PlayerErrorCode._(
    'AUTHENTICATION_FAILED',
    'authenticationFailed',
  );

  /// Credentials are valid but the account or token is not allowed to play this media.
  static const PlayerErrorCode authorizationFailed = PlayerErrorCode._('AUTHORIZATION_FAILED', 'authorizationFailed');

  /// The TLS handshake or certificate validation failed, so the stream was not trusted.
  static const PlayerErrorCode tlsError = PlayerErrorCode._('TLS_ERROR', 'tlsError');

  // ===========================================================================
  // Adapter / Backend
  // ===========================================================================

  /// The player adapter that should serve the request is not present or not registered.
  static const PlayerErrorCode adapterUnavailable = PlayerErrorCode._('ADAPTER_UNAVAILABLE', 'adapterUnavailable');

  /// The adapter cannot handle the requested source or capability at all.
  static const PlayerErrorCode adapterUnsupported = PlayerErrorCode._('ADAPTER_UNSUPPORTED', 'adapterUnsupported');

  /// Adapter setup failed, so no playback session could be created.
  static const PlayerErrorCode adapterInitializationFailed = PlayerErrorCode._(
    'ADAPTER_INITIALIZATION_FAILED',
    'adapterInitializationFailed',
  );

  /// The adapter had already been disposed when the command or event arrived.
  static const PlayerErrorCode adapterDisposed = PlayerErrorCode._('ADAPTER_DISPOSED', 'adapterDisposed');

  /// The playback backend could not be resolved or started on this platform.
  static const PlayerErrorCode backendUnavailable = PlayerErrorCode._('BACKEND_UNAVAILABLE', 'backendUnavailable');

  /// Backend setup failed after the media was opened, before playback could begin.
  static const PlayerErrorCode backendInitializationFailed = PlayerErrorCode._(
    'BACKEND_INITIALIZATION_FAILED',
    'backendInitializationFailed',
  );

  /// The backend could not open the media source.
  static const PlayerErrorCode backendOpenFailed = PlayerErrorCode._('BACKEND_OPEN_FAILED', 'backendOpenFailed');

  /// The backend rejected the start or resume command.
  static const PlayerErrorCode backendPlayFailed = PlayerErrorCode._('BACKEND_PLAY_FAILED', 'backendPlayFailed');

  /// The backend rejected the pause command.
  static const PlayerErrorCode backendPauseFailed = PlayerErrorCode._('BACKEND_PAUSE_FAILED', 'backendPauseFailed');

  /// The backend rejected the stop command.
  static const PlayerErrorCode backendStopFailed = PlayerErrorCode._('BACKEND_STOP_FAILED', 'backendStopFailed');

  /// The backend rejected the seek command.
  static const PlayerErrorCode backendSeekFailed = PlayerErrorCode._('BACKEND_SEEK_FAILED', 'backendSeekFailed');

  /// The backend reported an unrecoverable error and must be torn down.
  static const PlayerErrorCode backendFatal = PlayerErrorCode._('BACKEND_FATAL', 'backendFatal');

  // ===========================================================================
  // Playback
  // ===========================================================================

  /// Playback could not be started or continued for the current source.
  static const PlayerErrorCode playbackFailed = PlayerErrorCode._('PLAYBACK_FAILED', 'playbackFailed');

  /// The backend stopped playing although no stop was requested.
  static const PlayerErrorCode unexpectedStop = PlayerErrorCode._('UNEXPECTED_STOP', 'unexpectedStop');

  /// A playback command arrived while the backend was in a state that cannot serve it.
  static const PlayerErrorCode playbackInvalidState = PlayerErrorCode._(
    'PLAYBACK_INVALID_STATE',
    'playbackInvalidState',
  );

  /// The requested seek position lies outside the playable range.
  static const PlayerErrorCode invalidSeekPosition = PlayerErrorCode._('INVALID_SEEK_POSITION', 'invalidSeekPosition');

  /// The requested speed is outside the range the backend accepts.
  static const PlayerErrorCode invalidPlaybackRate = PlayerErrorCode._('INVALID_PLAYBACK_RATE', 'invalidPlaybackRate');

  /// The requested volume is outside the supported range.
  static const PlayerErrorCode invalidVolume = PlayerErrorCode._('INVALID_VOLUME', 'invalidVolume');

  // ===========================================================================
  // Decoder / Demuxer / Media
  // ===========================================================================

  /// Video or audio decoding failed while the stream was already playing.
  static const PlayerErrorCode decoderError = PlayerErrorCode._('DECODER_ERROR', 'decoderError');

  /// No decoder capable of this stream could be obtained.
  static const PlayerErrorCode decoderUnavailable = PlayerErrorCode._('DECODER_UNAVAILABLE', 'decoderUnavailable');

  /// The stream codec is not available on this device.
  static const PlayerErrorCode codecUnsupported = PlayerErrorCode._('CODEC_UNSUPPORTED', 'codecUnsupported');

  /// Splitting the container into elementary streams failed.
  static const PlayerErrorCode demuxerError = PlayerErrorCode._('DEMUXER_ERROR', 'demuxerError');

  /// The media data is damaged and could not be decoded as supplied.
  static const PlayerErrorCode mediaCorrupted = PlayerErrorCode._('MEDIA_CORRUPTED', 'mediaCorrupted');

  /// Duration, track, or other metadata is missing or self-contradictory.
  static const PlayerErrorCode mediaMetadataInvalid = PlayerErrorCode._(
    'MEDIA_METADATA_INVALID',
    'mediaMetadataInvalid',
  );

  /// The source is readable but contains no stream the player can render.
  static const PlayerErrorCode noPlayableStream = PlayerErrorCode._('NO_PLAYABLE_STREAM', 'noPlayableStream');

  /// The media ended before its declared duration or before buffering completed.
  static const PlayerErrorCode streamEndedUnexpectedly = PlayerErrorCode._(
    'STREAM_ENDED_UNEXPECTEDLY',
    'streamEndedUnexpectedly',
  );

  // ===========================================================================
  // Resource
  // ===========================================================================

  /// A required system resource could not be acquired.
  static const PlayerErrorCode resourceUnavailable = PlayerErrorCode._('RESOURCE_UNAVAILABLE', 'resourceUnavailable');

  /// A configured limit, such as concurrent players or buffers, was reached.
  static const PlayerErrorCode resourceLimitExceeded = PlayerErrorCode._(
    'RESOURCE_LIMIT_EXCEEDED',
    'resourceLimitExceeded',
  );

  /// The device reported low memory, so playback was curtailed to stay alive.
  static const PlayerErrorCode memoryPressure = PlayerErrorCode._('MEMORY_PRESSURE', 'memoryPressure');

  /// The device is thermally throttling and can no longer sustain playback.
  static const PlayerErrorCode thermalPressure = PlayerErrorCode._('THERMAL_PRESSURE', 'thermalPressure');

  /// The connection is slower than the stream bitrate, so buffering cannot keep up.
  static const PlayerErrorCode insufficientBandwidth = PlayerErrorCode._(
    'INSUFFICIENT_BANDWIDTH',
    'insufficientBandwidth',
  );

  // ===========================================================================
  // Renderer / Presentation / Geometry
  // ===========================================================================

  /// The renderer could not be created for the surface.
  static const PlayerErrorCode rendererInitializationFailed = PlayerErrorCode._(
    'RENDERER_INITIALIZATION_FAILED',
    'rendererInitializationFailed',
  );

  /// The render surface became invalid or was lost.
  static const PlayerErrorCode rendererSurfaceFailed = PlayerErrorCode._(
    'RENDERER_SURFACE_FAILED',
    'rendererSurfaceFailed',
  );

  /// Creating or updating a texture for a frame failed.
  static const PlayerErrorCode rendererTextureFailed = PlayerErrorCode._(
    'RENDERER_TEXTURE_FAILED',
    'rendererTextureFailed',
  );

  /// The frame or layer geometry was unusable, for example a zero-sized surface.
  static const PlayerErrorCode geometryInvalid = PlayerErrorCode._('GEOMETRY_INVALID', 'geometryInvalid');

  /// Rendering or updating the visual presentation failed.
  static const PlayerErrorCode presentationFailed = PlayerErrorCode._('PRESENTATION_FAILED', 'presentationFailed');

  /// Entering or leaving picture in picture was rejected by the platform.
  static const PlayerErrorCode pipFailed = PlayerErrorCode._('PIP_FAILED', 'pipFailed');

  /// The platform refused the fullscreen transition.
  static const PlayerErrorCode fullscreenFailed = PlayerErrorCode._('FULLSCREEN_FAILED', 'fullscreenFailed');

  /// The floating or mini-player window could not be shown.
  static const PlayerErrorCode floatingFailed = PlayerErrorCode._('FLOATING_FAILED', 'floatingFailed');

  // ===========================================================================
  // Audio
  // ===========================================================================

  /// The audio output could not be configured for playback.
  static const PlayerErrorCode audioInitializationFailed = PlayerErrorCode._(
    'AUDIO_INITIALIZATION_FAILED',
    'audioInitializationFailed',
  );

  /// Audio focus or audio-session ownership was denied or lost.
  static const PlayerErrorCode audioFocusFailed = PlayerErrorCode._('AUDIO_FOCUS_FAILED', 'audioFocusFailed');

  /// The requested audio route, such as headset or bluetooth, could not be used.
  static const PlayerErrorCode audioRouteFailed = PlayerErrorCode._('AUDIO_ROUTE_FAILED', 'audioRouteFailed');

  /// Audio output is not supported in the current configuration.
  static const PlayerErrorCode audioUnsupported = PlayerErrorCode._('AUDIO_UNSUPPORTED', 'audioUnsupported');

  // ===========================================================================
  // Recording
  // ===========================================================================

  /// The active pipeline cannot record the current stream.
  static const PlayerErrorCode recordingUnsupported = PlayerErrorCode._(
    'RECORDING_UNSUPPORTED',
    'recordingUnsupported',
  );

  /// The recorder could not be created or started.
  static const PlayerErrorCode recordingInitializationFailed = PlayerErrorCode._(
    'RECORDING_INITIALIZATION_FAILED',
    'recordingInitializationFailed',
  );

  /// Recording stopped because the capture path itself failed.
  static const PlayerErrorCode recordingFailed = PlayerErrorCode._('RECORDING_FAILED', 'recordingFailed');

  /// The output location or container for the recording is not usable.
  static const PlayerErrorCode recordingOutputInvalid = PlayerErrorCode._(
    'RECORDING_OUTPUT_INVALID',
    'recordingOutputInvalid',
  );

  /// The storage medium for the recording is missing, full, or not writable.
  static const PlayerErrorCode recordingStorageUnavailable = PlayerErrorCode._(
    'RECORDING_STORAGE_UNAVAILABLE',
    'recordingStorageUnavailable',
  );

  // ===========================================================================
  // Cache
  // ===========================================================================

  /// A cache operation failed for a reason no more specific cache code describes.
  static const PlayerErrorCode cacheError = PlayerErrorCode._('CACHE_ERROR', 'cacheError');

  /// The cache directory or volume could not be used.
  static const PlayerErrorCode cacheStorageUnavailable = PlayerErrorCode._(
    'CACHE_STORAGE_UNAVAILABLE',
    'cacheStorageUnavailable',
  );

  /// A cached entry is corrupt or does not match the source it claims to serve.
  static const PlayerErrorCode cacheEntryInvalid = PlayerErrorCode._('CACHE_ENTRY_INVALID', 'cacheEntryInvalid');

  /// The cache could not grow enough to accept the requested data.
  static const PlayerErrorCode cacheLimitExceeded = PlayerErrorCode._('CACHE_LIMIT_EXCEEDED', 'cacheLimitExceeded');

  // ===========================================================================
  // Concurrency
  // ===========================================================================

  /// The limit on concurrent operations of this kind was reached.
  static const PlayerErrorCode concurrencyLimitExceeded = PlayerErrorCode._(
    'CONCURRENCY_LIMIT_EXCEEDED',
    'concurrencyLimitExceeded',
  );

  /// A required lock was held elsewhere and could not be acquired.
  static const PlayerErrorCode lockUnavailable = PlayerErrorCode._('LOCK_UNAVAILABLE', 'lockUnavailable');

  // ===========================================================================
  // Lifecycle
  // ===========================================================================

  /// The player or component was disposed while an operation or subscription was still active.
  static const PlayerErrorCode disposed = PlayerErrorCode._('PLAYER_DISPOSED', 'disposed');

  /// The app or widget lifecycle is inactive, so playback is not allowed.
  static const PlayerErrorCode lifecycleInactive = PlayerErrorCode._('LIFECYCLE_INACTIVE', 'lifecycleInactive');

  /// A lifecycle transition, such as resume or backgrounding, failed.
  static const PlayerErrorCode lifecycleTransitionFailed = PlayerErrorCode._(
    'LIFECYCLE_TRANSITION_FAILED',
    'lifecycleTransitionFailed',
  );

  // ===========================================================================
  // Fallback / Recovery
  // ===========================================================================

  /// No alternate source or path is available to fall back to.
  static const PlayerErrorCode fallbackUnavailable = PlayerErrorCode._('FALLBACK_UNAVAILABLE', 'fallbackUnavailable');

  /// Fallback candidates existed, but none could be selected as usable.
  static const PlayerErrorCode fallbackSelectionFailed = PlayerErrorCode._(
    'FALLBACK_SELECTION_FAILED',
    'fallbackSelectionFailed',
  );

  /// Recovery is not configured or not possible for this failure.
  static const PlayerErrorCode recoveryUnavailable = PlayerErrorCode._('RECOVERY_UNAVAILABLE', 'recoveryUnavailable');

  /// A recovery action was attempted and did not restore playback.
  static const PlayerErrorCode recoveryFailed = PlayerErrorCode._('RECOVERY_FAILED', 'recoveryFailed');

  /// The recovery ladder ran out of actions without restoring playback.
  static const PlayerErrorCode recoveryExhausted = PlayerErrorCode._('RECOVERY_EXHAUSTED', 'recoveryExhausted');

  // ===========================================================================
  // Properties
  // ===========================================================================

  /// Stable machine-readable error code.
  final String value;

  /// Stable symbolic name intended for diagnostics and debugging.
  final String name;

  /// Whether this is one of the built-in player error codes.
  bool get isBuiltIn => _builtInCodes.contains(value);

  /// Whether this is a custom error code.
  bool get isCustom => !isBuiltIn;

  /// Whether this represents cancellation or invalidation of an operation.
  ///
  /// Value comparison is intentionally used instead of [identical] because
  /// [PlayerErrorCode] is a value object.
  bool get isCancellation {
    return _cancellationCodes.contains(value);
  }

  /// Whether this code belongs to the network-related family.
  bool get isNetworkRelated {
    return _networkCodes.contains(value);
  }

  /// Whether this code belongs to the source-related family.
  bool get isSourceRelated {
    return _sourceCodes.contains(value);
  }

  /// Whether this code belongs to the adapter/backend family.
  ///
  /// This includes both adapter-level and backend-level failures.
  bool get isAdapterOrBackendRelated {
    return _adapterOrBackendCodes.contains(value);
  }

  /// Whether this code belongs to the adapter/backend family.
  ///
  /// Kept as a compatibility-oriented alias.
  bool get isBackendRelated {
    return isAdapterOrBackendRelated;
  }

  /// Whether this code belongs to the playback family.
  bool get isPlaybackRelated {
    return _playbackCodes.contains(value);
  }

  /// Whether this code belongs to the media decoding/demuxing family.
  bool get isMediaPipelineRelated {
    return _mediaPipelineCodes.contains(value);
  }

  /// Whether this code belongs to the resource-pressure family.
  bool get isResourceRelated {
    return _resourceCodes.contains(value);
  }

  /// Whether this code belongs to the presentation/rendering family.
  bool get isPresentationRelated {
    return _presentationCodes.contains(value);
  }

  /// Whether this error may potentially be recoverable.
  ///
  /// This is only a classification hint.
  ///
  /// It does NOT determine whether the player should:
  ///
  /// - retry;
  /// - fallback;
  /// - recover;
  /// - stop playback.
  ///
  /// Those decisions belong to the policy layer.
  bool get isPotentiallyRecoverable {
    return _potentiallyRecoverableCodes.contains(value);
  }

  // ===========================================================================
  // Lookup
  // ===========================================================================

  /// Returns all built-in error codes.
  static List<PlayerErrorCode> get values {
    return List<PlayerErrorCode>.unmodifiable(_builtInValues);
  }

  /// Resolves a built-in error code from its stable value.
  ///
  /// Unknown values resolve to [unknown].
  ///
  /// Use [PlayerErrorCode.custom] when custom error-code preservation is required.
  static PlayerErrorCode fromValue(String value) {
    final normalized = value.trim();

    for (final code in _builtInValues) {
      if (code.value == normalized) {
        return code;
      }
    }

    return PlayerErrorCode.unknown;
  }

  /// Parses a built-in error code from a string.
  ///
  /// This is an alias for [fromValue].
  static PlayerErrorCode parse(String value) {
    return fromValue(value);
  }

  /// Creates an error code from its JSON representation.
  ///
  /// Unknown values resolve to [unknown].
  static PlayerErrorCode fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('PlayerErrorCode JSON value must be a String.');
    }

    return fromValue(json);
  }

  /// Converts this error code to its JSON representation.
  String toJson() => value;

  /// Returns whether [value] is a built-in error code value.
  static bool isBuiltInValue(String value) {
    return _builtInCodes.contains(value.trim());
  }

  /// Returns whether [value] is one of the cancellation codes.
  static bool isCancellationValue(String value) {
    return _cancellationCodes.contains(value.trim());
  }

  /// Returns whether [value] is one of the network-related codes.
  static bool isNetworkRelatedValue(String value) {
    return _networkCodes.contains(value.trim());
  }

  /// Returns the built-in error code matching [value], or `null`.
  static PlayerErrorCode? tryFromValue(String value) {
    final normalized = value.trim();

    for (final code in _builtInValues) {
      if (code.value == normalized) {
        return code;
      }
    }

    return null;
  }

  /// Returns all built-in codes belonging to [predicate].
  static List<PlayerErrorCode> where(bool Function(PlayerErrorCode code) predicate) {
    return List<PlayerErrorCode>.unmodifiable(_builtInValues.where(predicate));
  }

  // ===========================================================================
  // Value helpers
  // ===========================================================================

  /// Returns a copy with optionally replaced fields.
  ///
  /// This method can create a custom value when [value] is not a built-in
  /// error code.
  PlayerErrorCode copyWith({String? value, String? name}) {
    final nextValue = (value ?? this.value).trim();
    final nextName = (name ?? this.name).trim();

    if (nextValue.isEmpty) {
      throw ArgumentError.value(value, 'value', 'PlayerIdentity error code cannot be empty.');
    }

    if (nextName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'PlayerIdentity error code name cannot be empty.');
    }

    return PlayerErrorCode._(nextValue, nextName);
  }

  /// Returns whether this code has the same stable value as [other].
  bool isSameAs(PlayerErrorCode other) {
    return value == other.value;
  }

  /// Returns whether this code has a different stable value from [other].
  bool isDifferentFrom(PlayerErrorCode other) {
    return value != other.value;
  }

  /// Returns the lexicographical comparison result against [other].
  @override
  int compareTo(PlayerErrorCode other) {
    return value.compareTo(other.value);
  }

  // ===========================================================================
  // Equatable
  // ===========================================================================

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() => value;
}

// =============================================================================
// Built-in values
// =============================================================================

const List<PlayerErrorCode> _builtInValues = <PlayerErrorCode>[
  // General
  PlayerErrorCode.unknown,
  PlayerErrorCode.invalidArgument,
  PlayerErrorCode.invalidState,
  PlayerErrorCode.unsupported,
  PlayerErrorCode.cancelled,
  PlayerErrorCode.timeout,
  PlayerErrorCode.staleGeneration,
  PlayerErrorCode.superseded,
  PlayerErrorCode.internal,

  // Source
  PlayerErrorCode.sourceMissing,
  PlayerErrorCode.sourceInvalid,
  PlayerErrorCode.sourceResolveFailed,
  PlayerErrorCode.sourceInspectFailed,
  PlayerErrorCode.sourceValidationFailed,
  PlayerErrorCode.sourceProtocolUnsupported,
  PlayerErrorCode.sourceMediaTypeUnsupported,
  PlayerErrorCode.sourceFormatUnsupported,

  // Network / HTTP / Authentication
  PlayerErrorCode.network,
  PlayerErrorCode.networkUnavailable,
  PlayerErrorCode.networkTimeout,
  PlayerErrorCode.networkDnsFailed,
  PlayerErrorCode.networkConnectionFailed,
  PlayerErrorCode.networkConnectionRefused,
  PlayerErrorCode.networkAborted,
  PlayerErrorCode.httpError,
  PlayerErrorCode.authenticationRequired,
  PlayerErrorCode.authenticationFailed,
  PlayerErrorCode.authorizationFailed,
  PlayerErrorCode.tlsError,

  // Adapter / Backend
  PlayerErrorCode.adapterUnavailable,
  PlayerErrorCode.adapterUnsupported,
  PlayerErrorCode.adapterInitializationFailed,
  PlayerErrorCode.adapterDisposed,
  PlayerErrorCode.backendUnavailable,
  PlayerErrorCode.backendInitializationFailed,
  PlayerErrorCode.backendOpenFailed,
  PlayerErrorCode.backendPlayFailed,
  PlayerErrorCode.backendPauseFailed,
  PlayerErrorCode.backendStopFailed,
  PlayerErrorCode.backendSeekFailed,
  PlayerErrorCode.backendFatal,

  // Playback
  PlayerErrorCode.playbackFailed,
  PlayerErrorCode.unexpectedStop,
  PlayerErrorCode.playbackInvalidState,
  PlayerErrorCode.invalidSeekPosition,
  PlayerErrorCode.invalidPlaybackRate,
  PlayerErrorCode.invalidVolume,

  // Decoder / Demuxer / Media
  PlayerErrorCode.decoderError,
  PlayerErrorCode.decoderUnavailable,
  PlayerErrorCode.codecUnsupported,
  PlayerErrorCode.demuxerError,
  PlayerErrorCode.mediaCorrupted,
  PlayerErrorCode.mediaMetadataInvalid,
  PlayerErrorCode.noPlayableStream,
  PlayerErrorCode.streamEndedUnexpectedly,

  // Resource
  PlayerErrorCode.resourceUnavailable,
  PlayerErrorCode.resourceLimitExceeded,
  PlayerErrorCode.memoryPressure,
  PlayerErrorCode.thermalPressure,
  PlayerErrorCode.insufficientBandwidth,

  // Renderer / Presentation / Geometry
  PlayerErrorCode.rendererInitializationFailed,
  PlayerErrorCode.rendererSurfaceFailed,
  PlayerErrorCode.rendererTextureFailed,
  PlayerErrorCode.geometryInvalid,
  PlayerErrorCode.presentationFailed,
  PlayerErrorCode.pipFailed,
  PlayerErrorCode.fullscreenFailed,
  PlayerErrorCode.floatingFailed,

  // Audio
  PlayerErrorCode.audioInitializationFailed,
  PlayerErrorCode.audioFocusFailed,
  PlayerErrorCode.audioRouteFailed,
  PlayerErrorCode.audioUnsupported,

  // Recording
  PlayerErrorCode.recordingUnsupported,
  PlayerErrorCode.recordingInitializationFailed,
  PlayerErrorCode.recordingFailed,
  PlayerErrorCode.recordingOutputInvalid,
  PlayerErrorCode.recordingStorageUnavailable,

  // Cache
  PlayerErrorCode.cacheError,
  PlayerErrorCode.cacheStorageUnavailable,
  PlayerErrorCode.cacheEntryInvalid,
  PlayerErrorCode.cacheLimitExceeded,

  // Concurrency
  PlayerErrorCode.concurrencyLimitExceeded,
  PlayerErrorCode.lockUnavailable,

  // Lifecycle
  PlayerErrorCode.disposed,
  PlayerErrorCode.lifecycleInactive,
  PlayerErrorCode.lifecycleTransitionFailed,

  // Fallback / Recovery
  PlayerErrorCode.fallbackUnavailable,
  PlayerErrorCode.fallbackSelectionFailed,
  PlayerErrorCode.recoveryUnavailable,
  PlayerErrorCode.recoveryFailed,
  PlayerErrorCode.recoveryExhausted,
];

// =============================================================================
// Code groups
// =============================================================================

final Set<String> _builtInCodes = <String>{for (final code in _builtInValues) code.value};

const Set<String> _cancellationCodes = <String>{'PLAYER_CANCELLED', 'PLAYER_STALE_GENERATION', 'PLAYER_SUPERSEDED'};

const Set<String> _networkCodes = <String>{
  'NETWORK_ERROR',
  'NETWORK_UNAVAILABLE',
  'NETWORK_TIMEOUT',
  'NETWORK_DNS_FAILED',
  'NETWORK_CONNECTION_FAILED',
  'NETWORK_CONNECTION_REFUSED',
  'NETWORK_ABORTED',
  'HTTP_ERROR',
  'AUTHENTICATION_REQUIRED',
  'AUTHENTICATION_FAILED',
  'AUTHORIZATION_FAILED',
  'TLS_ERROR',
};

const Set<String> _sourceCodes = <String>{
  'SOURCE_MISSING',
  'SOURCE_INVALID',
  'SOURCE_RESOLVE_FAILED',
  'SOURCE_INSPECT_FAILED',
  'SOURCE_VALIDATION_FAILED',
  'SOURCE_PROTOCOL_UNSUPPORTED',
  'SOURCE_MEDIA_TYPE_UNSUPPORTED',
  'SOURCE_FORMAT_UNSUPPORTED',
};

const Set<String> _adapterOrBackendCodes = <String>{
  'ADAPTER_UNAVAILABLE',
  'ADAPTER_UNSUPPORTED',
  'ADAPTER_INITIALIZATION_FAILED',
  'ADAPTER_DISPOSED',
  'BACKEND_UNAVAILABLE',
  'BACKEND_INITIALIZATION_FAILED',
  'BACKEND_OPEN_FAILED',
  'BACKEND_PLAY_FAILED',
  'BACKEND_PAUSE_FAILED',
  'BACKEND_STOP_FAILED',
  'BACKEND_SEEK_FAILED',
  'BACKEND_FATAL',
};

const Set<String> _playbackCodes = <String>{
  'PLAYBACK_FAILED',
  'UNEXPECTED_STOP',
  'PLAYBACK_INVALID_STATE',
  'INVALID_SEEK_POSITION',
  'INVALID_PLAYBACK_RATE',
  'INVALID_VOLUME',
};

const Set<String> _mediaPipelineCodes = <String>{
  'DECODER_ERROR',
  'DECODER_UNAVAILABLE',
  'CODEC_UNSUPPORTED',
  'DEMUXER_ERROR',
  'MEDIA_CORRUPTED',
  'MEDIA_METADATA_INVALID',
  'NO_PLAYABLE_STREAM',
  'STREAM_ENDED_UNEXPECTEDLY',
};

const Set<String> _resourceCodes = <String>{
  'RESOURCE_UNAVAILABLE',
  'RESOURCE_LIMIT_EXCEEDED',
  'MEMORY_PRESSURE',
  'THERMAL_PRESSURE',
  'INSUFFICIENT_BANDWIDTH',
};

const Set<String> _presentationCodes = <String>{
  'RENDERER_INITIALIZATION_FAILED',
  'RENDERER_SURFACE_FAILED',
  'RENDERER_TEXTURE_FAILED',
  'GEOMETRY_INVALID',
  'PRESENTATION_FAILED',
  'PIP_FAILED',
  'FULLSCREEN_FAILED',
  'FLOATING_FAILED',
};

/// Classification hints only.
///
/// This set deliberately does not contain every technically recoverable
/// error. The actual retry/recovery decision belongs to ErrorPolicy.
const Set<String> _potentiallyRecoverableCodes = <String>{
  // Network.
  'NETWORK_ERROR',
  'NETWORK_UNAVAILABLE',
  'NETWORK_TIMEOUT',
  'NETWORK_DNS_FAILED',
  'NETWORK_CONNECTION_FAILED',
  'NETWORK_CONNECTION_REFUSED',
  'NETWORK_ABORTED',

  // HTTP.
  'HTTP_ERROR',

  // Security.
  'TLS_ERROR',

  // Backend.
  'BACKEND_UNAVAILABLE',
  'BACKEND_INITIALIZATION_FAILED',
  'BACKEND_OPEN_FAILED',
  'BACKEND_PLAY_FAILED',
  'BACKEND_FATAL',

  // Decoder.
  'DECODER_ERROR',
  'DECODER_UNAVAILABLE',

  // Media.
  'STREAM_ENDED_UNEXPECTEDLY',

  // Resource.
  'RESOURCE_UNAVAILABLE',
  'MEMORY_PRESSURE',
  'THERMAL_PRESSURE',
  'INSUFFICIENT_BANDWIDTH',

  // Renderer.
  'RENDERER_INITIALIZATION_FAILED',
  'RENDERER_SURFACE_FAILED',

  // Audio.
  'AUDIO_INITIALIZATION_FAILED',

  // Fallback / Recovery.
  'FALLBACK_UNAVAILABLE',
  'RECOVERY_FAILED',
};
