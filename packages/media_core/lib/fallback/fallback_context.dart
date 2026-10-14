import 'package:equatable/equatable.dart';
import 'package:media_core/fallback/fallback_reason.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/identity/source_id.dart';

/// Context associated with a fallback operation.
///
/// The context identifies why fallback was requested and which operation,
/// request, source, or renderer generation it belongs to.
///
/// Context is descriptive data only. It does not execute fallback logic.
final class FallbackContext extends Equatable {
  /// Creates a fallback context describing why fallback was requested and
  /// which operation, request, source, or generation it belongs to.
  const FallbackContext({
    required this.reason,
    this.operationId,
    this.requestId,
    this.sourceId,
    this.generationId,
    this.message,
    this.metadata = const <String, Object?>{},
  });

  /// Why fallback was requested.
  final FallbackReason reason;

  /// The operation this fallback belongs to, when triggered by one.
  final OperationId? operationId;

  /// The request this fallback belongs to, when triggered by one.
  final RequestId? requestId;

  /// The source this fallback belongs to, when triggered by one.
  final SourceId? sourceId;

  /// The renderer generation this fallback belongs to, when known.
  final GenerationId? generationId;

  /// Optional human-readable detail about the fallback.
  final String? message;

  /// Arbitrary descriptive data carried alongside the fallback request.
  final Map<String, Object?> metadata;

  /// Whether an [operationId] is associated with this context.
  bool get hasOperation => operationId != null;

  /// Whether a [requestId] is associated with this context.
  bool get hasRequest => requestId != null;

  /// Whether a [sourceId] is associated with this context.
  bool get hasSource => sourceId != null;

  /// Whether a [generationId] is associated with this context.
  bool get hasGeneration => generationId != null;

  /// Whether a non-empty [message] is present.
  bool get hasMessage => message != null && message!.isNotEmpty;

  /// Whether [metadata] carries any entries.
  bool get hasMetadata => metadata.isNotEmpty;

  /// Returns a copy with the given fields replaced.
  FallbackContext copyWith({
    FallbackReason? reason,
    OperationId? operationId,
    RequestId? requestId,
    SourceId? sourceId,
    GenerationId? generationId,
    String? message,
    Map<String, Object?>? metadata,
  }) {
    return FallbackContext(
      reason: reason ?? this.reason,
      operationId: operationId ?? this.operationId,
      requestId: requestId ?? this.requestId,
      sourceId: sourceId ?? this.sourceId,
      generationId: generationId ?? this.generationId,
      message: message ?? this.message,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Serializes the context, stringifying identifiers and copying [metadata].
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'reason': reason.toString(),
      'operationId': operationId?.toString(),
      'requestId': requestId?.toString(),
      'sourceId': sourceId?.toString(),
      'generationId': generationId?.toString(),
      'message': message,
      'metadata': Map<String, dynamic>.from(metadata),
    };
  }

  @override
  List<Object?> get props => <Object?>[reason, operationId, requestId, sourceId, generationId, message, metadata];

  @override
  String toString() {
    return 'FallbackContext('
        'reason: $reason, '
        'operationId: $operationId, '
        'requestId: $requestId, '
        'sourceId: $sourceId, '
        'generationId: $generationId, '
        'message: $message, '
        'metadata: $metadata'
        ')';
  }
}
