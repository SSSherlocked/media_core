import 'package:clock/clock.dart';
import 'package:media_core/state_machine/state.dart';
import 'package:media_core/state_machine/state_machine_context.dart';
import 'package:media_core/state_machine/state_machine_event.dart';
import 'package:media_core/state_machine/state_transition.dart';
import 'package:media_core/state_machine/state_transition_result.dart';

/// Generic asynchronous state machine execution engine.
///
/// StateMachine is the core execution component of the
/// state machine architecture.
///
/// Responsibilities:
///
/// - hold current state
/// - find matching transitions
/// - execute transition guards
/// - execute transition actions
/// - update current state
///
/// Does not:
///
/// - manage event queues
/// - expose streams
/// - persist state
/// - manage lifecycle
/// - perform retry or recovery
///
/// These responsibilities belong to
/// StateMachineController and higher-level modules.
final class StateMachine<S extends StateMachineState> {
  /// Creates a state machine.
  ///
  /// [initialState] is the starting state.
  ///
  /// [transitions] defines all allowed state changes.
  StateMachine({required S initialState, required List<StateTransition<S>> transitions, StateMachineContext? context})
    : state = initialState,
      _transitions = List.unmodifiable(transitions),
      context = context ?? const StateMachineContext();

  /// Registered transitions.
  final List<StateTransition<S>> _transitions;

  /// Runtime execution context.
  final StateMachineContext context;

  /// Current state.
  ///
  /// Mutable on purpose: `machine.state = next` is how initialization, restore
  /// and recovery push a state in without playing a transition. Guarded event
  /// driven changes stay in [dispatch].
  S state;

  /// Returns current state identifier.
  String get stateId => state.id;

  /// Whether machine reached terminal state.
  bool get isTerminal => state.isTerminal;

  /// Returns all registered transitions.
  List<StateTransition<S>> get transitions => _transitions;

  /// Finds transitions matching current state and event.
  ///
  /// Multiple transitions may match.
  ///
  /// Higher priority transitions are returned first.
  List<StateTransition<S>> findTransitions(StateMachineEvent event) {
    final result = _transitions.where((transition) => transition.matches(state, event)).toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));

    return result;
  }

  /// Checks whether an event can be handled.
  Future<bool> canHandle(StateMachineEvent event) async {
    if (!state.acceptsEvents) {
      return false;
    }

    final candidates = findTransitions(event);

    for (final transition in candidates) {
      final allowed = await transition.canExecute(context, state, event);

      if (allowed) {
        return true;
      }
    }

    return false;
  }

  /// Dispatches an event to the state machine.
  ///
  /// Execution flow:
  ///
  /// 1. validate current state
  /// 2. find matching transitions
  /// 3. execute guards
  /// 4. execute action
  /// 5. update state
  /// 6. return execution result
  Future<StateTransitionResult<S>> dispatch(StateMachineEvent event) async {
    final start = clock.now();

    if (!state.acceptsEvents) {
      return StateTransitionResult.rejected(
        state: state,
        event: event,
        reason: 'State does not accept events',
        duration: clock.now().difference(start),
      );
    }

    if (isTerminal) {
      return StateTransitionResult.rejected(
        state: state,
        event: event,
        reason: 'State is terminal',
        duration: clock.now().difference(start),
      );
    }

    final candidates = findTransitions(event);

    if (candidates.isEmpty) {
      return StateTransitionResult.rejected(
        state: state,
        event: event,
        reason: 'No transition matches event',
        duration: clock.now().difference(start),
      );
    }

    for (final transition in candidates) {
      final allowed = await transition.canExecute(context, state, event);

      if (!allowed) {
        continue;
      }

      final previous = state;

      try {
        await transition.execute(context, state, event);

        state = transition.to;

        return StateTransitionResult.success(
          previous: previous,
          current: state,
          event: event,
          duration: clock.now().difference(start),
        );
      } on Object catch (error, stackTrace) {
        return StateTransitionResult.failed(
          state: previous,
          event: event,
          error: error,
          stackTrace: stackTrace,
          duration: clock.now().difference(start),
        );
      }
    }

    return StateTransitionResult.rejected(
      state: state,
      event: event,
      reason: 'All transition guards rejected',
      duration: clock.now().difference(start),
    );
  }

  /// Creates a new machine instance with another state.
  ///
  /// Used for:
  ///
  /// - rebuilding
  /// - restore
  /// - testing
  StateMachine<S> copyWithState(S state) {
    return StateMachine<S>(initialState: state, transitions: _transitions, context: context);
  }

  @override
  String toString() {
    // The state id already identifies the state type, so the description does
    // not need the runtime type of the machine.
    return 'StateMachine('
        'state=${state.id}, '
        'transitions=${_transitions.length}'
        ')';
  }
}
