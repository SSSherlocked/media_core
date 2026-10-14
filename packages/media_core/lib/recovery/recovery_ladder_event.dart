import 'package:equatable/equatable.dart';
import 'package:media_core/recovery/recovery_failure.dart';
import 'package:media_core/recovery/recovery_step.dart';

/// Kind of ladder transition.
enum RecoveryLadderEventKind {
  /// A failure was accepted and the ladder started.
  started,

  /// One step is about to be executed.
  stepStarted,

  /// One step failed; the ladder advanced.
  stepFailed,

  /// Recovery succeeded.
  completed,

  /// No step is left; recovery gave up.
  exhausted,

  /// The run was stopped from the outside (reset, suspend, dispose).
  cancelled,
}

/// A decision transition of the recovery ladder.
///
/// Ladder events are the observability contract of recovery: they are
/// emitted for every rung the ladder climbs, so a diagnosis can be read
/// off the event stream instead of reconstructed from log fragments.
///
/// They describe decisions, not physical operations — see
/// `RecoveryTargetEvent` for the execution side.
sealed class RecoveryLadderEvent extends Equatable {
  const RecoveryLadderEvent({required this.kind, this.failure, this.step, this.attempt = 0, this.message});

  /// Transition kind.
  final RecoveryLadderEventKind kind;

  /// Failure the run is working on.
  final RecoveryFailure? failure;

  /// Step this event is about, when it is about one.
  final RecoveryStep? step;

  /// Attempt counter at the time of the event.
  final int attempt;

  /// Diagnostic message.
  final String? message;

  /// Whether the run reached a terminal state with this event.
  bool get isTerminal {
    return kind == RecoveryLadderEventKind.completed ||
        kind == RecoveryLadderEventKind.exhausted ||
        kind == RecoveryLadderEventKind.cancelled;
  }

  /// Diagnostic detail of this event, without the type name.
  String get detail {
    final buffer = StringBuffer('attempt: $attempt');

    if (step != null) {
      buffer.write(', step: ${step!.label}');
    }

    if (message != null) {
      buffer.write(', message: $message');
    }

    return buffer.toString();
  }

  @override
  List<Object?> get props => <Object?>[kind, failure, step, attempt, message];

  @override
  String toString() => 'RecoveryLadderEvent(${kind.name}, $detail)';
}

/// The ladder accepted a failure and started escalating.
final class RecoveryLadderStarted extends RecoveryLadderEvent {
  /// Creates a start event.
  const RecoveryLadderStarted({required RecoveryFailure failure, required this.plan})
    : super(kind: RecoveryLadderEventKind.started, failure: failure);

  /// Escalation order the ladder will follow.
  final List<RecoveryStepKind> plan;

  /// The plan as a readable chain.
  String get planLabel => plan.map((kind) => kind.name).join(' → ');

  @override
  List<Object?> get props => <Object?>[...super.props, plan];

  @override
  String toString() => 'RecoveryLadderStarted(plan: $planLabel, failure: $failure)';
}

/// The ladder is about to execute a step.
final class RecoveryLadderStepStarted extends RecoveryLadderEvent {
  /// Creates a step-start event.
  const RecoveryLadderStepStarted({required super.step, required super.attempt, super.failure})
    : super(kind: RecoveryLadderEventKind.stepStarted);

  @override
  String toString() => 'RecoveryLadderStepStarted(${step?.label}, attempt: $attempt)';
}

/// A step failed and the ladder moved on.
final class RecoveryLadderStepFailed extends RecoveryLadderEvent {
  /// Creates a step-failure event.
  const RecoveryLadderStepFailed({
    required super.step,
    required super.attempt,
    required super.failure,
    this.error,
    this.stackTrace,
  }) : super(kind: RecoveryLadderEventKind.stepFailed);

  /// Error thrown by the step, when one was thrown.
  final Object? error;

  /// Stack trace of [error].
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[...super.props, error];

  @override
  String toString() => 'RecoveryLadderStepFailed(${step?.label}, attempt: $attempt, error: $error)';
}

/// Recovery succeeded.
final class RecoveryLadderCompleted extends RecoveryLadderEvent {
  /// Creates a completion event.
  const RecoveryLadderCompleted({required super.step, required super.attempt, super.failure})
    : super(kind: RecoveryLadderEventKind.completed);

  @override
  String toString() => 'RecoveryLadderCompleted(${step?.label}, attempt: $attempt)';
}

/// Recovery ran out of steps.
final class RecoveryLadderExhausted extends RecoveryLadderEvent {
  /// Creates an exhaustion event.
  const RecoveryLadderExhausted({required super.attempt, required super.message, super.failure})
    : super(kind: RecoveryLadderEventKind.exhausted);

  @override
  String toString() => 'RecoveryLadderExhausted(attempt: $attempt, reason: $message)';
}

/// The run was stopped from the outside.
final class RecoveryLadderCancelled extends RecoveryLadderEvent {
  /// Creates a cancellation event.
  const RecoveryLadderCancelled({required super.attempt, required super.message, super.failure})
    : super(kind: RecoveryLadderEventKind.cancelled);

  @override
  String toString() => 'RecoveryLadderCancelled(attempt: $attempt, reason: $message)';
}
