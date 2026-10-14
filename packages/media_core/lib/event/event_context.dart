import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/slot_id.dart';
import 'package:media_core/identity/source_id.dart';

/// Context associated with a player event.
///
/// Context carries correlation information without forcing every event to
/// define the same set of fields.
///
/// Event context is metadata; it does not contain event-specific payload.
final class EventContext extends Equatable {
  /// Builds a context from the correlation identifiers known at emit time.
  ///
  /// [timestamp] defaults to the current time (`clock.now()`) so callers do
  /// not have to supply one unless they are reconstructing a past event.
  EventContext({
    this.playerId,
    this.sessionId,
    this.slotId,
    this.sourceId,
    this.operationId,
    this.requestId,
    this.generationId,
    this.metadata = const <String, Object?>{},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? clock.now();

  /// Player the event is attributed to, when it is scoped to one player.
  final PlayerId? playerId;

  /// Playback session the event belongs to, used to discard late events that
  /// arrive after their session has already ended.
  final SessionId? sessionId;

  /// Pool slot the event came from, distinguishing hosts that share a player.
  final SlotId? slotId;

  /// Media source the event describes.
  final SourceId? sourceId;

  /// Logical operation the event is part of, correlating a command with the
  /// events it produced.
  final OperationId? operationId;

  /// Discrete request that triggered the event, when it was request-driven.
  final RequestId? requestId;

  /// Generation of the resource the event refers to, letting consumers drop
  /// events emitted by a replaced instance.
  final GenerationId? generationId;

  /// Free-form, event-specific values that do not warrant a dedicated field.
  final Map<String, Object?> metadata;

  /// Instant the event was created.
  final DateTime timestamp;

  /// Whether the context is scoped to a specific player.
  bool get hasPlayer => playerId != null;

  /// Whether the context belongs to a specific session.
  bool get hasSession => sessionId != null;

  /// Whether the context names a specific pool slot.
  bool get hasSlot => slotId != null;

  /// Whether the context names a specific source.
  bool get hasSource => sourceId != null;

  /// Whether the context is tied to a logical operation.
  bool get hasOperation => operationId != null;

  /// Whether the context is tied to a discrete request.
  bool get hasRequest => requestId != null;

  /// Whether the context carries a resource generation.
  bool get hasGeneration => generationId != null;

  /// Whether any free-form metadata is attached.
  bool get hasMetadata => metadata.isNotEmpty;

  /// Returns a copy with the supplied fields replaced; omitted fields keep
  /// their current values.
  EventContext copyWith({
    PlayerId? playerId,
    SessionId? sessionId,
    SlotId? slotId,
    SourceId? sourceId,
    OperationId? operationId,
    RequestId? requestId,
    GenerationId? generationId,
    Map<String, Object?>? metadata,
    DateTime? timestamp,
  }) {
    return EventContext(
      playerId: playerId ?? this.playerId,
      sessionId: sessionId ?? this.sessionId,
      slotId: slotId ?? this.slotId,
      sourceId: sourceId ?? this.sourceId,
      operationId: operationId ?? this.operationId,
      requestId: requestId ?? this.requestId,
      generationId: generationId ?? this.generationId,
      metadata: metadata ?? this.metadata,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Serialises the correlation ids, metadata and timestamp into a string-keyed
  /// map for logging or transport; ids are rendered via `toString` and the
  /// timestamp as ISO-8601.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'playerId': playerId?.toString(),
      'sessionId': sessionId?.toString(),
      'slotId': slotId?.toString(),
      'sourceId': sourceId?.toString(),
      'operationId': operationId?.toString(),
      'requestId': requestId?.toString(),
      'generationId': generationId?.toString(),
      'metadata': metadata,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => <Object?>[
    playerId,
    sessionId,
    slotId,
    sourceId,
    operationId,
    requestId,
    generationId,
    metadata,
    timestamp,
  ];

  @override
  String toString() {
    return 'EventContext('
        'playerId: $playerId, '
        'sessionId: $sessionId, '
        'slotId: $slotId, '
        'sourceId: $sourceId, '
        'operationId: $operationId, '
        'requestId: $requestId, '
        'generationId: $generationId, '
        'timestamp: $timestamp'
        ')';
  }
}
