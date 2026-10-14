import 'package:media_core/error/error_context.dart';
import 'package:media_core/error/player_error_category.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/error/player_failure.dart';

/// Utility functions for working with player errors.
///
/// This class provides small, stateless helpers for converting and inspecting
/// errors without introducing retry, fallback, or recovery policy.
///
/// Policy decisions remain the responsibility of the policy layer.
abstract final class ErrorUtils {
  /// Converts an arbitrary error into a [PlayerFailure].
  ///
  /// Existing [PlayerFailure] instances are returned unchanged.
  static PlayerFailure toFailure(
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

  /// Converts an arbitrary error into a [PlayerFailure].
  ///
  /// Unlike [toFailure], this method also accepts a nullable error and
  /// returns `null` when no error is supplied.
  static PlayerFailure? tryToFailure(
    Object? error, {
    PlayerErrorCode code = PlayerErrorCode.unknown,
    String? message,
    StackTrace? stackTrace,
    ErrorContext? context,
    PlayerErrorCategory? category,
  }) {
    if (error == null) {
      return null;
    }

    return toFailure(error, code: code, message: message, stackTrace: stackTrace, context: context, category: category);
  }

  /// Returns the underlying cause of [failure], or the failure itself
  /// when no separate cause is available.
  static Object unwrap(PlayerFailure failure) {
    return failure.cause ?? failure;
  }

  /// Returns the most useful message available for [error].
  ///
  /// The structured [PlayerFailure.message] is preferred. If it is absent,
  /// the underlying cause's string representation is used.
  static String messageOf(Object error) {
    if (error is PlayerFailure) {
      final message = error.message;

      if (message != null && message.trim().isNotEmpty) {
        return message.trim();
      }

      final cause = error.cause;
      if (cause != null) {
        return cause.toString();
      }
    }

    return error.toString();
  }

  /// Returns the error code associated with [error].
  ///
  /// Non-[PlayerFailure] errors resolve to [PlayerErrorCode.unknown].
  static PlayerErrorCode codeOf(Object error) {
    if (error is PlayerFailure) {
      return error.code;
    }

    return PlayerErrorCode.unknown;
  }

  /// Returns the category explicitly stored on [error], or resolves the
  /// category from its error code when possible.
  static PlayerErrorCategory categoryOf(Object error) {
    if (error is PlayerFailure) {
      return error.effectiveCategory;
    }

    return PlayerErrorCategory.unknown;
  }

  /// Returns the error context when [error] is a [PlayerFailure].
  static ErrorContext? contextOf(Object error) {
    if (error is PlayerFailure) {
      return error.context;
    }

    return null;
  }

  /// Returns whether [error] is a [PlayerFailure].
  static bool isPlayerFailure(Object error) {
    return error is PlayerFailure;
  }

  /// Returns whether [error] represents cancellation.
  static bool isCancellation(Object error) {
    if (error is PlayerFailure) {
      return error.isCancelled;
    }

    return false;
  }

  /// Returns whether [error] represents an unsupported capability.
  static bool isUnsupported(Object error) {
    if (error is PlayerFailure) {
      return error.isUnsupported;
    }

    return false;
  }

  /// Returns whether [error] represents a timeout.
  static bool isTimeout(Object error) {
    if (error is PlayerFailure) {
      return error.isTimeout;
    }

    return false;
  }

  /// Returns whether [error] is network-related.
  static bool isNetworkRelated(Object error) {
    if (error is PlayerFailure) {
      return error.isNetworkRelated;
    }

    return false;
  }

  /// Returns whether [error] is source-related.
  static bool isSourceRelated(Object error) {
    if (error is PlayerFailure) {
      return error.isSourceRelated;
    }

    return false;
  }

  /// Returns whether [error] is backend-related.
  static bool isBackendRelated(Object error) {
    if (error is PlayerFailure) {
      return error.isBackendRelated;
    }

    return false;
  }

  /// Returns whether [error] is potentially recoverable according to the
  /// static hint carried by its error code.
  ///
  /// This does not mean recovery should actually be attempted.
  static bool isPotentiallyRecoverable(Object error) {
    if (error is PlayerFailure) {
      return error.isPotentiallyRecoverable;
    }

    return false;
  }

  /// Returns whether [error] has diagnostic information.
  static bool hasDiagnostics(Object error) {
    if (error is PlayerFailure) {
      return error.hasDiagnostics;
    }

    return false;
  }

  /// Returns a normalized [PlayerFailure] while preserving an existing
  /// structured failure.
  static PlayerFailure normalize(
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

  /// Creates an unknown failure from an arbitrary error.
  static PlayerFailure unknown(Object error, {String? message, StackTrace? stackTrace, ErrorContext? context}) {
    return PlayerFailure(
      code: PlayerErrorCode.unknown,
      message: message,
      cause: error,
      stackTrace: stackTrace,
      context: context,
      category: PlayerErrorCategory.unknown,
    );
  }

  /// Creates an unsupported failure.
  static PlayerFailure unsupported({String? message, Object? cause, StackTrace? stackTrace, ErrorContext? context}) {
    return PlayerFailure(
      code: PlayerErrorCode.unsupported,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: PlayerErrorCategory.unsupported,
    );
  }

  /// Creates a cancellation failure.
  static PlayerFailure cancelled({String? message, Object? cause, StackTrace? stackTrace, ErrorContext? context}) {
    return PlayerFailure(
      code: PlayerErrorCode.cancelled,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: PlayerErrorCategory.cancellation,
    );
  }

  /// Creates a timeout failure.
  static PlayerFailure timeout({String? message, Object? cause, StackTrace? stackTrace, ErrorContext? context}) {
    return PlayerFailure(
      code: PlayerErrorCode.timeout,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: PlayerErrorCategory.timeout,
    );
  }

  /// Creates a network failure.
  static PlayerFailure network({
    PlayerErrorCode code = PlayerErrorCode.network,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) {
    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: PlayerErrorCategory.network,
    );
  }

  /// Creates a source failure.
  static PlayerFailure source({
    PlayerErrorCode code = PlayerErrorCode.sourceInvalid,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) {
    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: PlayerErrorCategory.source,
    );
  }

  /// Creates a backend failure.
  static PlayerFailure backend({
    PlayerErrorCode code = PlayerErrorCode.backendUnavailable,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) {
    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: PlayerErrorCategory.backend,
    );
  }

  /// Creates a playback failure.
  static PlayerFailure playback({
    PlayerErrorCode code = PlayerErrorCode.playbackFailed,
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    ErrorContext? context,
  }) {
    return PlayerFailure(
      code: code,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
      category: PlayerErrorCategory.playback,
    );
  }
}
