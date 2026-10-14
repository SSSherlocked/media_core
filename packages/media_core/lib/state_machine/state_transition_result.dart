import 'package:equatable/equatable.dart';
import 'package:media_core/state_machine/state.dart';
import 'package:media_core/state_machine/state_machine_event.dart';

/// Result returned after executing a state transition.
///
/// A transition execution can have three outcomes:
///
/// - success
/// - rejected
/// - failed
///
/// StateMachine converts execution results into this object
/// instead of throwing transition errors to callers.
///
/// Responsibilities:
///
/// - describe transition outcome
/// - provide previous and current state
/// - expose execution diagnostics
///
/// Does not:
///
/// - retry transitions
/// - handle recovery
/// - modify machine state
final class StateTransitionResult<S extends StateMachineState> extends Equatable {
  const StateTransitionResult._({
    required this.status,
    required this.event,
    this.previous,
    this.current,
    this.reason,
    this.error,
    this.stackTrace,
    this.duration,
  });

  /// Creates a successful transition result.
  factory StateTransitionResult.success({
    required S previous,
    required S current,
    required StateMachineEvent event,
    Duration? duration,
  }) {
    return StateTransitionResult._(
      status: StateTransitionStatus.success,
      previous: previous,
      current: current,
      event: event,
      duration: duration,
    );
  }

  /// Creates a rejected transition result.
  ///
  /// A transition can be rejected when:
  ///
  /// - no matching transition exists
  /// - guard returns false
  /// - state does not accept events
  factory StateTransitionResult.rejected({
    required S state,
    required StateMachineEvent event,
    required String reason,
    Duration? duration,
  }) {
    return StateTransitionResult._(
      status: StateTransitionStatus.rejected,
      previous: state,
      current: state,
      event: event,
      reason: reason,
      duration: duration,
    );
  }

  /// Creates a failed transition result.
  ///
  /// A failure means transition execution threw an error.
  factory StateTransitionResult.failed({
    required S state,
    required StateMachineEvent event,
    required Object error,
    StackTrace? stackTrace,
    Duration? duration,
  }) {
    return StateTransitionResult._(
      status: StateTransitionStatus.failed,
      previous: state,
      current: state,
      event: event,
      error: error,
      stackTrace: stackTrace,
      duration: duration,
    );
  }

  /// Transition execution status.
  final StateTransitionStatus status;

  /// State before transition.
  final S? previous;

  /// State after transition.
  final S? current;

  /// Event which triggered transition.
  final StateMachineEvent event;

  /// Rejection reason.
  final String? reason;

  /// Execution error.
  final Object? error;

  /// Error stack trace.
  final StackTrace? stackTrace;

  /// Time spent executing transition.
  final Duration? duration;

  /// Whether transition succeeded.
  bool get isSuccess {
    return status == StateTransitionStatus.success;
  }

  /// Whether transition was rejected.
  bool get isRejected {
    return status == StateTransitionStatus.rejected;
  }

  /// Whether transition failed.
  bool get isFailed {
    return status == StateTransitionStatus.failed;
  }

  /// Whether state changed.
  bool get changed {
    return previous != current;
  }

  @override
  List<Object?> get props => [status, previous, current, event, reason, error, stackTrace, duration];

  @override
  String toString() {
    return 'StateTransitionResult('
        'status=$status, '
        'previous=$previous, '
        'current=$current, '
        'event=$event'
        ')';
  }
}

/// State transition execution status.
enum StateTransitionStatus {
  /// Transition completed successfully.
  success,

  /// Transition was rejected and not executed.
  rejected,

  /// Transition execution failed.
  failed,
}
