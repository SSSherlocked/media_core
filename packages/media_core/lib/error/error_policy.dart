import 'package:media_core/error/error_classifier.dart';
import 'package:media_core/error/player_error_category.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/error/player_failure.dart';

/// Defines how player failures should be handled.
///
/// [ErrorClassifier] answers:
///
///   "What kind of error is this?"
///
/// [ErrorPolicy] answers:
///
///   "What should the player do about it?"
///
/// This class only makes policy decisions. It does not perform retry,
/// recovery, or fallback itself.
final class ErrorPolicy {
  /// Builds a policy from explicit retryable and non-retryable code sets and
  /// the handling switches each feature honours.
  ErrorPolicy({
    Set<PlayerErrorCode> retryable = const <PlayerErrorCode>{},
    Set<PlayerErrorCode> nonRetryable = const <PlayerErrorCode>{},
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.enableRetry = true,
    this.enableFallback = true,
    this.enableRecovery = true,
  }) : assert(maxRetries >= 0, 'maxRetries must not be negative.'),
       retryable = Set<PlayerErrorCode>.unmodifiable(retryable),
       nonRetryable = Set<PlayerErrorCode>.unmodifiable(nonRetryable);

  /// Creates the default player error policy.
  factory ErrorPolicy.defaults() {
    return ErrorPolicy(
      retryable: <PlayerErrorCode>{
        PlayerErrorCode.timeout,
        PlayerErrorCode.networkTimeout,
        PlayerErrorCode.networkUnavailable,
        PlayerErrorCode.networkDnsFailed,
        PlayerErrorCode.networkConnectionFailed,
        PlayerErrorCode.networkConnectionRefused,
        PlayerErrorCode.networkAborted,
        PlayerErrorCode.sourceResolveFailed,
        PlayerErrorCode.sourceInspectFailed,
        PlayerErrorCode.backendOpenFailed,
        PlayerErrorCode.playbackFailed,
        PlayerErrorCode.decoderError,
        PlayerErrorCode.resourceUnavailable,
        PlayerErrorCode.insufficientBandwidth,
      },
      nonRetryable: <PlayerErrorCode>{
        PlayerErrorCode.invalidArgument,
        PlayerErrorCode.invalidState,
        PlayerErrorCode.unsupported,
        PlayerErrorCode.cancelled,
        PlayerErrorCode.staleGeneration,
        PlayerErrorCode.superseded,
        PlayerErrorCode.sourceMissing,
        PlayerErrorCode.sourceInvalid,
        PlayerErrorCode.sourceValidationFailed,
        PlayerErrorCode.sourceProtocolUnsupported,
        PlayerErrorCode.sourceMediaTypeUnsupported,
        PlayerErrorCode.sourceFormatUnsupported,
        PlayerErrorCode.authenticationRequired,
        PlayerErrorCode.authenticationFailed,
        PlayerErrorCode.authorizationFailed,
        PlayerErrorCode.adapterDisposed,
        PlayerErrorCode.backendFatal,
        PlayerErrorCode.codecUnsupported,
        PlayerErrorCode.mediaCorrupted,
        PlayerErrorCode.mediaMetadataInvalid,
        PlayerErrorCode.noPlayableStream,
        PlayerErrorCode.recordingUnsupported,
        PlayerErrorCode.recordingOutputInvalid,
        PlayerErrorCode.cacheEntryInvalid,
        PlayerErrorCode.disposed,
      },
    );
  }

  /// Error codes explicitly considered retryable.
  final Set<PlayerErrorCode> retryable;

  /// Error codes explicitly considered non-retryable.
  ///
  /// This set has higher priority than [retryable].
  final Set<PlayerErrorCode> nonRetryable;

  /// Maximum number of retries allowed for one operation.
  final int maxRetries;

  /// Base delay before a retry.
  final Duration retryDelay;

  /// Whether retry handling is enabled.
  final bool enableRetry;

  /// Whether fallback handling is enabled.
  final bool enableFallback;

  /// Whether recovery handling is enabled.
  final bool enableRecovery;

  /// Returns whether the failure may be retried.
  ///
  /// This is only a policy decision. It does not perform the retry.
  bool shouldRetry(PlayerFailure failure, {int retryCount = 0}) {
    if (!enableRetry) {
      return false;
    }

    if (retryCount >= maxRetries) {
      return false;
    }

    if (failure.isCancelled ||
        failure.code == PlayerErrorCode.staleGeneration ||
        failure.code == PlayerErrorCode.superseded ||
        failure.code == PlayerErrorCode.disposed) {
      return false;
    }

    if (nonRetryable.contains(failure.code)) {
      return false;
    }

    if (retryable.contains(failure.code)) {
      return true;
    }

    return failure.isPotentiallyRecoverable;
  }

  /// Returns whether fallback should be attempted.
  ///
  /// Fallback may mean switching source, line, adapter, or backend.
  bool shouldFallback(PlayerFailure failure) {
    if (!enableFallback) {
      return false;
    }

    if (failure.isCancelled ||
        failure.code == PlayerErrorCode.staleGeneration ||
        failure.code == PlayerErrorCode.superseded ||
        failure.code == PlayerErrorCode.disposed) {
      return false;
    }

    if (failure.isUnsupported) {
      return true;
    }

    if (failure.isSourceRelated || failure.isBackendRelated || failure.isNetworkRelated) {
      return true;
    }

    switch (failure.effectiveCategory) {
      case PlayerErrorCategory.adapter:
      case PlayerErrorCategory.backend:
      case PlayerErrorCategory.decoder:
      case PlayerErrorCategory.demuxer:
      case PlayerErrorCategory.network:
      case PlayerErrorCategory.http:
      case PlayerErrorCategory.source:
        return true;

      default:
        return false;
    }
  }

  /// Returns whether recovery should be attempted.
  ///
  /// Recovery attempts to restore the current playback path without
  /// necessarily selecting another source or backend.
  bool shouldRecover(PlayerFailure failure) {
    if (!enableRecovery) {
      return false;
    }

    if (failure.isCancelled ||
        failure.code == PlayerErrorCode.staleGeneration ||
        failure.code == PlayerErrorCode.superseded ||
        failure.code == PlayerErrorCode.disposed) {
      return false;
    }

    switch (failure.effectiveCategory) {
      case PlayerErrorCategory.playback:
      case PlayerErrorCategory.renderer:
      case PlayerErrorCategory.geometry:
      case PlayerErrorCategory.presentation:
      case PlayerErrorCategory.audio:
      case PlayerErrorCategory.resource:
      case PlayerErrorCategory.memory:
      case PlayerErrorCategory.thermal:
        return true;

      default:
        return false;
    }
  }

  /// Returns whether the failure is terminal for the current operation.
  bool isTerminal(PlayerFailure failure) {
    if (failure.isCancelled) {
      return true;
    }

    if (failure.code == PlayerErrorCode.staleGeneration ||
        failure.code == PlayerErrorCode.superseded ||
        failure.code == PlayerErrorCode.disposed) {
      return true;
    }

    if (nonRetryable.contains(failure.code)) {
      return true;
    }

    return false;
  }

  /// Returns whether an automatic action is available.
  bool hasAutomaticAction(PlayerFailure failure, {int retryCount = 0}) {
    return shouldRetry(failure, retryCount: retryCount) || shouldRecover(failure) || shouldFallback(failure);
  }

  /// Determines the recommended action.
  ErrorPolicyAction decide(PlayerFailure failure, {int retryCount = 0}) {
    if (failure.isCancelled) {
      return ErrorPolicyAction.cancel;
    }

    if (failure.code == PlayerErrorCode.staleGeneration || failure.code == PlayerErrorCode.superseded) {
      return ErrorPolicyAction.ignore;
    }

    if (failure.code == PlayerErrorCode.disposed) {
      return ErrorPolicyAction.ignore;
    }

    if (shouldRetry(failure, retryCount: retryCount)) {
      return ErrorPolicyAction.retry;
    }

    if (shouldRecover(failure)) {
      return ErrorPolicyAction.recover;
    }

    if (shouldFallback(failure)) {
      return ErrorPolicyAction.fallback;
    }

    return ErrorPolicyAction.fail;
  }

  /// Returns the delay before the specified retry attempt.
  ///
  /// Retry 0:
  ///
  ///     retryDelay
  ///
  /// Retry 1:
  ///
  ///     retryDelay
  ///
  /// Retry 2:
  ///
  ///     retryDelay * 2
  ///
  /// Retry 3:
  ///
  ///     retryDelay * 4
  ///
  /// The result is capped at one minute.
  Duration retryDelayFor(int retryCount) {
    if (retryCount <= 0) {
      return retryDelay;
    }

    var multiplier = 1;

    for (var index = 1; index < retryCount; index++) {
      multiplier *= 2;

      final currentMilliseconds = retryDelay.inMilliseconds * multiplier;

      if (currentMilliseconds >= const Duration(minutes: 1).inMilliseconds) {
        return const Duration(minutes: 1);
      }
    }

    final milliseconds = retryDelay.inMilliseconds * multiplier;

    return Duration(milliseconds: milliseconds.clamp(0, const Duration(minutes: 1).inMilliseconds));
  }

  /// Returns the effective error category.
  PlayerErrorCategory categoryOf(PlayerFailure failure) {
    return failure.effectiveCategory;
  }

  /// Returns whether the code belongs to the specified category.
  bool isCategory(PlayerErrorCode code, PlayerErrorCategory category) {
    return ErrorClassifier.classify(code) == category;
  }

  /// Returns a short diagnostic description.
  String describe(PlayerFailure failure) {
    final action = decide(failure);

    return 'code=${failure.code.value}, '
        'category=${failure.effectiveCategory.value}, '
        'action=${action.name}';
  }

  /// Creates a new policy with selected values replaced.
  ErrorPolicy copyWith({
    Set<PlayerErrorCode>? retryable,
    Set<PlayerErrorCode>? nonRetryable,
    int? maxRetries,
    Duration? retryDelay,
    bool? enableRetry,
    bool? enableFallback,
    bool? enableRecovery,
  }) {
    return ErrorPolicy(
      retryable: retryable ?? this.retryable,
      nonRetryable: nonRetryable ?? this.nonRetryable,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      enableRetry: enableRetry ?? this.enableRetry,
      enableFallback: enableFallback ?? this.enableFallback,
      enableRecovery: enableRecovery ?? this.enableRecovery,
    );
  }

  /// Adds an explicitly retryable error code.
  ErrorPolicy withRetryable(PlayerErrorCode code) {
    return copyWith(retryable: <PlayerErrorCode>{...retryable, code});
  }

  /// Adds an explicitly non-retryable error code.
  ErrorPolicy withNonRetryable(PlayerErrorCode code) {
    return copyWith(nonRetryable: <PlayerErrorCode>{...nonRetryable, code});
  }

  /// Removes a code from the retryable set.
  ErrorPolicy withoutRetryable(PlayerErrorCode code) {
    return copyWith(retryable: retryable.where((item) => item != code).toSet());
  }

  /// Removes a code from the non-retryable set.
  ErrorPolicy withoutNonRetryable(PlayerErrorCode code) {
    return copyWith(nonRetryable: nonRetryable.where((item) => item != code).toSet());
  }
}

/// Recommended action produced by [ErrorPolicy].
enum ErrorPolicyAction {
  /// Ignore the failure because it belongs to an obsolete
  /// generation or operation.
  ignore,

  /// Cancellation was requested.
  cancel,

  /// Retry the current operation.
  retry,

  /// Recover the current playback path.
  recover,

  /// Switch to another source, line, adapter, or backend.
  fallback,

  /// No automatic action is appropriate.
  fail,
}
