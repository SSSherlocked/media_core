import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/state_machine/state_transition.dart' show StateTransition;

/// Base abstraction for state machine events.
///
/// An event represents an external or internal signal
/// that may cause a state transition.
///
/// StateMachine does not understand event meaning.
/// Domain modules define concrete events.
///
/// Responsibilities:
///
/// - provide stable event identity
/// - carry optional event payload
/// - provide diagnostic information
///
/// Does not:
///
/// - perform state changes
/// - execute business logic
/// - manage event queues
abstract class StateMachineEvent extends Equatable {
  /// Creates a state machine event.
  const StateMachineEvent();

  /// Stable event identifier.
  ///
  /// Used by [StateTransition] to match
  /// an incoming event.
  String get id;

  /// Human readable event name.
  ///
  /// Defaults to [id].
  String get name => id;

  /// Optional event payload.
  ///
  /// Domain modules may attach additional
  /// immutable data required by transitions.
  Map<String, Object?> get payload => const {};

  /// Event processing priority.
  ///
  /// Higher priority events may be processed
  /// before lower priority events by controllers.
  int get priority => 0;

  /// Whether this event is generated internally.
  ///
  /// Examples:
  ///
  /// - decoder initialized
  /// - buffering completed
  /// - backend failure
  bool get internal => false;

  /// Whether this event may be skipped
  /// when the machine is busy.
  bool get skippable => false;

  /// Event source identifier.
  ///
  /// Examples:
  ///
  /// - user
  /// - backend
  /// - network
  /// - lifecycle
  String get source => 'unknown';

  /// Event creation timestamp.
  ///
  /// Override in tests to provide deterministic time.
  DateTime get timestamp => clock.now();

  /// Diagnostic event name.
  String get diagnosticName => runtimeType.toString();

  @override
  List<Object?> get props => [id, payload, priority, internal, skippable, source, timestamp];

  @override
  String toString() {
    return '$runtimeType('
        'id=$id, '
        'source=$source, '
        'priority=$priority'
        ')';
  }
}
