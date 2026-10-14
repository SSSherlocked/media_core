import 'package:equatable/equatable.dart';
import 'package:media_core/error/error_classifier.dart';
import 'package:media_core/error/error_context.dart';
import 'package:media_core/error/player_error_category.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/error/player_exception.dart';

/// Immutable concrete failure produced by the media player core.
///
/// [PlayerErrorCode] identifies the specific failure, while
/// [PlayerErrorCategory] identifies its broader failure domain.
///
/// [PlayerFailure] is a data/diagnostic object only.
///
/// It does not:
/// - decide whether an error should be retried;
/// - decide whether fallback should be used;
/// - decide whether recovery should be performed;
/// - execute recovery;
/// - format user-facing messages.
///
/// Those responsibilities belong to higher-level policy and recovery layers.
final class PlayerFailure extends Equatable {
  /// Records [code] as the failure, with the optional diagnostics that were
  /// available where it happened.
  const PlayerFailure({required this.code, this.message, this.cause, this.stackTrace, this.context, this.category});

  /// Creates a failure from an error code.
  const PlayerFailure.fromCode(
    PlayerErrorCode code, {
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
    PlayerErrorCategory? category,
  }) : this(code: code, message: message, cause: cause, stackTrace: stackTrace, context: context, category: category);

  /// Creates an unknown player failure.
  const PlayerFailure.unknown({String? message, Object? cause, StackTrace? stackTrace, ErrorContext? context})
    : this(code: PlayerErrorCode.unknown, message: message, cause: cause, stackTrace: stackTrace, context: context);

  /// Creates an invalid argument failure.
  const PlayerFailure.invalidArgument({String? message, Object? cause, StackTrace? stackTrace, ErrorContext? context})
    : this(
        code: PlayerErrorCode.invalidArgument,
        message: message,
        cause: cause,
        stackTrace: stackTrace,
        context: context,
        category: PlayerErrorCategory.invalidArgument,
      );

  /// Creates an unsupported operation or capability failure.
  const PlayerFailure.unsupported({String? message, Object? cause, StackTrace? stackTrace, ErrorContext? context})
    : this(
        code: PlayerErrorCode.unsupported,
        message: message,
        cause: cause,
        stackTrace: stackTrace,
        context: context,
        category: PlayerErrorCategory.unsupported,
      );

  /// Creates an invalid state failure.
  const PlayerFailure.invalidState({String? message, Object? cause, StackTrace? stackTrace, ErrorContext? context})
    : this(
        code: PlayerErrorCode.invalidState,
        message: message,
        cause: cause,
        stackTrace: stackTrace,
        context: context,
        category: PlayerErrorCategory.state,
      );

  /// Creates a cancellation failure.
  const PlayerFailure.cancelled({String? message, Object? cause, StackTrace? stackTrace, ErrorContext? context})
    : this(
        code: PlayerErrorCode.cancelled,
        message: message,
        cause: cause,
        stackTrace: stackTrace,
        context: context,
        category: PlayerErrorCategory.cancellation,
      );

  /// Creates a timeout failure.
  const PlayerFailure.timeout({String? message, Object? cause, StackTrace? stackTrace, ErrorContext? context})
    : this(
        code: PlayerErrorCode.timeout,
        message: message,
        cause: cause,
        stackTrace: stackTrace,
        context: context,
        category: PlayerErrorCategory.timeout,
      );

  /// Creates a network failure.
  const PlayerFailure.network({
    PlayerErrorCode code = PlayerErrorCode.network,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) : this(
         code: code,
         message: message,
         cause: cause,
         stackTrace: stackTrace,
         context: context,
         category: PlayerErrorCategory.network,
       );

  /// Creates a source failure.
  const PlayerFailure.source({
    PlayerErrorCode code = PlayerErrorCode.sourceInvalid,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) : this(
         code: code,
         message: message,
         cause: cause,
         stackTrace: stackTrace,
         context: context,
         category: PlayerErrorCategory.source,
       );

  /// Creates a backend failure.
  const PlayerFailure.backend({
    PlayerErrorCode code = PlayerErrorCode.backendUnavailable,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) : this(
         code: code,
         message: message,
         cause: cause,
         stackTrace: stackTrace,
         context: context,
         category: PlayerErrorCategory.backend,
       );

  /// Creates a playback failure.
  const PlayerFailure.playback({
    PlayerErrorCode code = PlayerErrorCode.playbackFailed,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) : this(
         code: code,
         message: message,
         cause: cause,
         stackTrace: stackTrace,
         context: context,
         category: PlayerErrorCategory.playback,
       );

  /// Creates a decoder failure.
  const PlayerFailure.decoder({
    PlayerErrorCode code = PlayerErrorCode.decoderError,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) : this(
         code: code,
         message: message,
         cause: cause,
         stackTrace: stackTrace,
         context: context,
         category: PlayerErrorCategory.decoder,
       );

  /// Creates a renderer failure.
  const PlayerFailure.renderer({
    PlayerErrorCode code = PlayerErrorCode.rendererTextureFailed,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) : this(
         code: code,
         message: message,
         cause: cause,
         stackTrace: stackTrace,
         context: context,
         category: PlayerErrorCategory.renderer,
       );

  /// Creates a lifecycle failure.
  const PlayerFailure.lifecycle({
    PlayerErrorCode code = PlayerErrorCode.lifecycleTransitionFailed,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) : this(
         code: code,
         message: message,
         cause: cause,
         stackTrace: stackTrace,
         context: context,
         category: PlayerErrorCategory.lifecycle,
       );

  /// Creates a recovery failure.
  const PlayerFailure.recovery({
    PlayerErrorCode code = PlayerErrorCode.recoveryFailed,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) : this(
         code: code,
         message: message,
         cause: cause,
         stackTrace: stackTrace,
         context: context,
         category: PlayerErrorCategory.recovery,
       );

  /// Creates a fallback failure.
  const PlayerFailure.fallback({
    PlayerErrorCode code = PlayerErrorCode.fallbackSelectionFailed,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) : this(
         code: code,
         message: message,
         cause: cause,
         stackTrace: stackTrace,
         context: context,
         category: PlayerErrorCategory.fallback,
       );

  /// Creates a failure from an arbitrary error object.
  ///
  /// If [error] is already a [PlayerFailure], it is returned directly.
  factory PlayerFailure.fromError(
    Object error, {
    PlayerErrorCode code = PlayerErrorCode.unknown,
    String? message,
    StackTrace? stackTrace,
    ErrorContext? context,
    PlayerErrorCategory? category,
  }) {
    if (error is PlayerFailure) {
      return error;
    }

    return PlayerFailure(
      code: code,
      message: message,
      cause: error,
      stackTrace: stackTrace,
      context: context,
      category: category,
    );
  }

  /// Creates a failure from an arbitrary [error].
  ///
  /// This is equivalent to [PlayerFailure.fromError].
  factory PlayerFailure.from(
    Object error, {
    PlayerErrorCode code = PlayerErrorCode.unknown,
    String? message,
    StackTrace? stackTrace,
    ErrorContext? context,
    PlayerErrorCategory? category,
  }) {
    return PlayerFailure.fromError(
      error,
      code: code,
      message: message,
      stackTrace: stackTrace,
      context: context,
      category: category,
    );
  }

  /// The specific machine-readable error code.
  final PlayerErrorCode code;

  /// Optional diagnostic or technical error message.
  final String? message;

  /// Original underlying error, when available.
  final Object? cause;

  /// Stack trace associated with the failure.
  final StackTrace? stackTrace;

  /// Optional structured runtime context.
  final ErrorContext? context;

  /// Explicit broad error category.
  ///
  /// When omitted, [effectiveCategory] resolves the category from
  /// [ErrorClassifier].
  final PlayerErrorCategory? category;

  // ===========================================================================
  // Properties
  // ===========================================================================

  /// Whether a non-empty message is available.
  bool get hasMessage {
    final value = message;
    return value != null && value.trim().isNotEmpty;
  }

  /// Whether an underlying cause is available.
  bool get hasCause => cause != null;

  /// Whether a stack trace is available.
  bool get hasStackTrace => stackTrace != null;

  /// Whether structured context is available.
  bool get hasContext {
    final value = context;
    return value != null && value.isNotEmpty;
  }

  /// Whether an explicit category is available.
  bool get hasCategory => category != null;

  /// Whether diagnostic information is available.
  bool get hasDiagnostics {
    return hasCause || hasStackTrace || hasContext;
  }

  /// Whether this failure is unknown.
  bool get isUnknown {
    return code == PlayerErrorCode.unknown;
  }

  /// Whether this failure represents an invalid argument.
  bool get isInvalidArgument {
    return code == PlayerErrorCode.invalidArgument || category == PlayerErrorCategory.invalidArgument;
  }

  /// Whether this failure represents an unsupported capability.
  bool get isUnsupported {
    return code == PlayerErrorCode.unsupported || category == PlayerErrorCategory.unsupported;
  }

  /// Whether this failure represents an invalid state.
  bool get isInvalidState {
    return code == PlayerErrorCode.invalidState ||
        code == PlayerErrorCode.playbackInvalidState ||
        category == PlayerErrorCategory.state;
  }

  /// Whether this failure represents cancellation.
  bool get isCancelled {
    return code.isCancellation || category == PlayerErrorCategory.cancellation;
  }

  /// Whether this failure represents a timeout.
  bool get isTimeout {
    return category == PlayerErrorCategory.timeout ||
        code == PlayerErrorCode.timeout ||
        code == PlayerErrorCode.networkTimeout;
  }

  /// Whether this failure is network-related.
  bool get isNetworkRelated {
    return code.isNetworkRelated ||
        category == PlayerErrorCategory.network ||
        category == PlayerErrorCategory.http ||
        category == PlayerErrorCategory.authentication ||
        category == PlayerErrorCategory.security;
  }

  /// Whether this failure is source-related.
  bool get isSourceRelated {
    return code.isSourceRelated || category == PlayerErrorCategory.source;
  }

  /// Whether this failure is backend-related.
  bool get isBackendRelated {
    return code.isBackendRelated || category == PlayerErrorCategory.adapter || category == PlayerErrorCategory.backend;
  }

  /// Whether this failure is potentially recoverable.
  ///
  /// This is only a property of the error itself.
  /// It does not mean recovery should actually be attempted.
  bool get isPotentiallyRecoverable {
    return code.isPotentiallyRecoverable;
  }

  // ===========================================================================
  // Category
  // ===========================================================================

  /// Returns the effective category of this failure.
  ///
  /// An explicitly supplied [category] takes precedence.
  ///
  /// When no explicit category is supplied, [ErrorClassifier] is the single
  /// source of truth for classifying the error code.
  PlayerErrorCategory get effectiveCategory {
    return category ?? ErrorClassifier.classify(code);
  }

  /// Returns the stable value of the effective category.
  String get categoryValue => effectiveCategory.value;

  /// Returns whether the failure belongs to [category].
  bool hasCategoryValue(PlayerErrorCategory category) {
    return effectiveCategory == category;
  }

  // ===========================================================================
  // Value helpers
  // ===========================================================================

  /// Returns a copy with selected fields replaced.
  ///
  /// Nullable fields retain their current value when omitted.
  /// Use [clear] or the corresponding `withoutX` method to explicitly
  /// remove nullable values.
  PlayerFailure copyWith({
    PlayerErrorCode? code,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
    PlayerErrorCategory? category,
  }) {
    return PlayerFailure(
      code: code ?? this.code,
      message: message ?? this.message,
      cause: cause ?? this.cause,
      stackTrace: stackTrace ?? this.stackTrace,
      context: context ?? this.context,
      category: category ?? this.category,
    );
  }

  /// Returns a copy with selected optional fields cleared.
  PlayerFailure clear({
    bool message = false,
    bool cause = false,
    bool stackTrace = false,
    bool context = false,
    bool category = false,
  }) {
    return PlayerFailure(
      code: code,
      message: message ? null : this.message,
      cause: cause ? null : this.cause,
      stackTrace: stackTrace ? null : this.stackTrace,
      context: context ? null : this.context,
      category: category ? null : this.category,
    );
  }

  /// Returns a copy with a different error code.
  PlayerFailure withCode(PlayerErrorCode code) {
    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: category,
    );
  }

  /// Returns a copy without an explicit category.
  ///
  /// After removing the explicit category, [effectiveCategory] will
  /// classify the error through [ErrorClassifier].
  PlayerFailure withoutCategory() {
    return PlayerFailure(code: code, message: message, cause: cause, stackTrace: stackTrace, context: context);
  }

  /// Returns a copy with [category].
  PlayerFailure withCategory(PlayerErrorCategory category) {
    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: category,
    );
  }

  /// Returns a copy with [context].
  PlayerFailure withContext(ErrorContext context) {
    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: category,
    );
  }

  /// Returns a copy without structured context.
  PlayerFailure withoutContext() {
    return PlayerFailure(code: code, message: message, cause: cause, stackTrace: stackTrace, category: category);
  }

  /// Returns a copy with [message].
  PlayerFailure withMessage(String message) {
    final normalized = message.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(message, 'message', 'Failure message cannot be empty.');
    }

    return PlayerFailure(
      code: code,
      message: normalized,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: category,
    );
  }

  /// Returns a copy without a message.
  PlayerFailure withoutMessage() {
    return PlayerFailure(code: code, cause: cause, stackTrace: stackTrace, context: context, category: category);
  }

  /// Returns a copy with [cause].
  PlayerFailure withCause(Object cause) {
    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: category,
    );
  }

  /// Returns a copy without an underlying cause.
  PlayerFailure withoutCause() {
    return PlayerFailure(code: code, message: message, stackTrace: stackTrace, context: context, category: category);
  }

  /// Returns a copy with [stackTrace].
  PlayerFailure withStackTrace(StackTrace stackTrace) {
    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: category,
    );
  }

  /// Returns a copy without a stack trace.
  PlayerFailure withoutStackTrace() {
    return PlayerFailure(code: code, message: message, cause: cause, context: context, category: category);
  }

  // ===========================================================================
  // Conversion
  // ===========================================================================

  /// Converts this failure into a runtime [PlayerException].
  ///
  /// [PlayerException] is the only exception type exposed by the error
  /// module. The structured failure remains the source of truth for
  /// diagnostics.
  PlayerException toException() {
    return PlayerException(code: code, message: message, cause: cause, stackTrace: stackTrace, context: context);
  }

  // ===========================================================================
  // Equatable
  // ===========================================================================

  @override
  List<Object?> get props => <Object?>[code, message, cause, stackTrace, context, category];

  @override
  String toString() {
    final buffer = StringBuffer('PlayerFailure(')
      ..write('code: ')
      ..write(code.value);

    final explicitCategory = category;

    if (explicitCategory != null) {
      buffer
        ..write(', category: ')
        ..write(explicitCategory.value);
    }

    final currentMessage = message;

    if (currentMessage != null && currentMessage.trim().isNotEmpty) {
      buffer
        ..write(', message: ')
        ..write(currentMessage.trim());
    }

    final currentCause = cause;

    if (currentCause != null) {
      buffer
        ..write(', cause: ')
        ..write(currentCause);
    }

    final currentContext = context;

    if (currentContext != null && currentContext.isNotEmpty) {
      buffer
        ..write(', context: ')
        ..write(currentContext);
    }

    buffer.write(')');

    return buffer.toString();
  }
}
