import 'package:media_core/error/error_context.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/error/player_failure.dart';

/// Base exception type used by the media player core.
///
/// [PlayerException] represents an operational error that occurred while
/// executing a player operation.
///
/// The exception itself does not decide how the error should be handled.
/// Classification, policy, recovery, and formatting are handled by their
/// respective components.
final class PlayerException implements Exception {
  /// Wraps [code] together with whatever diagnostics were available at the
  /// point the operation failed.
  PlayerException({required this.code, this.message, this.cause, this.stackTrace, this.context});

  /// Creates a [PlayerException] from another error.
  ///
  /// Existing [PlayerException] instances are returned unchanged.
  factory PlayerException.from(
    Object error, {
    PlayerErrorCode code = PlayerErrorCode.unknown,
    String? message,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) {
    if (error is PlayerException) {
      return error;
    }

    return PlayerException(code: code, message: message, cause: error, stackTrace: stackTrace, context: context);
  }

  /// Stable machine-readable error code.
  final PlayerErrorCode code;

  /// Optional human-readable error message.
  ///
  /// This message is intended to provide additional information about the
  /// specific failure. It should not be treated as a stable API contract.
  final String? message;

  /// The original exception or error that caused this exception.
  final Object? cause;

  /// Stack trace associated with the failure.
  final StackTrace? stackTrace;

  /// Additional player-specific context associated with the failure.
  final ErrorContext? context;

  /// Whether an underlying cause is available.
  bool get hasCause => cause != null;

  /// Whether an explicit message is available.
  bool get hasMessage => message != null && message!.trim().isNotEmpty;

  /// Whether a stack trace is available.
  bool get hasStackTrace => stackTrace != null;

  /// Whether diagnostic context is available.
  bool get hasContext => context != null && context!.isNotEmpty;

  /// Whether this exception contains any diagnostic information.
  bool get hasDiagnostics => hasCause || hasStackTrace || hasContext;

  /// Converts this exception into the structured player failure model.
  PlayerFailure toFailure() {
    return PlayerFailure(code: code, message: message, cause: cause, stackTrace: stackTrace, context: context);
  }

  /// Creates a copy with selected fields replaced.
  PlayerException copyWith({
    PlayerErrorCode? code,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) {
    return PlayerException(
      code: code ?? this.code,
      message: message ?? this.message,
      cause: cause ?? this.cause,
      stackTrace: stackTrace ?? this.stackTrace,
      context: context ?? this.context,
    );
  }

  /// Returns a new exception without its message.
  PlayerException withoutMessage() {
    return PlayerException(code: code, cause: cause, stackTrace: stackTrace, context: context);
  }

  /// Returns a new exception without its cause.
  PlayerException withoutCause() {
    return PlayerException(code: code, message: message, stackTrace: stackTrace, context: context);
  }

  /// Returns a new exception without its stack trace.
  PlayerException withoutStackTrace() {
    return PlayerException(code: code, message: message, cause: cause, context: context);
  }

  /// Returns a new exception without diagnostic context.
  PlayerException withoutContext() {
    return PlayerException(code: code, message: message, cause: cause, stackTrace: stackTrace);
  }

  /// Throws this exception.
  Never throwSelf() {
    throw this;
  }

  @override
  String toString() {
    final buffer = StringBuffer('PlayerException(')
      ..write('code: ')
      ..write(code.value);

    if (hasMessage) {
      buffer
        ..write(', message: ')
        ..write(message!.trim());
    }

    if (hasCause) {
      buffer
        ..write(', cause: ')
        ..write(cause);
    }

    if (hasContext) {
      buffer
        ..write(', context: ')
        ..write(context);
    }

    buffer.write(')');

    return buffer.toString();
  }
}
