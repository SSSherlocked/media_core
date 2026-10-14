import 'package:equatable/equatable.dart';
import 'package:media_core/error/error_context.dart' show ErrorContext;
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/slot_id.dart';
import 'package:media_core/identity/source_id.dart';

/// Provides contextual information associated with an operation.
///
/// [OperationContext] contains business and execution context that may be
/// required while performing an operation.
///
/// It is intentionally separate from [ErrorContext]:
///
/// ```text
/// OperationContext
///     ↓
/// describes operation input/execution context
///
/// ErrorContext
///     ↓
/// describes diagnostic/error context
/// ```
///
/// This class does not contain operation lifecycle state, timeout policy,
/// cancellation state, retry policy, or error information.
///
/// The object is immutable. Metadata and parameters are copied and exposed
/// through unmodifiable views.
final class OperationContext extends Equatable {
  /// Creates an operation context.
  OperationContext({
    this.playerId,
    this.sessionId,
    this.slotId,
    this.sourceId,
    this.requestId,
    this.operationId,
    this.generationId,
    this.lineId,
    this.quality,
    this.uri,
    this.platform,
    this.backend,
    this.adapter,
    this.description,
    this.reason,
    Map<String, Object?> parameters = const <String, Object?>{},
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : parameters = Map<String, Object?>.unmodifiable(parameters),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  /// Creates an [OperationContext] from JSON.
  factory OperationContext.fromJson(Map<String, dynamic> json) {
    return OperationContext(
      playerId: _readPlayerId(json['playerId']),
      sessionId: _readSessionId(json['sessionId']),
      slotId: _readSlotId(json['slotId']),
      sourceId: _readSourceId(json['sourceId']),
      requestId: _readRequestId(json['requestId']),
      operationId: _readOperationId(json['operationId']),
      generationId: _readGenerationId(json['generationId']),
      lineId: _readNullableString(json['lineId'], 'lineId'),
      quality: _readNullableString(json['quality'], 'quality'),
      uri: _readNullableString(json['uri'], 'uri'),
      platform: _readNullableString(json['platform'], 'platform'),
      backend: _readNullableString(json['backend'], 'backend'),
      adapter: _readNullableString(json['adapter'], 'adapter'),
      description: _readNullableString(json['description'], 'description'),
      reason: _readNullableString(json['reason'], 'reason'),
      parameters: _readMap(json['parameters'], 'parameters'),
      metadata: _readMap(json['metadata'], 'metadata'),
    );
  }

  /// PlayerIdentity associated with the operation.
  final PlayerId? playerId;

  /// Session associated with the operation.
  final SessionId? sessionId;

  /// Slot associated with the operation.
  final SlotId? slotId;

  /// Source associated with the operation.
  final SourceId? sourceId;

  /// Request associated with the operation.
  final RequestId? requestId;

  /// Operation identity associated with this context.
  final OperationId? operationId;

  /// Generation associated with the operation.
  ///
  /// Useful for detecting stale or superseded operations.
  final GenerationId? generationId;

  /// Optional source line identifier.
  final String? lineId;

  /// Optional requested quality.
  final String? quality;

  /// Optional source URI.
  final String? uri;

  /// Platform associated with the operation.
  final String? platform;

  /// Backend associated with the operation.
  final String? backend;

  /// Adapter associated with the operation.
  final String? adapter;

  /// Human-readable operation description.
  final String? description;

  /// Business reason for creating the operation.
  final String? reason;

  /// Parameters consumed by the operation.
  ///
  /// Parameters describe operation inputs rather than diagnostic metadata.
  final Map<String, Object?> parameters;

  /// Additional operation metadata.
  ///
  /// Metadata is intentionally generic and should not be used as a replacement
  /// for strongly typed fields.
  final Map<String, Object?> metadata;

  // ---------------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------------

  /// Converts this context to JSON.
  ///
  /// Nullable fields are explicitly included as `null` so the serialized
  /// structure remains stable.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'playerId': playerId?.toJson(),
      'sessionId': sessionId?.toJson(),
      'slotId': slotId?.toJson(),
      'sourceId': sourceId?.toJson(),
      'requestId': requestId?.toJson(),
      'operationId': operationId?.toJson(),
      'generationId': generationId?.toJson(),
      'lineId': lineId,
      'quality': quality,
      'uri': uri,
      'platform': platform,
      'backend': backend,
      'adapter': adapter,
      'description': description,
      'reason': reason,
      'parameters': Map<String, Object?>.from(parameters),
      'metadata': Map<String, Object?>.from(metadata),
    };
  }

  // ---------------------------------------------------------------------------
  // Presence
  // ---------------------------------------------------------------------------

  /// Whether a player identity is present.
  bool get hasPlayerId => playerId != null;

  /// Whether a session identity is present.
  bool get hasSessionId => sessionId != null;

  /// Whether a slot identity is present.
  bool get hasSlotId => slotId != null;

  /// Whether a source identity is present.
  bool get hasSourceId => sourceId != null;

  /// Whether a request identity is present.
  bool get hasRequestId => requestId != null;

  /// Whether an operation identity is present.
  bool get hasOperationId => operationId != null;

  /// Whether a generation identity is present.
  bool get hasGenerationId => generationId != null;

  /// Whether a non-blank line identifier is present.
  bool get hasLineId => _hasText(lineId);

  /// Whether a non-blank quality value is present.
  bool get hasQuality => _hasText(quality);

  /// Whether a non-blank source URI is present.
  bool get hasUri => _hasText(uri);

  /// Whether a non-blank platform name is present.
  bool get hasPlatform => _hasText(platform);

  /// Whether a non-blank backend name is present.
  bool get hasBackend => _hasText(backend);

  /// Whether a non-blank adapter name is present.
  bool get hasAdapter => _hasText(adapter);

  /// Whether a non-blank description is present.
  bool get hasDescription => _hasText(description);

  /// Whether a non-blank business reason is present.
  bool get hasReason => _hasText(reason);

  /// Whether any operation parameters are attached.
  bool get hasParameters => parameters.isNotEmpty;

  /// Whether any metadata entries are attached.
  bool get hasMetadata => metadata.isNotEmpty;

  /// Whether this context contains no information.
  bool get isEmpty {
    return !hasPlayerId &&
        !hasSessionId &&
        !hasSlotId &&
        !hasSourceId &&
        !hasRequestId &&
        !hasOperationId &&
        !hasGenerationId &&
        !hasLineId &&
        !hasQuality &&
        !hasUri &&
        !hasPlatform &&
        !hasBackend &&
        !hasAdapter &&
        !hasDescription &&
        !hasReason &&
        !hasParameters &&
        !hasMetadata;
  }

  /// Whether this context contains any information.
  bool get isNotEmpty => !isEmpty;

  // ---------------------------------------------------------------------------
  // Parameter helpers
  // ---------------------------------------------------------------------------

  /// Returns an unmodifiable view of operation parameters.
  Map<String, Object?> get parametersView => parameters;

  /// Returns whether [key] exists in operation parameters.
  bool containsParameter(String key) {
    return parameters.containsKey(key);
  }

  /// Returns a parameter value.
  Object? parameterValue(String key) {
    return parameters[key];
  }

  /// Returns a typed parameter value.
  T? parameterAs<T>(String key) {
    final value = parameters[key];

    if (value is T) {
      return value;
    }

    return null;
  }

  /// Adds or replaces one operation parameter.
  OperationContext withParameter(String key, Object? value) {
    _requireKey(key, 'Parameter key');

    final next = <String, Object?>{...parameters, key: value};

    return copyWith(parameters: next);
  }

  /// Adds multiple operation parameters.
  OperationContext withParameters(Map<String, Object?> values) {
    if (values.isEmpty) {
      return this;
    }

    final next = <String, Object?>{...parameters, ...values};

    return copyWith(parameters: next);
  }

  /// Removes an operation parameter.
  OperationContext withoutParameter(String key) {
    if (!parameters.containsKey(key)) {
      return this;
    }

    final next = <String, Object?>{...parameters}..remove(key);

    return copyWith(parameters: next);
  }

  /// Removes all operation parameters.
  OperationContext clearParameters() {
    if (parameters.isEmpty) {
      return this;
    }

    return copyWith(parameters: const <String, Object?>{});
  }

  // ---------------------------------------------------------------------------
  // Metadata helpers
  // ---------------------------------------------------------------------------

  /// Returns an unmodifiable view of metadata.
  Map<String, Object?> get metadataView => metadata;

  /// Returns whether [key] exists in metadata.
  bool containsMetadata(String key) {
    return metadata.containsKey(key);
  }

  /// Returns a metadata value.
  Object? metadataValue(String key) {
    return metadata[key];
  }

  /// Returns a typed metadata value.
  T? metadataAs<T>(String key) {
    final value = metadata[key];

    if (value is T) {
      return value;
    }

    return null;
  }

  /// Adds or replaces one metadata value.
  OperationContext withMetadata(String key, Object? value) {
    _requireKey(key, 'Metadata key');

    final next = <String, Object?>{...metadata, key: value};

    return copyWith(metadata: next);
  }

  /// Adds multiple metadata values.
  OperationContext withMetadataMap(Map<String, Object?> values) {
    if (values.isEmpty) {
      return this;
    }

    final next = <String, Object?>{...metadata, ...values};

    return copyWith(metadata: next);
  }

  /// Removes one metadata value.
  OperationContext withoutMetadata(String key) {
    if (!metadata.containsKey(key)) {
      return this;
    }

    final next = <String, Object?>{...metadata}..remove(key);

    return copyWith(metadata: next);
  }

  /// Removes all metadata.
  OperationContext clearMetadata() {
    if (metadata.isEmpty) {
      return this;
    }

    return copyWith(metadata: const <String, Object?>{});
  }

  // ---------------------------------------------------------------------------
  // Identity helpers
  // ---------------------------------------------------------------------------

  /// Returns a copy with the named fields cleared.
  ///
  /// [copyWith] cannot express "no value": a null argument means "keep what is
  /// there", which is what a caller building a context wants and is exactly what
  /// made the `withoutX()` helpers below return an unchanged copy. Clearing is
  /// therefore a separate question, asked field by field so that a caller names
  /// the one it means to drop and never has to repeat the fourteen it does not.
  OperationContext cleared({
    bool playerId = false,
    bool sessionId = false,
    bool slotId = false,
    bool sourceId = false,
    bool requestId = false,
    bool operationId = false,
    bool generationId = false,
    bool lineId = false,
    bool quality = false,
    bool uri = false,
    bool platform = false,
    bool backend = false,
    bool adapter = false,
    bool description = false,
    bool reason = false,
  }) {
    return OperationContext(
      playerId: playerId ? null : this.playerId,
      sessionId: sessionId ? null : this.sessionId,
      slotId: slotId ? null : this.slotId,
      sourceId: sourceId ? null : this.sourceId,
      requestId: requestId ? null : this.requestId,
      operationId: operationId ? null : this.operationId,
      generationId: generationId ? null : this.generationId,
      lineId: lineId ? null : this.lineId,
      quality: quality ? null : this.quality,
      uri: uri ? null : this.uri,
      platform: platform ? null : this.platform,
      backend: backend ? null : this.backend,
      adapter: adapter ? null : this.adapter,
      description: description ? null : this.description,
      reason: reason ? null : this.reason,
      parameters: parameters,
      metadata: metadata,
    );
  }

  /// Returns a copy carrying [value] as the player identity.
  OperationContext withPlayerId(PlayerId value) {
    return copyWith(playerId: value);
  }

  /// Returns a copy without the player identity.
  OperationContext withoutPlayerId() => cleared(playerId: true);

  /// Returns a copy carrying [value] as the session identity.
  OperationContext withSessionId(SessionId value) {
    return copyWith(sessionId: value);
  }

  /// Returns a copy without the session identity.
  OperationContext withoutSessionId() => cleared(sessionId: true);

  /// Returns a copy carrying [value] as the slot identity.
  OperationContext withSlotId(SlotId value) {
    return copyWith(slotId: value);
  }

  /// Returns a copy without the slot identity.
  OperationContext withoutSlotId() => cleared(slotId: true);

  /// Returns a copy carrying [value] as the source identity.
  OperationContext withSourceId(SourceId value) {
    return copyWith(sourceId: value);
  }

  /// Returns a copy without the source identity.
  OperationContext withoutSourceId() => cleared(sourceId: true);

  /// Returns a copy carrying [value] as the request identity.
  OperationContext withRequestId(RequestId value) {
    return copyWith(requestId: value);
  }

  /// Returns a copy without the request identity.
  OperationContext withoutRequestId() => cleared(requestId: true);

  /// Returns a copy carrying [value] as the operation identity.
  OperationContext withOperationId(OperationId value) {
    return copyWith(operationId: value);
  }

  /// Returns a copy without the operation identity.
  OperationContext withoutOperationId() => cleared(operationId: true);

  /// Returns a copy carrying [value] as the generation identity.
  OperationContext withGenerationId(GenerationId value) {
    return copyWith(generationId: value);
  }

  /// Returns a copy without the generation identity.
  OperationContext withoutGenerationId() => cleared(generationId: true);

  // ---------------------------------------------------------------------------
  // Text helpers
  // ---------------------------------------------------------------------------

  /// Returns a copy carrying [value] as the normalized source line id.
  OperationContext withLineId(String value) {
    return copyWith(lineId: _normalizeText(value));
  }

  /// Returns a copy without the source line id.
  OperationContext withoutLineId() => cleared(lineId: true);

  /// Returns a copy carrying [value] as the normalized requested quality.
  OperationContext withQuality(String value) {
    return copyWith(quality: _normalizeText(value));
  }

  /// Returns a copy without the requested quality.
  OperationContext withoutQuality() => cleared(quality: true);

  /// Returns a copy carrying [value] as the normalized source URI.
  OperationContext withUri(String value) {
    return copyWith(uri: _normalizeText(value));
  }

  /// Returns a copy without the source URI.
  OperationContext withoutUri() => cleared(uri: true);

  /// Returns a copy carrying [value] as the normalized platform name.
  OperationContext withPlatform(String value) {
    return copyWith(platform: _normalizeText(value));
  }

  /// Returns a copy without the platform name.
  OperationContext withoutPlatform() => cleared(platform: true);

  /// Returns a copy carrying [value] as the normalized backend name.
  OperationContext withBackend(String value) {
    return copyWith(backend: _normalizeText(value));
  }

  /// Returns a copy without the backend name.
  OperationContext withoutBackend() => cleared(backend: true);

  /// Returns a copy carrying [value] as the normalized adapter name.
  OperationContext withAdapter(String value) {
    return copyWith(adapter: _normalizeText(value));
  }

  /// Returns a copy without the adapter name.
  OperationContext withoutAdapter() => cleared(adapter: true);

  /// Returns a copy carrying [value] as the normalized description.
  OperationContext withDescription(String value) {
    return copyWith(description: _normalizeText(value));
  }

  /// Returns a copy without the description.
  OperationContext withoutDescription() => cleared(description: true);

  /// Returns a copy carrying [value] as the normalized business reason.
  OperationContext withReason(String value) {
    return copyWith(reason: _normalizeText(value));
  }

  /// Returns a copy without the business reason.
  OperationContext withoutReason() => cleared(reason: true);

  // ---------------------------------------------------------------------------
  // Copy
  // ---------------------------------------------------------------------------

  /// Creates a copy with the supplied values replaced.
  ///
  /// Because nullable fields use `null` as the "keep existing value" marker,
  /// the explicit `withoutX()` methods should be used when a nullable value
  /// needs to be cleared.
  OperationContext copyWith({
    PlayerId? playerId,
    SessionId? sessionId,
    SlotId? slotId,
    SourceId? sourceId,
    RequestId? requestId,
    OperationId? operationId,
    GenerationId? generationId,
    String? lineId,
    String? quality,
    String? uri,
    String? platform,
    String? backend,
    String? adapter,
    String? description,
    String? reason,
    Map<String, Object?>? parameters,
    Map<String, Object?>? metadata,
  }) {
    return OperationContext(
      playerId: playerId ?? this.playerId,
      sessionId: sessionId ?? this.sessionId,
      slotId: slotId ?? this.slotId,
      sourceId: sourceId ?? this.sourceId,
      requestId: requestId ?? this.requestId,
      operationId: operationId ?? this.operationId,
      generationId: generationId ?? this.generationId,
      lineId: lineId ?? this.lineId,
      quality: quality ?? this.quality,
      uri: uri ?? this.uri,
      platform: platform ?? this.platform,
      backend: backend ?? this.backend,
      adapter: adapter ?? this.adapter,
      description: description ?? this.description,
      reason: reason ?? this.reason,
      parameters: parameters ?? this.parameters,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Removes all context information.
  OperationContext clear() {
    return OperationContext();
  }

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  List<Object?> get props => <Object?>[
    playerId,
    sessionId,
    slotId,
    sourceId,
    requestId,
    operationId,
    generationId,
    lineId,
    quality,
    uri,
    platform,
    backend,
    adapter,
    description,
    reason,
    parameters,
    metadata,
  ];

  @override
  String toString() {
    if (isEmpty) {
      return 'OperationContext()';
    }

    final parts = <String>[];

    void addValue(String name, Object? value) {
      if (value != null) {
        parts.add('$name: $value');
      }
    }

    addValue('playerId', playerId);
    addValue('sessionId', sessionId);
    addValue('slotId', slotId);
    addValue('sourceId', sourceId);
    addValue('requestId', requestId);
    addValue('operationId', operationId);
    addValue('generationId', generationId);
    addValue('lineId', lineId);
    addValue('quality', quality);
    addValue('uri', uri);
    addValue('platform', platform);
    addValue('backend', backend);
    addValue('adapter', adapter);
    addValue('description', description);
    addValue('reason', reason);

    if (parameters.isNotEmpty) {
      parts.add('parameters: $parameters');
    }

    if (metadata.isNotEmpty) {
      parts.add('metadata: $metadata');
    }

    return 'OperationContext(${parts.join(', ')})';
  }

  // ---------------------------------------------------------------------------
  // JSON helpers
  // ---------------------------------------------------------------------------

  static PlayerId? _readPlayerId(Object? value) {
    if (value == null) {
      return null;
    }

    return PlayerId.fromJson(value);
  }

  static SessionId? _readSessionId(Object? value) {
    if (value == null) {
      return null;
    }

    return SessionId.fromJson(value);
  }

  static SlotId? _readSlotId(Object? value) {
    if (value == null) {
      return null;
    }

    return SlotId.fromJson(value);
  }

  static SourceId? _readSourceId(Object? value) {
    if (value == null) {
      return null;
    }

    return SourceId.fromJson(value);
  }

  static RequestId? _readRequestId(Object? value) {
    if (value == null) {
      return null;
    }

    return RequestId.fromJson(value);
  }

  static OperationId? _readOperationId(Object? value) {
    if (value == null) {
      return null;
    }

    return OperationId.fromJson(value);
  }

  static GenerationId? _readGenerationId(Object? value) {
    if (value == null) {
      return null;
    }

    return GenerationId.fromJson(value);
  }

  static String? _readNullableString(Object? value, String fieldName) {
    if (value == null) {
      return null;
    }

    if (value is! String) {
      throw FormatException('$fieldName must be a String or null.');
    }

    final normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  static Map<String, Object?> _readMap(Object? value, String fieldName) {
    if (value == null) {
      return const <String, Object?>{};
    }

    if (value is! Map) {
      throw FormatException('$fieldName must be a JSON object.');
    }

    final result = <String, Object?>{};

    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('$fieldName keys must be Strings.');
      }

      result[entry.key as String] = entry.value;
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  static String? _normalizeText(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  static void _requireKey(String key, String label) {
    if (key.trim().isEmpty) {
      throw ArgumentError.value(key, 'key', '$label cannot be empty.');
    }
  }
}
