import 'package:equatable/equatable.dart';
import 'package:media_core/error/error_classifier.dart';
import 'package:media_core/error/player_error_category.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/source_id.dart';

/// Represents an immutable player error snapshot.
///
/// [PlayerError] contains the error code, message, optional category,
/// underlying cause, stack trace, player context, and diagnostic metadata.
///
/// The error category is normally resolved by [ErrorClassifier] unless
/// an explicit [category] is provided.
final class PlayerError extends Equatable {
  /// Creates an immutable player error.
  const PlayerError({
    required this.code,
    required this.message,
    this.category,
    this.cause,
    this.stackTrace,
    this.playerId,
    this.sessionId,
    this.sourceId,
    this.requestId,
    this.generationId,
    this.timestamp,
    this.metadata = const <String, Object?>{},
  });

  /// Stable error code.
  final PlayerErrorCode code;

  /// Human-readable error message.
  final String message;

  /// Explicitly assigned error category.
  ///
  /// When null, [effectiveCategory] is resolved by [ErrorClassifier].
  final PlayerErrorCategory? category;

  /// Original underlying error or exception.
  final Object? cause;

  /// Stack trace associated with the error.
  final StackTrace? stackTrace;

  /// PlayerIdentity associated with this error.
  final PlayerId? playerId;

  /// Session associated with this error.
  final SessionId? sessionId;

  /// Source associated with this error.
  final SourceId? sourceId;

  /// Request associated with this error.
  final RequestId? requestId;

  /// Generation associated with this error.
  ///
  /// This is useful for rejecting stale asynchronous results.
  final GenerationId? generationId;

  /// Time when the error was created or observed.
  final DateTime? timestamp;

  /// Additional diagnostic metadata.
  final Map<String, Object?> metadata;

  /// Returns the effective error category.
  ///
  /// An explicitly provided category takes precedence over automatic
  /// classification.
  PlayerErrorCategory get effectiveCategory {
    return category ?? ErrorClassifier.classify(code);
  }

  /// Returns whether an explicit category is available.
  bool get hasCategory => category != null;

  /// Returns whether an underlying cause is available.
  bool get hasCause => cause != null;

  /// Returns whether a stack trace is available.
  bool get hasStackTrace => stackTrace != null;

  /// Returns whether a player context is available.
  bool get hasPlayer => playerId != null;

  /// Returns whether a session context is available.
  bool get hasSession => sessionId != null;

  /// Returns whether a source context is available.
  bool get hasSource => sourceId != null;

  /// Returns whether a request context is available.
  bool get hasRequest => requestId != null;

  /// Returns whether a generation context is available.
  bool get hasGeneration => generationId != null;

  /// Returns whether a timestamp is available.
  bool get hasTimestamp => timestamp != null;

  /// Returns whether diagnostic metadata is available.
  bool get hasMetadata => metadata.isNotEmpty;

  /// Returns whether any contextual information is attached.
  bool get hasContext {
    return hasPlayer || hasSession || hasSource || hasRequest || hasGeneration || hasTimestamp || hasMetadata;
  }

  /// Returns whether this represents an unknown error.
  bool get isUnknown {
    return code == PlayerErrorCode.unknown || effectiveCategory == PlayerErrorCategory.unknown;
  }

  /// Returns whether this represents a cancellation.
  bool get isCancellation {
    return code.isCancellation || effectiveCategory == PlayerErrorCategory.cancellation;
  }

  /// Returns whether this represents a timeout.
  bool get isTimeout {
    return effectiveCategory == PlayerErrorCategory.timeout;
  }

  /// Returns whether this represents a network-related error.
  bool get isNetworkRelated {
    return code.isNetworkRelated || effectiveCategory == PlayerErrorCategory.network;
  }

  /// Returns whether this represents a source-related error.
  bool get isSourceRelated {
    return code.isSourceRelated || effectiveCategory == PlayerErrorCategory.source;
  }

  /// Returns whether this represents a backend-related error.
  bool get isBackendRelated {
    return code.isBackendRelated || effectiveCategory == PlayerErrorCategory.backend;
  }

  /// Returns whether this represents a playback-related error.
  bool get isPlaybackRelated {
    return code.isPlaybackRelated || effectiveCategory == PlayerErrorCategory.playback;
  }

  /// Returns whether this represents a media pipeline error.
  ///
  /// This includes media, decoder, and demuxer failures.
  bool get isMediaPipelineRelated {
    return code.isMediaPipelineRelated ||
        effectiveCategory == PlayerErrorCategory.media ||
        effectiveCategory == PlayerErrorCategory.decoder ||
        effectiveCategory == PlayerErrorCategory.demuxer;
  }

  /// Returns whether this represents a resource-related error.
  ///
  /// This includes memory, thermal, bandwidth, and concurrency failures.
  bool get isResourceRelated {
    return code.isResourceRelated ||
        effectiveCategory == PlayerErrorCategory.resource ||
        effectiveCategory == PlayerErrorCategory.memory ||
        effectiveCategory == PlayerErrorCategory.thermal ||
        effectiveCategory == PlayerErrorCategory.bandwidth ||
        effectiveCategory == PlayerErrorCategory.concurrency;
  }

  /// Returns whether this represents a presentation-related error.
  ///
  /// This includes renderer and geometry failures.
  bool get isPresentationRelated {
    return code.isPresentationRelated ||
        effectiveCategory == PlayerErrorCategory.presentation ||
        effectiveCategory == PlayerErrorCategory.renderer ||
        effectiveCategory == PlayerErrorCategory.geometry;
  }

  /// Returns whether this error may be recoverable.
  bool get isPotentiallyRecoverable {
    return code.isPotentiallyRecoverable;
  }

  /// Returns a metadata value by key.
  Object? metadataValue(String key) {
    return metadata[key];
  }

  /// Returns a metadata value when it matches [T].
  T? metadataAs<T>(String key) {
    final value = metadata[key];

    if (value is T) {
      return value;
    }

    return null;
  }

  /// Returns whether metadata contains [key].
  bool containsMetadata(String key) {
    return metadata.containsKey(key);
  }

  /// Creates a copy with the supplied values replaced.
  ///
  /// Null values mean that the existing value is retained.
  PlayerError copyWith({
    PlayerErrorCode? code,
    String? message,
    PlayerErrorCategory? category,
    Object? cause,
    StackTrace? stackTrace,
    PlayerId? playerId,
    SessionId? sessionId,
    SourceId? sourceId,
    RequestId? requestId,
    GenerationId? generationId,
    DateTime? timestamp,
    Map<String, Object?>? metadata,
  }) {
    return PlayerError(
      code: code ?? this.code,
      message: message ?? this.message,
      category: category ?? this.category,
      cause: cause ?? this.cause,
      stackTrace: stackTrace ?? this.stackTrace,
      playerId: playerId ?? this.playerId,
      sessionId: sessionId ?? this.sessionId,
      sourceId: sourceId ?? this.sourceId,
      requestId: requestId ?? this.requestId,
      generationId: generationId ?? this.generationId,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Creates a copy with a different error code.
  PlayerError withCode(PlayerErrorCode value) {
    return copyWith(code: value);
  }

  /// Creates a copy with a different message.
  PlayerError withMessage(String value) {
    return copyWith(message: value);
  }

  /// Creates a copy with an explicit category.
  PlayerError withCategory(PlayerErrorCategory value) {
    return copyWith(category: value);
  }

  /// Creates a copy with an underlying cause.
  PlayerError withCause(Object value) {
    return copyWith(cause: value);
  }

  /// Creates a copy with a stack trace.
  PlayerError withStackTrace(StackTrace value) {
    return copyWith(stackTrace: value);
  }

  /// Creates a copy associated with [value].
  PlayerError withPlayer(PlayerId value) {
    return copyWith(playerId: value);
  }

  /// Creates a copy associated with [value].
  PlayerError withSession(SessionId value) {
    return copyWith(sessionId: value);
  }

  /// Creates a copy associated with [value].
  PlayerError withSource(SourceId value) {
    return copyWith(sourceId: value);
  }

  /// Creates a copy associated with [value].
  PlayerError withRequest(RequestId value) {
    return copyWith(requestId: value);
  }

  /// Creates a copy associated with [value].
  PlayerError withGeneration(GenerationId value) {
    return copyWith(generationId: value);
  }

  /// Creates a copy with a timestamp.
  PlayerError withTimestamp(DateTime value) {
    return copyWith(timestamp: value);
  }

  /// Creates a copy with one metadata entry added or replaced.
  PlayerError withMetadata(String key, Object? value) {
    return copyWith(metadata: <String, Object?>{...metadata, key: value});
  }

  /// Creates a copy with multiple metadata entries added or replaced.
  PlayerError withMetadataMap(Map<String, Object?> values) {
    if (values.isEmpty) {
      return this;
    }

    return copyWith(metadata: <String, Object?>{...metadata, ...values});
  }

  /// Creates a copy without the explicit category.
  PlayerError withoutCategory() {
    return PlayerError(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      playerId: playerId,
      sessionId: sessionId,
      sourceId: sourceId,
      requestId: requestId,
      generationId: generationId,
      timestamp: timestamp,
      metadata: metadata,
    );
  }

  /// Creates a copy without the underlying cause.
  PlayerError withoutCause() {
    return PlayerError(
      code: code,
      message: message,
      category: category,
      stackTrace: stackTrace,
      playerId: playerId,
      sessionId: sessionId,
      sourceId: sourceId,
      requestId: requestId,
      generationId: generationId,
      timestamp: timestamp,
      metadata: metadata,
    );
  }

  /// Creates a copy without the stack trace.
  PlayerError withoutStackTrace() {
    return PlayerError(
      code: code,
      message: message,
      category: category,
      cause: cause,
      playerId: playerId,
      sessionId: sessionId,
      sourceId: sourceId,
      requestId: requestId,
      generationId: generationId,
      timestamp: timestamp,
      metadata: metadata,
    );
  }

  /// Creates a copy without the player association.
  PlayerError withoutPlayer() {
    return PlayerError(
      code: code,
      message: message,
      category: category,
      cause: cause,
      stackTrace: stackTrace,
      sessionId: sessionId,
      sourceId: sourceId,
      requestId: requestId,
      generationId: generationId,
      timestamp: timestamp,
      metadata: metadata,
    );
  }

  /// Creates a copy without the session association.
  PlayerError withoutSession() {
    return PlayerError(
      code: code,
      message: message,
      category: category,
      cause: cause,
      stackTrace: stackTrace,
      playerId: playerId,
      sourceId: sourceId,
      requestId: requestId,
      generationId: generationId,
      timestamp: timestamp,
      metadata: metadata,
    );
  }

  /// Creates a copy without the source association.
  PlayerError withoutSource() {
    return PlayerError(
      code: code,
      message: message,
      category: category,
      cause: cause,
      stackTrace: stackTrace,
      playerId: playerId,
      sessionId: sessionId,
      requestId: requestId,
      generationId: generationId,
      timestamp: timestamp,
      metadata: metadata,
    );
  }

  /// Creates a copy without the request association.
  PlayerError withoutRequest() {
    return PlayerError(
      code: code,
      message: message,
      category: category,
      cause: cause,
      stackTrace: stackTrace,
      playerId: playerId,
      sessionId: sessionId,
      sourceId: sourceId,
      generationId: generationId,
      timestamp: timestamp,
      metadata: metadata,
    );
  }

  /// Creates a copy without the generation association.
  PlayerError withoutGeneration() {
    return PlayerError(
      code: code,
      message: message,
      category: category,
      cause: cause,
      stackTrace: stackTrace,
      playerId: playerId,
      sessionId: sessionId,
      sourceId: sourceId,
      requestId: requestId,
      timestamp: timestamp,
      metadata: metadata,
    );
  }

  /// Creates a copy without one metadata entry.
  PlayerError withoutMetadata(String key) {
    if (!metadata.containsKey(key)) {
      return this;
    }

    final updated = <String, Object?>{...metadata}..remove(key);

    return copyWith(metadata: updated);
  }

  /// Creates a copy without any metadata.
  PlayerError clearMetadata() {
    if (metadata.isEmpty) {
      return this;
    }

    return copyWith(metadata: const <String, Object?>{});
  }

  /// Returns whether both errors use the same error code.
  bool isSameCode(PlayerError other) {
    return code == other.code;
  }

  /// Returns whether both errors resolve to the same category.
  bool isSameCategory(PlayerError other) {
    return effectiveCategory == other.effectiveCategory;
  }

  /// Returns whether both errors belong to the same player.
  bool isSamePlayer(PlayerError other) {
    return playerId != null && other.playerId != null && playerId == other.playerId;
  }

  /// Returns whether both errors belong to the same session.
  bool isSameSession(PlayerError other) {
    return sessionId != null && other.sessionId != null && sessionId == other.sessionId;
  }

  /// Returns whether both errors belong to the same source.
  bool isSameSource(PlayerError other) {
    return sourceId != null && other.sourceId != null && sourceId == other.sourceId;
  }

  /// Returns whether both errors belong to the same request.
  bool isSameRequest(PlayerError other) {
    return requestId != null && other.requestId != null && requestId == other.requestId;
  }

  /// Returns whether both errors belong to the same generation.
  bool isSameGeneration(PlayerError other) {
    return generationId != null && other.generationId != null && generationId == other.generationId;
  }

  /// Returns a compact diagnostic representation of the error.
  String get diagnosticMessage {
    final buffer = StringBuffer()..write('[$code] $message');

    if (category != null) {
      buffer.write(' category=$category');
    }

    if (playerId != null) {
      buffer.write(' playerId=$playerId');
    }

    if (sessionId != null) {
      buffer.write(' sessionId=$sessionId');
    }

    if (sourceId != null) {
      buffer.write(' sourceId=$sourceId');
    }

    if (requestId != null) {
      buffer.write(' requestId=$requestId');
    }

    if (generationId != null) {
      buffer.write(' generationId=$generationId');
    }

    if (timestamp != null) {
      buffer.write(' timestamp=$timestamp');
    }

    return buffer.toString();
  }

  @override
  List<Object?> get props => <Object?>[
    code,
    message,
    category,
    cause,
    stackTrace,
    playerId,
    sessionId,
    sourceId,
    requestId,
    generationId,
    timestamp,
    metadata,
  ];

  @override
  String toString() {
    return 'PlayerError('
        'code: $code, '
        'message: $message, '
        'category: $category, '
        'effectiveCategory: $effectiveCategory, '
        'cause: $cause, '
        'playerId: $playerId, '
        'sessionId: $sessionId, '
        'sourceId: $sourceId, '
        'requestId: $requestId, '
        'generationId: $generationId, '
        'timestamp: $timestamp, '
        'metadata: $metadata'
        ')';
  }
}
