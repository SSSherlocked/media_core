/// What went wrong in a danmaku session.
///
/// A danmaku failure is not a playback failure: chat can be dead while video
/// plays perfectly, and the caller's reaction differs (show a notice, retry
/// the socket, or ignore it entirely). Keeping a separate type means the
/// module never has to borrow the player's error model to say "the chat
/// socket did not answer".
enum DanmakuFailureKind {
  /// The transport did not confirm readiness inside the configured timeout.
  startTimeout,

  /// The transport threw while starting.
  startRejected,

  /// The transport reported a terminal close after it had started.
  transportClosed,

  /// A connect request was superseded before its serialized body completed.
  ///
  /// Not an error the caller has to act on — it means a newer request won —
  /// but reported so a session that never connects is explainable.
  superseded,
}

/// One danmaku failure with its cause preserved.
final class DanmakuFailure {
  /// One failure report; [cause] keeps the original error for logs, never for
  /// presentation.
  const DanmakuFailure({
    required this.kind,
    required this.message,
    this.roomKey,
    this.transportId,
    this.isRecoverable = true,
    this.cause,
  });

  /// Which transition failed; drives recovery and presentation.
  final DanmakuFailureKind kind;

  /// Human-readable summary. Never localized: the host decides how to present
  /// a failure, and a translated string baked in here could not be re-used for
  /// logs.
  final String message;

  /// Session key the failure belongs to, when it is room-scoped.
  final String? roomKey;

  /// Transport that produced the failure, when known.
  final String? transportId;

  /// Whether reconnecting the same room could succeed.
  final bool isRecoverable;

  /// Original error object, kept for logging.
  final Object? cause;

  @override
  String toString() =>
      'DanmakuFailure(${kind.name}${roomKey == null ? '' : ' $roomKey'}'
      '${transportId == null ? '' : ' via $transportId'}: $message)';
}
