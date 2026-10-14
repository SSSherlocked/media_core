import 'package:media_core/task/task_state.dart' show TaskState;
import 'package:meta/meta.dart';

/// Describes the lifecycle state of an operation.
///
/// [OperationState] is an immutable value object rather than a Dart enum.
/// Built-in states provide the standard operation lifecycle while custom
/// states allow extensions without changing this class.
///
/// Operation state describes **where an operation is in its lifecycle**.
///
/// Scheduling states such as `queued` belong to [TaskState], because task
/// scheduling and operation lifecycle are intentionally separated.
///
/// Standard lifecycle:
///
/// ```text
/// created
///    │
///    ├── running
///    │      ├── completed
///    │      ├── failed
///    │      └── cancelled
///    │
///    └── cancelled
/// ```
///
/// Terminal states cannot transition to another state.
@immutable
final class OperationState implements Comparable<OperationState> {
  /// Creates a state from JSON.
  ///
  /// Unknown values are represented as custom states.
  factory OperationState.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('OperationState JSON value must be a String.');
    }

    return OperationState.fromValue(json);
  }

  /// Creates a state from its stable string value.
  ///
  /// Built-in values return their canonical instances.
  /// Unknown values become custom states.
  factory OperationState.fromValue(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Operation state cannot be empty.');
    }

    for (final state in values) {
      if (state.value == normalized) {
        return state;
      }
    }

    return OperationState.custom(normalized);
  }
  const OperationState._(this.value, this.name);

  /// Creates a custom operation state.
  ///
  /// Custom values are normalized by trimming leading and trailing
  /// whitespace.
  ///
  /// An empty value is not allowed.
  factory OperationState.custom(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Operation state cannot be empty.');
    }

    return OperationState._(normalized, normalized);
  }

  /// Parses an operation state from a string.
  factory OperationState.parse(String value) = OperationState.fromValue;

  // ---------------------------------------------------------------------------
  // Built-in states
  // ---------------------------------------------------------------------------

  /// Operation has been created but has not started.
  static const OperationState created = OperationState._('created', 'Created');

  /// Operation is currently executing.
  static const OperationState running = OperationState._('running', 'Running');

  /// Operation completed successfully.
  static const OperationState completed = OperationState._('completed', 'Completed');

  /// Operation failed.
  static const OperationState failed = OperationState._('failed', 'Failed');

  /// Operation was cancelled.
  static const OperationState cancelled = OperationState._('cancelled', 'Cancelled');

  // ---------------------------------------------------------------------------
  // Built-in values
  // ---------------------------------------------------------------------------

  static const Set<String> _builtInValues = <String>{'created', 'running', 'completed', 'failed', 'cancelled'};

  /// All built-in operation states.
  static const List<OperationState> values = <OperationState>[created, running, completed, failed, cancelled];

  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------

  /// Stable machine-readable state value.
  final String value;

  /// Human-readable state name.
  final String name;

  /// Whether this is one of the built-in states.
  bool get isBuiltIn => _builtInValues.contains(value);

  /// Whether this is a custom state.
  bool get isCustom => !isBuiltIn;

  /// Whether this state is the initial operation state.
  bool get isCreated => value == created.value;

  /// Whether this operation is currently running.
  bool get isRunning => value == running.value;

  /// Whether this operation completed successfully.
  bool get isCompleted => value == completed.value;

  /// Whether this operation failed.
  bool get isFailed => value == failed.value;

  /// Whether this operation was cancelled.
  bool get isCancelled => value == cancelled.value;

  /// Whether this is a terminal state.
  ///
  /// Terminal states:
  ///
  /// - completed
  /// - failed
  /// - cancelled
  bool get isTerminal {
    return isCompleted || isFailed || isCancelled;
  }

  /// Whether this state represents an operation that has not started.
  bool get isPending => isCreated;

  /// Whether this state represents an actively executing operation.
  bool get isActive => isRunning;

  /// Whether this operation completed successfully.
  bool get isSuccess => isCompleted;

  /// Whether this operation ended unsuccessfully.
  ///
  /// Cancellation is intentionally treated separately from failure.
  bool get isFailure => isFailed;

  /// Whether this state can be cancelled.
  bool get canCancel {
    return isCreated || isRunning;
  }

  /// Whether this state can be started.
  bool get canStart => isCreated;

  /// Whether this state can be completed.
  bool get canComplete => isRunning;

  /// Whether this state can be failed.
  bool get canFail => isRunning;

  // ---------------------------------------------------------------------------
  // Transition graph
  // ---------------------------------------------------------------------------

  /// Returns all legal next states from this state.
  ///
  /// The lifecycle graph is:
  ///
  /// ```text
  /// created -> running
  /// created -> cancelled
  ///
  /// running -> completed
  /// running -> failed
  /// running -> cancelled
  ///
  /// completed -> none
  /// failed    -> none
  /// cancelled -> none
  /// ```
  List<OperationState> get nextStates {
    if (isCreated) {
      return const <OperationState>[running, cancelled];
    }

    if (isRunning) {
      return const <OperationState>[completed, failed, cancelled];
    }

    return const <OperationState>[];
  }

  /// Returns whether this state can transition to [target].
  bool canTransitionTo(OperationState target) {
    if (this == target) {
      return false;
    }

    return nextStates.contains(target);
  }

  /// Validates a transition to [target].
  ///
  /// Throws [StateError] when the transition is not legal.
  void validateTransitionTo(OperationState target) {
    if (!canTransitionTo(target)) {
      throw StateError(
        'Invalid operation state transition: '
        '$value -> ${target.value}.',
      );
    }
  }

  /// Returns whether this state has [target] as a legal next state.
  bool hasNextState(OperationState target) {
    return nextStates.contains(target);
  }

  /// Returns whether [target] is a valid terminal state.
  static bool isValidTerminalState(OperationState target) {
    return target.isCompleted || target.isFailed || target.isCancelled;
  }

  /// Returns whether this state can transition to a terminal state.
  bool get canTerminate => isRunning;

  // ---------------------------------------------------------------------------
  // Conversion
  // ---------------------------------------------------------------------------

  /// Returns the stable state value.
  String toValue() => value;

  /// Returns the stable state value for JSON serialization.
  String toJson() => value;

  /// Returns whether [value] is a valid operation state.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Returns whether [value] represents a built-in state.
  static bool isBuiltInValue(String value) {
    return _builtInValues.contains(value.trim());
  }

  /// Attempts to parse an operation state.
  ///
  /// Returns `null` when [value] is empty.
  static OperationState? tryParse(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return OperationState.fromValue(normalized);
  }

  // ---------------------------------------------------------------------------
  // Value helpers
  // ---------------------------------------------------------------------------

  /// Creates a custom state with [value].
  ///
  /// This method intentionally creates a custom value instead of attempting
  /// to return a built-in singleton.
  ///
  /// Use [OperationState.fromValue] when canonical built-in values are desired.
  OperationState copyWith(String value) {
    return OperationState.custom(value);
  }

  /// Returns whether this state has the same value as [other].
  bool isSameAs(OperationState other) {
    return this == other;
  }

  /// Returns whether this state has a different value from [other].
  bool isDifferentFrom(OperationState other) {
    return this != other;
  }

  // ---------------------------------------------------------------------------
  // Comparable / equality
  // ---------------------------------------------------------------------------

  @override
  int compareTo(OperationState other) {
    return value.compareTo(other.value);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is OperationState && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    return 'OperationState($value)';
  }
}
