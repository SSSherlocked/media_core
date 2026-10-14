import 'package:equatable/equatable.dart';
import 'package:media_core/error/error_classifier.dart';
import 'package:media_core/error/error_context.dart';
import 'package:media_core/error/player_error_category.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/error/player_failure.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/recovery/recovery_reason.dart';

/// Describes which layer observed a failure.
///
/// Recovery deliberately does not treat every reporter the same: an
/// adapter error and a watchdog-inferred stall reach the same ladder,
/// but they are not the same evidence. The reporter is carried through
/// the ladder as diagnostic data and as policy input.
enum RecoveryFailureSource {
  /// The adapter reported an error event.
  adapter,

  /// A watchdog inferred a stall (no frames, no progress, no resume).
  watchdog,

  /// The playback owner observed a failed playback command.
  playback,

  /// An application-level action failed.
  user,

  /// The kernel observed the failure while orchestrating.
  kernel,

  /// The reporter is unknown.
  unknown,
}

/// Normalized playback failure used by the recovery ladder.
///
/// A [RecoveryFailure] is the single shape every reporter hands to the
/// ladder: the adapter, the watchdogs and the playback owner all
/// normalize into this type, so the ladder never has to know which
/// module produced the evidence.
///
/// It carries the error code, the diagnostic message and the identity
/// of the failing unit (source, backend, generation). It does not carry
/// policy and it executes nothing.
final class RecoveryFailure extends Equatable {
  /// Creates a normalized failure.
  const RecoveryFailure({
    required this.code,
    required this.message,
    this.source = RecoveryFailureSource.unknown,
    this.category,
    this.reason,
    this.cause,
    this.stackTrace,
    this.sourceId,
    this.backendId,
    this.generationId,
    this.uri,
    this.metadata = const <String, Object?>{},
  });

  /// Builds a failure from an error module [PlayerFailure].
  factory RecoveryFailure.fromFailure(
    PlayerFailure failure, {
    RecoveryFailureSource source = RecoveryFailureSource.unknown,
    SourceId? sourceId,
    String? backendId,
    GenerationId? generationId,
    String? uri,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RecoveryFailure(
      code: failure.code,
      message: failure.message ?? failure.code.value,
      source: source,
      category: failure.effectiveCategory,
      cause: failure.cause,
      stackTrace: failure.stackTrace,
      sourceId: sourceId,
      backendId: backendId,
      generationId: generationId,
      uri: uri ?? failure.context?.uri,
      metadata: metadata,
    );
  }

  /// Normalizes a raw backend or watchdog message into a failure.
  ///
  /// Adapters report free-form text; the recovery layer needs a code
  /// and a reason it can act on. This is the one place where that
  /// sniffing happens, so every reporter gets the same classification
  /// for the same text.
  factory RecoveryFailure.fromMessage(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    RecoveryFailureSource source = RecoveryFailureSource.unknown,
    PlayerErrorCode? code,
    SourceId? sourceId,
    String? backendId,
    GenerationId? generationId,
    String? uri,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final reason = RecoveryReason.classify(message, error);

    return RecoveryFailure(
      code: code ?? _codeForReason(reason),
      message: message,
      source: source,
      reason: reason,
      cause: error,
      stackTrace: stackTrace,
      sourceId: sourceId,
      backendId: backendId,
      generationId: generationId,
      uri: uri,
      metadata: metadata,
    );
  }

  /// Error code describing the failure.
  final PlayerErrorCode code;

  /// Human-readable diagnostic message.
  final String message;

  /// Which layer observed the failure.
  final RecoveryFailureSource source;

  /// Explicit error category, when the reporter already knew it.
  ///
  /// When absent the category is derived from [code].
  final PlayerErrorCategory? category;

  /// Explicit recovery reason, when the reporter already knew it.
  ///
  /// When absent the reason is derived from [message] and [cause].
  final RecoveryReason? reason;

  /// Underlying error object, when one exists.
  final Object? cause;

  /// Stack trace of [cause], when available.
  final StackTrace? stackTrace;

  /// Source being played when the failure occurred.
  final SourceId? sourceId;

  /// Backend attached when the failure occurred.
  final String? backendId;

  /// Session generation the failure belongs to.
  final GenerationId? generationId;

  /// URI being played when the failure occurred.
  final String? uri;

  /// Additional diagnostic metadata.
  final Map<String, Object?> metadata;

  /// Error category of this failure.
  PlayerErrorCategory get effectiveCategory {
    return category ?? ErrorClassifier.classify(code);
  }

  /// Recovery reason of this failure.
  RecoveryReason get effectiveReason {
    return reason ?? RecoveryReason.classify(message, cause);
  }

  /// Deduplication key.
  ///
  /// Two reports with the same key describe the same failing unit:
  /// the same error code, on the same source, on the same backend.
  /// The ladder uses it to recognise a repeat of the failure it is
  /// already working on instead of starting a second recovery.
  String get stableKey {
    final source = sourceId?.value ?? uri ?? '-';

    return '${code.value}|$source|${backendId ?? '-'}';
  }

  /// Whether this failure was reported by a watchdog.
  bool get isWatchdog => source == RecoveryFailureSource.watchdog;

  /// Converts back to the error module's failure type.
  ///
  /// A normalized failure is not a replacement for [PlayerFailure]: the
  /// error module speaks its own vocabulary, and the ladder delegates
  /// the entry decision to `ErrorPolicy`. This is the bridge.
  PlayerFailure toFailure() {
    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      category: category,
      context: uri == null && backendId == null ? null : ErrorContext(uri: uri, backend: backendId, metadata: metadata),
    );
  }

  /// Creates a copy with selected values replaced.
  RecoveryFailure copyWith({
    PlayerErrorCode? code,
    String? message,
    RecoveryFailureSource? source,
    PlayerErrorCategory? category,
    RecoveryReason? reason,
    Object? cause,
    StackTrace? stackTrace,
    SourceId? sourceId,
    String? backendId,
    GenerationId? generationId,
    String? uri,
    Map<String, Object?>? metadata,
  }) {
    return RecoveryFailure(
      code: code ?? this.code,
      message: message ?? this.message,
      source: source ?? this.source,
      category: category ?? this.category,
      reason: reason ?? this.reason,
      cause: cause ?? this.cause,
      stackTrace: stackTrace ?? this.stackTrace,
      sourceId: sourceId ?? this.sourceId,
      backendId: backendId ?? this.backendId,
      generationId: generationId ?? this.generationId,
      uri: uri ?? this.uri,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Fills in the identity fields that are still missing.
  ///
  /// Reporters know different amounts about the failing unit: a
  /// watchdog knows the source, the handle knows the backend. This lets
  /// the handle complete a report without overwriting what the reporter
  /// already established.
  RecoveryFailure enriched({SourceId? sourceId, String? backendId, GenerationId? generationId, String? uri}) {
    return RecoveryFailure(
      code: code,
      message: message,
      source: source,
      category: category,
      reason: reason,
      cause: cause,
      stackTrace: stackTrace,
      sourceId: this.sourceId ?? sourceId,
      backendId: this.backendId ?? backendId,
      generationId: this.generationId ?? generationId,
      uri: this.uri ?? uri,
      metadata: metadata,
    );
  }

  /// Serialises the failure for diagnostics and persistence.
  ///
  /// The classified category and reason are written out, so the record can be read back without the classifier.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'code': code.value,
      'message': message,
      'source': source.name,
      'category': effectiveCategory.value,
      'reason': effectiveReason.toString(),
      'sourceId': sourceId?.value,
      'backendId': backendId,
      'generationId': generationId?.value,
      'uri': uri,
      'stableKey': stableKey,
    };
  }

  @override
  List<Object?> get props {
    return <Object?>[code, message, source, effectiveCategory, effectiveReason, sourceId, backendId, generationId, uri];
  }

  @override
  String toString() {
    return 'RecoveryFailure('
        'code=${code.value}, '
        'source=${source.name}, '
        'reason=$effectiveReason, '
        'backend=$backendId, '
        'message=$message'
        ')';
  }
}

PlayerErrorCode _codeForReason(RecoveryReason reason) {
  if (reason.isNetwork) {
    return PlayerErrorCode.networkUnavailable;
  }

  if (reason.isTimeout) {
    return PlayerErrorCode.timeout;
  }

  if (reason.isDecoder) {
    return PlayerErrorCode.decoderError;
  }

  if (reason.isRenderer) {
    return PlayerErrorCode.rendererInitializationFailed;
  }

  if (reason.isSource) {
    return PlayerErrorCode.sourceResolveFailed;
  }

  if (reason.isInitialization) {
    return PlayerErrorCode.backendOpenFailed;
  }

  if (reason.isInterrupted) {
    return PlayerErrorCode.superseded;
  }

  if (reason.isResource) {
    return PlayerErrorCode.resourceUnavailable;
  }

  return PlayerErrorCode.playbackFailed;
}
