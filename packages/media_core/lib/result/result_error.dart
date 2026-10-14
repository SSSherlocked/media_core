import 'package:equatable/equatable.dart';
import 'package:media_core/error/error_context.dart';
import 'package:media_core/error/player_error_category.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/error/player_failure.dart';
import 'package:media_core/result/result.dart' show Result;

/// Represents an error contained by a [Result].
///
/// [ResultError] is the error value used by the result layer.
///
/// It can retain the original [PlayerFailure] so callers do not lose
/// diagnostic information when converting a player failure into a result.
///
/// Classification and recovery policy remain the responsibility of the
/// error layer. [ResultError] only carries the error information required
/// by the result layer.
///
/// A [ResultError] is immutable and value-based.
final class ResultError extends Equatable {
  /// Creates a [ResultError].
  const ResultError({
    required this.code,
    this.message,
    this.cause,
    this.stackTrace,
    this.context,
    this.category,
    this.failure,
  });

  /// Creates a [ResultError] from a [PlayerFailure].
  ///
  /// The original failure is retained in [failure] so that no diagnostic
  /// information is lost.
  factory ResultError.fromFailure(PlayerFailure failure) {
    return ResultError(
      code: failure.code,
      message: failure.message,
      cause: failure.cause,
      stackTrace: failure.stackTrace,
      context: failure.context,
      category: failure.category,
      failure: failure,
    );
  }

  /// Creates a [ResultError] from an arbitrary error.
  ///
  /// When [error] is already a [PlayerFailure], it is preserved directly
  /// through [ResultError.fromFailure].
  factory ResultError.fromError(
    Object error, {
    PlayerErrorCode code = PlayerErrorCode.unknown,
    String? message,
    StackTrace? stackTrace,
    ErrorContext? context,
    PlayerErrorCategory? category,
  }) {
    if (error is PlayerFailure) {
      return ResultError.fromFailure(error);
    }

    return ResultError(
      code: code,
      message: message,
      cause: error,
      stackTrace: stackTrace,
      context: context,
      category: category,
    );
  }

  /// Machine-readable player error code.
  final PlayerErrorCode code;

  /// Optional human-readable error message.
  final String? message;

  /// Original underlying error.
  final Object? cause;

  /// Stack trace associated with the error.
  final StackTrace? stackTrace;

  /// Diagnostic context associated with the error.
  final ErrorContext? context;

  /// Error category.
  final PlayerErrorCategory? category;

  /// Original [PlayerFailure], when this error was created from one.
  final PlayerFailure? failure;

  /// Returns `true` when a non-empty message is available.
  bool get hasMessage {
    final value = message;
    return value != null && value.trim().isNotEmpty;
  }

  /// Returns `true` when an underlying cause is available.
  bool get hasCause => cause != null;

  /// Returns `true` when a stack trace is available.
  bool get hasStackTrace => stackTrace != null;

  /// Returns `true` when diagnostic context is available.
  bool get hasContext {
    final value = context;
    return value != null && value.isNotEmpty;
  }

  /// Returns `true` when an error category is available.
  bool get hasCategory => category != null;

  /// Returns `true` when the original [PlayerFailure] is available.
  bool get hasFailure => failure != null;

  /// Returns `true` when this error contains diagnostic information.
  ///
  /// Diagnostic information consists of an underlying cause, stack trace,
  /// or diagnostic context.
  bool get hasDiagnostics {
    return hasCause || hasStackTrace || hasContext;
  }

  /// Converts this result error back into a [PlayerFailure].
  ///
  /// When the original failure is available, it is returned directly.
  ///
  /// Otherwise a new [PlayerFailure] is created from the stored information.
  PlayerFailure toFailure() {
    final originalFailure = failure;

    if (originalFailure != null) {
      return originalFailure;
    }

    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: category,
    );
  }

  /// Returns a copy with the supplied non-null values replaced.
  ///
  /// Because nullable fields cannot distinguish between "keep the current
  /// value" and "replace with null", use [clear] when a nullable field needs
  /// to be explicitly removed.
  ResultError copyWith({
    PlayerErrorCode? code,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
    PlayerErrorCategory? category,
    PlayerFailure? failure,
  }) {
    return ResultError(
      code: code ?? this.code,
      message: message ?? this.message,
      cause: cause ?? this.cause,
      stackTrace: stackTrace ?? this.stackTrace,
      context: context ?? this.context,
      category: category ?? this.category,
      failure: failure ?? this.failure,
    );
  }

  /// Returns a copy with selected nullable fields cleared.
  ResultError clear({
    bool message = false,
    bool cause = false,
    bool stackTrace = false,
    bool context = false,
    bool category = false,
    bool failure = false,
  }) {
    return ResultError(
      code: code,
      message: message ? null : this.message,
      cause: cause ? null : this.cause,
      stackTrace: stackTrace ? null : this.stackTrace,
      context: context ? null : this.context,
      category: category ? null : this.category,
      failure: failure ? null : this.failure,
    );
  }

  /// Returns a copy with [category] attached.
  ResultError withCategory(PlayerErrorCategory category) {
    return ResultError(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: category,
      failure: failure,
    );
  }

  /// Returns a copy without an attached category.
  ResultError withoutCategory() {
    return ResultError(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      failure: failure,
    );
  }

  /// Returns a copy with [context] attached.
  ResultError withContext(ErrorContext context) {
    return ResultError(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: category,
      failure: failure,
    );
  }

  /// Returns a copy without diagnostic context.
  ResultError withoutContext() {
    return ResultError(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      category: category,
      failure: failure,
    );
  }

  @override
  List<Object?> get props => <Object?>[code, message, cause, stackTrace, context, category, failure];

  @override
  String toString() {
    final buffer = StringBuffer('ResultError(')
      ..write('code: ')
      ..write(code.value);

    final currentCategory = category;
    if (currentCategory != null) {
      buffer
        ..write(', category: ')
        ..write(currentCategory.value);
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

    buffer.write(')');

    return buffer.toString();
  }
}
