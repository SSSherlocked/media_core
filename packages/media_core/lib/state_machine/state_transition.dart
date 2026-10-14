import 'package:media_core/state_machine/state.dart';
import 'package:media_core/state_machine/state_machine_context.dart';
import 'package:media_core/state_machine/state_machine_event.dart';

/// Defines a state transition rule.
///
/// A transition describes how a state machine moves
/// from one state to another when an event occurs.
///
/// Responsibilities:
///
/// - define source state
/// - define target state
/// - match incoming events
/// - validate transition conditions
/// - execute transition side effects
///
/// Does not:
///
/// - store current state
/// - manage transition queues
/// - update state machine lifecycle
/// - handle persistence
final class StateTransition<S extends StateMachineState> {
  /// Creates a state transition.
  const StateTransition({
    required this.from,
    required this.to,
    required this.eventId,
    this.guard,
    this.action,
    this.priority = 0,
  });

  /// State before transition.
  final S from;

  /// State after transition.
  final S to;

  /// Event identifier which triggers this transition.
  final String eventId;

  /// Optional transition guard.
  ///
  /// Returning `false` rejects this transition.
  final StateTransitionGuard<S>? guard;

  /// Optional transition action.
  ///
  /// Executed after guard succeeds and before
  /// state machine updates its current state.
  final StateTransitionAction<S>? action;

  /// Transition priority.
  ///
  /// Higher priority transitions are checked first.
  final int priority;

  /// Whether this transition matches
  /// current state and incoming event.
  bool matches(S state, StateMachineEvent event) {
    return state == from && event.id == eventId;
  }

  /// Executes transition guard.
  ///
  /// Returns `true` when transition is allowed.
  Future<bool> canExecute(StateMachineContext context, S state, StateMachineEvent event) {
    final currentGuard = guard;

    if (currentGuard == null) {
      return Future<bool>.value(true);
    }

    return currentGuard(context, state, event);
  }

  /// Executes transition action.
  ///
  /// The action is optional.
  Future<void> execute(StateMachineContext context, S state, StateMachineEvent event) async {
    final currentAction = action;

    if (currentAction == null) {
      return;
    }

    await currentAction(context, state, event);
  }

  @override
  String toString() {
    return 'StateTransition('
        'from=${from.id}, '
        'to=${to.id}, '
        'event=$eventId, '
        'priority=$priority'
        ')';
  }
}

/// Validates whether a transition can execute.
///
/// Parameters:
///
/// - [context] runtime execution context
/// - [state] current state
/// - [event] incoming event
typedef StateTransitionGuard<S extends StateMachineState> =
    Future<bool> Function(StateMachineContext context, S state, StateMachineEvent event);

/// Executes transition side effects.
///
/// Parameters:
///
/// - [context] runtime execution context
/// - [state] current state
/// - [event] incoming event
typedef StateTransitionAction<S extends StateMachineState> =
    Future<void> Function(StateMachineContext context, S state, StateMachineEvent event);
