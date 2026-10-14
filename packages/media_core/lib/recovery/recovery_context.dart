import 'package:equatable/equatable.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/recovery/recovery_reason.dart';

/// Context associated with a recovery attempt.
///
/// The context carries identity and diagnostic information required
/// to correlate a recovery operation with the operation and source
/// that caused it.
///
/// It does not contain recovery policy or execute recovery actions.
final class RecoveryContext extends Equatable {
  /// Records what triggered recovery together with the identities needed to tie the attempt to the operation that failed.
  const RecoveryContext({
    required this.reason,
    this.operationId,
    this.requestId,
    this.sourceId,
    this.generationId,
    this.message,
    this.metadata = const <String, Object?>{},
  });

  /// Reason that triggered recovery.
  final RecoveryReason reason;

  /// Operation associated with the failure.
  final OperationId? operationId;

  /// Request associated with the failure.
  final RequestId? requestId;

  /// Source associated with the failure.
  final SourceId? sourceId;

  /// Generation associated with the failure.
  ///
  /// This prevents an old recovery request from being applied
  /// to a newer generation of the same operation.
  final GenerationId? generationId;

  /// Optional human-readable diagnostic message.
  final String? message;

  /// Additional diagnostic metadata.
  final Map<String, Object?> metadata;

  /// Whether this context identifies an operation.
  bool get hasOperation => operationId != null;

  /// Whether this context identifies a request.
  bool get hasRequest => requestId != null;

  /// Whether this context identifies a source.
  bool get hasSource => sourceId != null;

  /// Whether this context identifies a generation.
  bool get hasGeneration => generationId != null;

  /// Creates a modified context.
  RecoveryContext copyWith({
    RecoveryReason? reason,
    OperationId? operationId,
    RequestId? requestId,
    SourceId? sourceId,
    GenerationId? generationId,
    String? message,
    Map<String, Object?>? metadata,
  }) {
    return RecoveryContext(
      reason: reason ?? this.reason,
      operationId: operationId ?? this.operationId,
      requestId: requestId ?? this.requestId,
      sourceId: sourceId ?? this.sourceId,
      generationId: generationId ?? this.generationId,
      message: message ?? this.message,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Serialises the context for diagnostics and persistence.
  ///
  /// The reason is written as its runtime type name, because the sealed reason subtypes carry no data of their own.
  Map<String, dynamic> toMap() {
    return {
      'reason': reason.runtimeType.toString(),
      'operationId': operationId?.toString(),
      'requestId': requestId?.toString(),
      'sourceId': sourceId?.toString(),
      'generationId': generationId?.toString(),
      'message': message,
      'metadata': metadata,
    };
  }

  @override
  List<Object?> get props => [reason, operationId, requestId, sourceId, generationId, message, metadata];

  @override
  String toString() {
    return 'RecoveryContext('
        'reason=$reason, '
        'operationId=$operationId, '
        'requestId=$requestId, '
        'sourceId=$sourceId, '
        'generationId=$generationId)';
  }
}
