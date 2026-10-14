import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/core/media_capabilities.dart';
import 'package:media_core/core/player_capabilities.dart';
import 'package:media_core/core/player_core_state.dart';
import 'package:media_core/core/player_media_type.dart';
import 'package:media_core/core/player_metrics.dart';
import 'package:media_core/core/player_options.dart';
import 'package:media_core/core/player_status.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/source_id.dart';

/// Represents the complete immutable observable state of a player at a
/// specific point in time.
///
/// [PlayerSnapshot] is the aggregate state exposed by the core.
///
/// It contains:
/// - stable player identity;
/// - runtime session associations;
/// - current source association;
/// - current media information;
/// - semantic player state;
/// - player options and capabilities;
/// - optional runtime metrics.
///
/// Presentation, recording, recovery, and fallback execution state belongs
/// to their respective modules and is intentionally not duplicated here.
///
/// A snapshot never owns player resources and never executes backend
/// operations.
final class PlayerSnapshot extends Equatable {
  /// Creates an immutable player snapshot.
  const PlayerSnapshot({
    required this.playerId,
    this.sessionId,
    this.requestId,
    this.generationId,
    this.sourceId,
    this.mediaType,
    this.mediaCapabilities,
    this.state = PlayerCoreState.idle,
    this.options = PlayerOptions.defaults,
    this.capabilities = PlayerCapabilities.basic,
    this.metrics,
    this.timestamp,
  });

  /// Creates an empty snapshot for [playerId].
  factory PlayerSnapshot.empty(PlayerId playerId) {
    return PlayerSnapshot(playerId: playerId, timestamp: clock.now());
  }

  /// Creates a snapshot for [playerId] using the supplied state.
  factory PlayerSnapshot.fromState({
    required PlayerId playerId,
    required PlayerCoreState state,
    SessionId? sessionId,
    RequestId? requestId,
    GenerationId? generationId,
    SourceId? sourceId,
    PlayerMediaType? mediaType,
    MediaCapabilities? mediaCapabilities,
    PlayerOptions options = PlayerOptions.defaults,
    PlayerCapabilities capabilities = PlayerCapabilities.basic,
    PlayerMetrics? metrics,
    DateTime? timestamp,
  }) {
    return PlayerSnapshot(
      playerId: playerId,
      sessionId: sessionId,
      requestId: requestId,
      generationId: generationId,
      sourceId: sourceId,
      mediaType: mediaType,
      mediaCapabilities: mediaCapabilities,
      state: state,
      options: options,
      capabilities: capabilities,
      metrics: metrics,
      timestamp: timestamp ?? clock.now(),
    );
  }

  /// Unique stable identifier of the player.
  final PlayerId playerId;

  /// Identifier of the active runtime session.
  ///
  /// This is a runtime association and does not participate in player
  /// identity.
  final SessionId? sessionId;

  /// Identifier of the operation request associated with this snapshot.
  final RequestId? requestId;

  /// Identifier of the current player generation.
  ///
  /// Generations distinguish different lifetimes of backend resources within
  /// the same player identity.
  final GenerationId? generationId;

  /// Identifier of the current media source.
  final SourceId? sourceId;

  /// Media type of the current source.
  final PlayerMediaType? mediaType;

  /// Capabilities detected for the current media source.
  ///
  /// These describe the media itself and are distinct from
  /// [PlayerCapabilities], which describe what the player implementation can
  /// do.
  final MediaCapabilities? mediaCapabilities;

  /// Complete semantic runtime state of the player.
  final PlayerCoreState state;

  /// Current player options.
  final PlayerOptions options;

  /// Capabilities exposed by the player implementation.
  ///
  /// This describes player operations, not properties of the current media.
  final PlayerCapabilities capabilities;

  /// Optional runtime metrics.
  final PlayerMetrics? metrics;

  /// Time at which this snapshot was produced.
  final DateTime? timestamp;

  /// Whether a session is associated with this snapshot.
  bool get hasSession => sessionId != null;

  /// Whether a request is associated with this snapshot.
  bool get hasRequest => requestId != null;

  /// Whether a generation is associated with this snapshot.
  bool get hasGeneration => generationId != null;

  /// Whether a source is associated with this snapshot.
  bool get hasSource => sourceId != null;

  /// Whether media type information is available.
  bool get hasMediaType => mediaType != null;

  /// Whether media capability information is available.
  bool get hasMediaCapabilities => mediaCapabilities != null;

  /// Whether runtime metrics are available.
  bool get hasMetrics => metrics != null;

  /// Current semantic player status.
  ///
  /// The status is derived from [state] and is intentionally not stored as
  /// a second independent state model.
  PlayerStatus get playerStatus {
    if (isDisposed) {
      return PlayerStatus.disposed;
    }

    if (isDisposing) {
      return PlayerStatus.disposing;
    }

    if (isOpening) {
      return PlayerStatus.opening;
    }

    if (isBuffering) {
      return PlayerStatus.buffering;
    }

    if (isSeeking) {
      return PlayerStatus.seeking;
    }

    if (isPlaying) {
      return PlayerStatus.playing;
    }

    if (isPaused) {
      return PlayerStatus.paused;
    }

    if (isStopping) {
      return PlayerStatus.stopping;
    }

    if (isCompleted) {
      return PlayerStatus.completed;
    }

    if (isStopped) {
      return PlayerStatus.stopped;
    }

    if (hasError) {
      return PlayerStatus.error;
    }

    if (isReady) {
      return PlayerStatus.ready;
    }

    return PlayerStatus.idle;
  }

  /// Whether the player has been initialized.
  bool get isInitialized => state.initialized;

  /// Whether the player is ready for normal control.
  bool get isReady => state.ready;

  /// Whether the player is opening a source.
  bool get isOpening => state.opening;

  /// Whether the player is currently playing.
  bool get isPlaying => state.playing;

  /// Whether playback is paused.
  bool get isPaused => state.paused;

  /// Whether the player is buffering.
  bool get isBuffering => state.buffering;

  /// Whether the player is seeking.
  bool get isSeeking => state.seeking;

  /// Whether the player is stopping.
  bool get isStopping => state.stopping;

  /// Whether playback has stopped.
  bool get isStopped => state.stopped;

  /// Whether playback has completed.
  bool get isCompleted => state.completed;

  /// Whether the player is disposing.
  bool get isDisposing => state.disposing;

  /// Whether the player has been disposed.
  bool get isDisposed => state.disposed;

  /// Whether the player currently has an error.
  bool get hasError => state.hasError;

  /// Whether audio output is available.
  ///
  /// Media capabilities take precedence over media type, while runtime state
  /// is used as the final fallback.
  bool get hasAudio {
    return mediaCapabilities?.hasAudio ?? mediaType?.hasAudio ?? state.audioEnabled;
  }

  /// Whether video output is available.
  ///
  /// Media capabilities take precedence over media type, while runtime state
  /// is used as the final fallback.
  bool get hasVideo {
    return mediaCapabilities?.hasVideo ?? mediaType?.hasVideo ?? state.videoEnabled;
  }

  /// Whether the player is muted.
  bool get isMuted => state.muted;

  /// Whether the current media is audio-only.
  bool get isAudioOnly {
    final currentCapabilities = mediaCapabilities;
    if (currentCapabilities != null) {
      return currentCapabilities.isAudioOnly;
    }

    final currentType = mediaType;
    if (currentType != null) {
      return currentType.isAudioOnly;
    }

    return hasAudio && !hasVideo;
  }

  /// Whether the current media is video-only.
  bool get isVideoOnly {
    final currentCapabilities = mediaCapabilities;
    if (currentCapabilities != null) {
      return currentCapabilities.isVideoOnly;
    }

    final currentType = mediaType;
    if (currentType != null) {
      return currentType.isVideoOnly;
    }

    return hasVideo && !hasAudio;
  }

  /// Whether the current media contains both audio and video.
  bool get isAudioVideo {
    final currentCapabilities = mediaCapabilities;
    if (currentCapabilities != null) {
      return currentCapabilities.isAudioVideo;
    }

    final currentType = mediaType;
    if (currentType != null) {
      return currentType.isAudioVideo;
    }

    return hasAudio && hasVideo;
  }

  /// Whether a video renderer is required.
  bool get requiresVideoRenderer {
    return mediaCapabilities?.requiresVideoRenderer ?? mediaType?.requiresVideoRenderer ?? hasVideo;
  }

  /// Whether any media output is available.
  bool get hasAnyMedia => hasAudio || hasVideo;

  /// Whether normal player controls are currently allowed.
  bool get canControl => state.canControl;

  /// Whether playback can currently be started.
  ///
  /// Both runtime state and the presence of a source are required.
  bool get canPlay => state.canPlay && hasSource;

  /// Whether playback can currently be paused.
  bool get canPause => state.canPause;

  /// Whether seeking is currently supported.
  ///
  /// The player implementation must support seeking and the current media
  /// must not explicitly report seeking as unsupported.
  bool get canSeek {
    return capabilities.seek && (mediaCapabilities?.supportsSeeking ?? true);
  }

  /// Whether recovery is currently allowed by configuration.
  ///
  /// Recovery execution belongs to the recovery layer.
  bool get canRecover => options.canRecover;

  /// Whether fallback is currently allowed by configuration.
  ///
  /// Fallback execution belongs to the fallback layer.
  bool get canFallback => options.canFallback;

  /// Returns a copy with the supplied values.
  ///
  /// Nullable fields use explicit [withoutSession], [withoutRequest],
  /// [withoutGeneration], [withoutSource], [withoutMediaType],
  /// [withoutMediaCapabilities], and [withoutMetrics] methods when they need
  /// to be removed.
  ///
  /// A null passed to [copyWith] retains the existing value.
  PlayerSnapshot copyWith({
    PlayerId? playerId,
    SessionId? sessionId,
    RequestId? requestId,
    GenerationId? generationId,
    SourceId? sourceId,
    PlayerMediaType? mediaType,
    MediaCapabilities? mediaCapabilities,
    PlayerCoreState? state,
    PlayerOptions? options,
    PlayerCapabilities? capabilities,
    PlayerMetrics? metrics,
    DateTime? timestamp,
  }) {
    return PlayerSnapshot(
      playerId: playerId ?? this.playerId,
      sessionId: sessionId ?? this.sessionId,
      requestId: requestId ?? this.requestId,
      generationId: generationId ?? this.generationId,
      sourceId: sourceId ?? this.sourceId,
      mediaType: mediaType ?? this.mediaType,
      mediaCapabilities: mediaCapabilities ?? this.mediaCapabilities,
      state: state ?? this.state,
      options: options ?? this.options,
      capabilities: capabilities ?? this.capabilities,
      metrics: metrics ?? this.metrics,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Returns a snapshot with a new session association.
  PlayerSnapshot withSession(SessionId value) {
    return copyWith(sessionId: value);
  }

  /// Returns a snapshot without a session association.
  PlayerSnapshot withoutSession() {
    return PlayerSnapshot(
      playerId: playerId,
      requestId: requestId,
      generationId: generationId,
      sourceId: sourceId,
      mediaType: mediaType,
      mediaCapabilities: mediaCapabilities,
      state: state,
      options: options,
      capabilities: capabilities,
      metrics: metrics,
      timestamp: timestamp,
    );
  }

  /// Returns a snapshot with a new request association.
  PlayerSnapshot withRequest(RequestId value) {
    return copyWith(requestId: value);
  }

  /// Returns a snapshot without a request association.
  PlayerSnapshot withoutRequest() {
    return PlayerSnapshot(
      playerId: playerId,
      sessionId: sessionId,
      generationId: generationId,
      sourceId: sourceId,
      mediaType: mediaType,
      mediaCapabilities: mediaCapabilities,
      state: state,
      options: options,
      capabilities: capabilities,
      metrics: metrics,
      timestamp: timestamp,
    );
  }

  /// Returns a snapshot with a new generation association.
  PlayerSnapshot withGeneration(GenerationId value) {
    return copyWith(generationId: value);
  }

  /// Returns a snapshot without a generation association.
  PlayerSnapshot withoutGeneration() {
    return PlayerSnapshot(
      playerId: playerId,
      sessionId: sessionId,
      requestId: requestId,
      sourceId: sourceId,
      mediaType: mediaType,
      mediaCapabilities: mediaCapabilities,
      state: state,
      options: options,
      capabilities: capabilities,
      metrics: metrics,
      timestamp: timestamp,
    );
  }

  /// Returns a snapshot with a new source association.
  PlayerSnapshot withSource(SourceId value) {
    return copyWith(sourceId: value);
  }

  /// Returns a snapshot without a source association.
  ///
  /// Source-dependent media information is cleared together with the source
  /// association.
  PlayerSnapshot withoutSource() {
    return PlayerSnapshot(
      playerId: playerId,
      sessionId: sessionId,
      requestId: requestId,
      generationId: generationId,
      state: state.withSource(value: false),
      options: options.withoutSource(),
      capabilities: capabilities,
      metrics: metrics,
      timestamp: timestamp,
    );
  }

  /// Returns a snapshot with the supplied media type.
  PlayerSnapshot withMediaType(PlayerMediaType value) {
    return copyWith(mediaType: value);
  }

  /// Returns a snapshot without media type information.
  PlayerSnapshot withoutMediaType() {
    return PlayerSnapshot(
      playerId: playerId,
      sessionId: sessionId,
      requestId: requestId,
      generationId: generationId,
      sourceId: sourceId,
      mediaCapabilities: mediaCapabilities,
      state: state,
      options: options,
      capabilities: capabilities,
      metrics: metrics,
      timestamp: timestamp,
    );
  }

  /// Returns a snapshot with the supplied media capabilities.
  PlayerSnapshot withMediaCapabilities(MediaCapabilities value) {
    return copyWith(mediaCapabilities: value);
  }

  /// Returns a snapshot without media capability information.
  PlayerSnapshot withoutMediaCapabilities() {
    return PlayerSnapshot(
      playerId: playerId,
      sessionId: sessionId,
      requestId: requestId,
      generationId: generationId,
      sourceId: sourceId,
      mediaType: mediaType,
      state: state,
      options: options,
      capabilities: capabilities,
      metrics: metrics,
      timestamp: timestamp,
    );
  }

  /// Returns a snapshot with the supplied player state.
  PlayerSnapshot withState(PlayerCoreState value) {
    return copyWith(state: value);
  }

  /// Returns a snapshot with the supplied player options.
  PlayerSnapshot withOptions(PlayerOptions value) {
    return copyWith(options: value);
  }

  /// Returns a snapshot with the supplied player capabilities.
  PlayerSnapshot withCapabilities(PlayerCapabilities value) {
    return copyWith(capabilities: value);
  }

  /// Returns a snapshot with the supplied metrics.
  PlayerSnapshot withMetrics(PlayerMetrics value) {
    return copyWith(metrics: value);
  }

  /// Returns a snapshot without runtime metrics.
  PlayerSnapshot withoutMetrics() {
    return PlayerSnapshot(
      playerId: playerId,
      sessionId: sessionId,
      requestId: requestId,
      generationId: generationId,
      sourceId: sourceId,
      mediaType: mediaType,
      mediaCapabilities: mediaCapabilities,
      state: state,
      options: options,
      capabilities: capabilities,
      timestamp: timestamp,
    );
  }

  /// Returns a snapshot with a new timestamp.
  PlayerSnapshot withTimestamp(DateTime value) {
    return copyWith(timestamp: value);
  }

  /// Returns an idle snapshot while preserving player identity and
  /// configuration.
  PlayerSnapshot asIdle() {
    return copyWith(state: PlayerCoreState.idle);
  }

  /// Returns a disposed snapshot.
  ///
  /// PlayerIdentity identity and runtime associations are preserved so observers can
  /// associate the terminal state with the original player generation.
  PlayerSnapshot asDisposed() {
    return PlayerSnapshot(
      playerId: playerId,
      sessionId: sessionId,
      requestId: requestId,
      generationId: generationId,
      state: state.disposedState(),
      options: options,
      capabilities: capabilities,
      metrics: metrics,
      timestamp: timestamp,
    );
  }

  /// Returns whether both snapshots belong to the same player.
  bool isSamePlayer(PlayerSnapshot other) {
    return playerId == other.playerId;
  }

  /// Returns whether both snapshots belong to the same session.
  bool isSameSession(PlayerSnapshot other) {
    return sessionId != null && other.sessionId != null && sessionId == other.sessionId;
  }

  /// Returns whether both snapshots belong to the same source.
  bool isSameSource(PlayerSnapshot other) {
    return sourceId != null && other.sourceId != null && sourceId == other.sourceId;
  }

  /// Returns whether both snapshots belong to the same generation.
  bool isSameGeneration(PlayerSnapshot other) {
    return generationId != null && other.generationId != null && generationId == other.generationId;
  }

  /// Returns whether both snapshots have the same semantic playback state.
  bool isSamePlaybackState(PlayerSnapshot other) {
    return state.playback == other.state.playback;
  }

  /// Returns whether both snapshots describe the same media capabilities.
  bool isSameMedia(PlayerSnapshot other) {
    return mediaType == other.mediaType && mediaCapabilities == other.mediaCapabilities;
  }

  /// Returns whether this snapshot is newer than [other].
  ///
  /// Snapshots without timestamps are considered incomparable.
  bool isNewerThan(PlayerSnapshot other) {
    final current = timestamp;
    final previous = other.timestamp;

    if (current == null || previous == null) {
      return false;
    }

    return current.isAfter(previous);
  }

  /// Returns whether this snapshot is older than [other].
  ///
  /// Snapshots without timestamps are considered incomparable.
  bool isOlderThan(PlayerSnapshot other) {
    final current = timestamp;
    final previous = other.timestamp;

    if (current == null || previous == null) {
      return false;
    }

    return current.isBefore(previous);
  }

  @override
  List<Object?> get props => <Object?>[
    playerId,
    sessionId,
    requestId,
    generationId,
    sourceId,
    mediaType,
    mediaCapabilities,
    state,
    options,
    capabilities,
    metrics,
    timestamp,
  ];

  @override
  String toString() {
    return 'PlayerSnapshot('
        'playerId: $playerId, '
        'sessionId: $sessionId, '
        'requestId: $requestId, '
        'generationId: $generationId, '
        'sourceId: $sourceId, '
        'playback: ${state.playback}, '
        'lifecycle: ${state.lifecycle}, '
        'hasError: $hasError, '
        'isDisposed: $isDisposed'
        ')';
  }
}
