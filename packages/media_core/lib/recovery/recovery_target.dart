import 'package:equatable/equatable.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/recovery/recovery_candidate_provider.dart';
import 'package:media_core/recovery/recovery_failure.dart';
import 'package:media_core/recovery/recovery_session.dart';
import 'package:media_core/recovery/recovery_step.dart';

/// What happened while a recovery target executed a step.
enum RecoveryTargetEventKind {
  /// The target started the physical operation.
  stepStarted,

  /// The operation completed and the backend is usable again.
  stepSucceeded,

  /// The operation threw; the step is spent.
  stepFailed,

  /// The target can no longer execute recovery at all.
  aborted,
}

/// Execution detail reported by a recovery target.
///
/// Target events describe the *physical* side of recovery — what the
/// backend was asked to do and how it went. Ladder events describe the
/// *decision* side. Keeping them separate lets diagnostics answer both
/// "why did it escalate" and "what did the backend do".
final class RecoveryTargetEvent extends Equatable {
  /// Creates a target event.
  const RecoveryTargetEvent({
    required this.kind,
    required this.step,
    this.message,
    this.error,
    this.stackTrace,
    this.sourceId,
    this.backendId,
    this.position = Duration.zero,
  });

  /// Execution outcome.
  final RecoveryTargetEventKind kind;

  /// Step that was executed.
  final RecoveryStep step;

  /// Diagnostic message.
  final String? message;

  /// Error thrown by the operation, when it failed.
  final Object? error;

  /// Stack trace of [error], when available.
  final StackTrace? stackTrace;

  /// Source the step was executed against.
  final SourceId? sourceId;

  /// Backend the step was executed against.
  final String? backendId;

  /// Position restored by the step.
  final Duration position;

  /// Whether the step succeeded.
  bool get succeeded => kind == RecoveryTargetEventKind.stepSucceeded;

  /// Whether the step failed.
  bool get failed => kind == RecoveryTargetEventKind.stepFailed;

  /// Whether the target as a whole is no longer usable.
  bool get aborted => kind == RecoveryTargetEventKind.aborted;

  @override
  List<Object?> get props => <Object?>[kind, step, message, error, sourceId, backendId, position];

  @override
  String toString() {
    return 'RecoveryTargetEvent(${kind.name}, ${step.label}'
        '${message == null ? '' : ', $message'})';
  }
}

/// The execution backend of the recovery ladder.
///
/// The ladder decides *when* to reopen a backend, switch a line or
/// attach another engine; the target performs those operations, because
/// it is the only layer that owns the backend, the session and the
/// lifecycle generations that guard them.
///
/// The dependency runs backwards on purpose: recovery does not know
/// about `PlayerHandle`. The handle implements this interface, so the
/// ladder can drive it without either module importing the other.
///
/// Implementations must:
///
/// - throw when a step fails, so the ladder can advance;
/// - complete normally when the step succeeded and the backend is ready
///   for playback again;
/// - preserve position, volume, rate and play state from the session.
abstract interface class RecoveryTarget {
  /// Whether the target can currently execute a recovery step.
  ///
  /// False when nothing is open, or the target is disposed. The ladder
  /// asks before every step, so a target that becomes unusable mid-run
  /// stops the ladder instead of thrashing.
  bool get isRecoveryAvailable;

  /// Physical execution detail emitted while steps run.
  ///
  /// Named for the execution side on purpose: the ladder's own decision
  /// stream is a separate channel, and keeping the two names distinct
  /// stops a consumer from signing up for the wrong kind of event.
  Stream<RecoveryTargetEvent> get executionEvents;

  /// Builds the decision context for [failure].
  ///
  /// The target owns the live playback state, so it is the only layer
  /// that can answer what to preserve and what to try instead.
  RecoverySession buildRecoverySession(RecoveryFailure failure, RecoveryCandidates candidates);

  /// Reopens the current backend, optionally on another source.
  ///
  /// Handles [RecoveryStepKind.sameBackendReopen] and
  /// [RecoveryStepKind.nextLine]: both keep the attached backend and
  /// (re)open a source on it. Throws when the source cannot be opened.
  Future<void> reopenForRecovery(RecoveryStep step, RecoverySession session);

  /// Attaches the backend named by [step] and opens the session's source.
  ///
  /// Handles [RecoveryStepKind.nextBackend]. Throws when the backend
  /// cannot be attached or the source cannot be opened on it; the
  /// target must leave the previously attached backend usable in that
  /// case.
  Future<void> swapToForRecovery(RecoveryStep step, RecoverySession session);
}
