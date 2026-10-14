import 'dart:async';
import 'dart:collection';

import 'package:media_core/state_machine/state.dart';
import 'package:media_core/state_machine/state_machine.dart';
import 'package:media_core/state_machine/state_machine_context.dart';
import 'package:media_core/state_machine/state_machine_event.dart';
import 'package:media_core/state_machine/state_transition_result.dart';

/// Runtime controller for a StateMachine.
///
/// StateMachineController is the lifecycle and execution
/// coordinator around the pure StateMachine engine.
///
/// Responsibilities:
///
/// - serialize event execution
/// - maintain pending event queue
/// - expose transition result stream
/// - coordinate asynchronous dispatch
/// - manage controller lifecycle
///
/// Does not:
///
/// - define state transition rules
/// - contain domain business logic
/// - replace StateMachine
/// - persist state
/// - implement retry policy
///
/// StateMachine owns transition execution.
/// Controller owns runtime orchestration.
final class StateMachineController<S extends StateMachineState> {
  /// Creates a state machine controller.
  StateMachineController({required StateMachine<S> machine, StateMachineContext? context})
    : _machine = machine,
      _context = context ?? machine.context;

  /// Underlying state machine engine.
  final StateMachine<S> _machine;

  /// Runtime execution context.
  final StateMachineContext _context;

  /// Pending event queue.
  final Queue<_PendingDispatch<S>> _queue = Queue<_PendingDispatch<S>>();

  /// Transition result stream.
  final StreamController<StateTransitionResult<S>> _resultController =
      StreamController<StateTransitionResult<S>>.broadcast();

  /// Whether events are currently being processed.
  bool _processing = false;

  /// Whether controller has been disposed.
  bool _disposed = false;

  /// Current machine state.
  S get state => _machine.state;

  /// Current state identifier.
  String get stateId => _machine.stateId;

  /// Runtime execution context.
  StateMachineContext get context => _context;

  /// Whether controller is processing events.
  bool get processing => _processing;

  /// Whether controller has been disposed.
  bool get disposed => _disposed;

  /// Number of queued events.
  int get queueLength => _queue.length;

  /// Stream of transition results.
  ///
  /// Every dispatched event produces one result.
  Stream<StateTransitionResult<S>> get results => _resultController.stream;

  /// Dispatches an event.
  ///
  /// Events are queued and processed sequentially.
  ///
  /// The controller guarantees that only one event
  /// is executing at a time.
  ///
  /// The returned future completes when *this* event has been handled, not
  /// when the queue happens to be free, so two overlapping dispatches cannot
  /// both resolve while the second event is still waiting.
  Future<void> dispatch(StateMachineEvent event) {
    if (_disposed) {
      return Future<void>.value();
    }

    final pending = _PendingDispatch<S>(event);

    _queue.add(pending);

    unawaited(_processQueue());

    return pending.done;
  }

  /// Processes pending events.
  ///
  /// Internal serial execution loop.
  Future<void> _processQueue() async {
    if (_processing) {
      return;
    }

    _processing = true;

    try {
      while (_queue.isNotEmpty) {
        final pending = _queue.removeFirst();

        try {
          final result = await _machine.dispatch(pending.event);

          if (!_resultController.isClosed) {
            _resultController.add(result);
          }

          pending.complete();
        } on Object catch (error, stackTrace) {
          // A throwing guard or action must not strand the rest of the queue,
          // and the caller of this event still needs an answer.
          pending.completeError(error, stackTrace);
        }
      }
    } finally {
      _processing = false;
    }
  }

  /// Checks whether an event can currently execute.
  Future<bool> canHandle(StateMachineEvent event) {
    if (_disposed) {
      return Future.value(false);
    }

    return _machine.canHandle(event);
  }

  /// Forces current machine state.
  ///
  /// Intended for:
  ///
  /// - initialization
  /// - restore
  /// - testing
  void setState(S state) {
    if (_disposed) {
      return;
    }

    _machine.state = state;
  }

  /// Removes all pending events.
  ///
  /// The dropped events produce no result; the dispatch futures that were
  /// waiting on them are completed instead of hanging forever.
  void clearQueue() {
    while (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    }
  }

  /// Disposes controller resources.
  ///
  /// After disposal:
  ///
  /// - events are ignored
  /// - result stream is closed
  /// - queue is cleared
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    clearQueue();

    await _resultController.close();
  }

  @override
  String toString() {
    return 'StateMachineController('
        'state=${state.id}, '
        'queue=${_queue.length}, '
        'processing=$_processing, '
        'disposed=$_disposed'
        ')';
  }
}

/// Event waiting for its turn in the controller queue.
///
/// The entry owns the dispatch future so the caller observes the handling of
/// its own event rather than the state of the shared queue.
final class _PendingDispatch<S extends StateMachineState> {
  _PendingDispatch(this.event);

  final StateMachineEvent event;

  final Completer<void> _done = Completer<void>();

  Future<void> get done => _done.future;

  void complete() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!_done.isCompleted) {
      _done.completeError(error, stackTrace);
    }
  }
}
