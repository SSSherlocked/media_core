import 'package:clock/clock.dart';
import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/operation/operation_context.dart';
import 'package:media_core/operation/operation_state.dart';
import 'package:media_core/operation/operation_type.dart';
import 'package:meta/meta.dart';

/// Represents a single player operation.
///
/// An [Operation] describes the lifecycle state of a high-level player
/// operation. It does not execute the operation itself.
///
/// ```text
/// Operation
///    │
///    ├── OperationId
///    ├── OperationType
///    ├── OperationState
///    └── OperationContext
/// ```
///
/// Responsibilities:
///
/// - identify an operation;
/// - describe its type;
/// - track its lifecycle state;
/// - retain operation context;
/// - retain lifecycle timestamps.
///
/// This class does not:
///
/// - execute operations;
/// - schedule operations;
/// - retry operations;
/// - perform recovery;
/// - perform fallback;
/// - classify errors.
@immutable
final class Operation {
  /// Creates an operation.
  const Operation({
    required this.id,
    required this.type,
    this.state = OperationState.created,
    this.context,
    this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  /// Creates a newly created operation.
  const Operation.created({
    required OperationId id,
    required OperationType type,
    OperationContext? context,
    DateTime? createdAt,
  }) : this(id: id, type: type, state: OperationState.created, context: context, createdAt: createdAt);

  /// Creates a running operation.
  const Operation.running({
    required OperationId id,
    required OperationType type,
    OperationContext? context,
    DateTime? createdAt,
    DateTime? startedAt,
  }) : this(
         id: id,
         type: type,
         state: OperationState.running,
         context: context,
         createdAt: createdAt,
         startedAt: startedAt,
       );

  /// Creates a successfully completed operation.
  const Operation.completed({
    required OperationId id,
    required OperationType type,
    OperationContext? context,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) : this(
         id: id,
         type: type,
         state: OperationState.completed,
         context: context,
         createdAt: createdAt,
         startedAt: startedAt,
         completedAt: completedAt,
       );

  /// Creates a failed operation.
  const Operation.failed({
    required OperationId id,
    required OperationType type,
    OperationContext? context,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) : this(
         id: id,
         type: type,
         state: OperationState.failed,
         context: context,
         createdAt: createdAt,
         startedAt: startedAt,
         completedAt: completedAt,
       );

  /// Creates a cancelled operation.
  const Operation.cancelled({
    required OperationId id,
    required OperationType type,
    OperationContext? context,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) : this(
         id: id,
         type: type,
         state: OperationState.cancelled,
         context: context,
         createdAt: createdAt,
         startedAt: startedAt,
         completedAt: completedAt,
       );

  /// Unique identifier of this operation.
  final OperationId id;

  /// Type of this operation.
  final OperationType type;

  /// Current lifecycle state.
  final OperationState state;

  /// Optional contextual information.
  final OperationContext? context;

  /// Time when the operation was created.
  final DateTime? createdAt;

  /// Time when execution started.
  final DateTime? startedAt;

  /// Time when execution completed or terminated.
  final DateTime? completedAt;

  /// Whether execution has started.
  bool get hasStarted => startedAt != null;

  /// Whether the operation has completed execution.
  bool get hasCompleted => completedAt != null;

  /// Whether the operation is terminal.
  bool get isTerminal => state.isTerminal;

  /// Whether the operation is running.
  bool get isRunning => state.isRunning;

  /// Whether the operation completed successfully.
  bool get isCompleted => state.isCompleted;

  /// Whether the operation failed.
  bool get isFailed => state.isFailed;

  /// Whether the operation was cancelled.
  bool get isCancelled => state.isCancelled;

  /// Whether the operation has context.
  bool get hasContext => context != null;

  /// Whether the operation is still pending.
  bool get isPending => !isTerminal;

  /// Duration between execution start and completion.
  ///
  /// Returns `null` when either timestamp is unavailable.
  Duration? get duration {
    final started = startedAt;
    final completed = completedAt;

    if (started == null || completed == null) {
      return null;
    }

    return completed.difference(started);
  }

  /// Total lifetime of the operation.
  ///
  /// Returns `null` when [createdAt] or [completedAt] is unavailable.
  Duration? get lifetime {
    final created = createdAt;
    final completed = completedAt;

    if (created == null || completed == null) {
      return null;
    }

    return completed.difference(created);
  }

  /// Creates a copy with selected values replaced.
  ///
  /// Nullable fields cannot be explicitly cleared through this method.
  /// Use [clear] to clear nullable fields.
  Operation copyWith({
    OperationId? id,
    OperationType? type,
    OperationState? state,
    OperationContext? context,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return Operation(
      id: id ?? this.id,
      type: type ?? this.type,
      state: state ?? this.state,
      context: context ?? this.context,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// Creates a copy with selected nullable values cleared.
  Operation clear({bool context = false, bool createdAt = false, bool startedAt = false, bool completedAt = false}) {
    return Operation(
      id: id,
      type: type,
      state: state,
      context: context ? null : this.context,
      createdAt: createdAt ? null : this.createdAt,
      startedAt: startedAt ? null : this.startedAt,
      completedAt: completedAt ? null : this.completedAt,
    );
  }

  /// Starts the operation.
  ///
  /// Only a non-running, non-terminal operation may be started.
  Operation start({DateTime? startedAt}) {
    _validateTransition(OperationState.running);

    final timestamp = startedAt ?? clock.now();

    return Operation(
      id: id,
      type: type,
      state: OperationState.running,
      context: context,
      createdAt: createdAt ?? timestamp,
      startedAt: timestamp,
    );
  }

  /// Completes the operation successfully.
  Operation complete({DateTime? completedAt}) {
    _validateTransition(OperationState.completed);

    final timestamp = completedAt ?? clock.now();

    return Operation(
      id: id,
      type: type,
      state: OperationState.completed,
      context: context,
      createdAt: createdAt,
      startedAt: startedAt,
      completedAt: timestamp,
    );
  }

  /// Marks the operation as failed.
  Operation fail({DateTime? completedAt}) {
    _validateTransition(OperationState.failed);

    final timestamp = completedAt ?? clock.now();

    return Operation(
      id: id,
      type: type,
      state: OperationState.failed,
      context: context,
      createdAt: createdAt,
      startedAt: startedAt,
      completedAt: timestamp,
    );
  }

  /// Cancels the operation.
  Operation cancel({DateTime? completedAt}) {
    _validateTransition(OperationState.cancelled);

    final timestamp = completedAt ?? clock.now();

    return Operation(
      id: id,
      type: type,
      state: OperationState.cancelled,
      context: context,
      createdAt: createdAt,
      startedAt: startedAt,
      completedAt: timestamp,
    );
  }

  /// Returns a copy with an updated context.
  Operation withContext(OperationContext context) {
    return Operation(
      id: id,
      type: type,
      state: state,
      context: context,
      createdAt: createdAt,
      startedAt: startedAt,
      completedAt: completedAt,
    );
  }

  /// Removes the operation context.
  Operation withoutContext() {
    return Operation(
      id: id,
      type: type,
      state: state,
      createdAt: createdAt,
      startedAt: startedAt,
      completedAt: completedAt,
    );
  }

  /// Validates a lifecycle transition.
  void _validateTransition(OperationState target) {
    if (state.canTransitionTo(target)) {
      return;
    }

    throw StateError(
      'Invalid operation state transition: '
      '${state.value} -> ${target.value}.',
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Operation &&
            other.id == id &&
            other.type == type &&
            other.state == state &&
            other.context == context &&
            other.createdAt == createdAt &&
            other.startedAt == startedAt &&
            other.completedAt == completedAt;
  }

  @override
  int get hashCode {
    return Object.hash(id, type, state, context, createdAt, startedAt, completedAt);
  }

  @override
  String toString() {
    final buffer = StringBuffer('Operation(')
      ..write('id: ')
      ..write(id)
      ..write(', type: ')
      ..write(type)
      ..write(', state: ')
      ..write(state);

    final currentContext = context;

    if (currentContext != null) {
      buffer
        ..write(', context: ')
        ..write(currentContext);
    }

    final created = createdAt;

    if (created != null) {
      buffer
        ..write(', createdAt: ')
        ..write(created);
    }

    final started = startedAt;

    if (started != null) {
      buffer
        ..write(', startedAt: ')
        ..write(started);
    }

    final completed = completedAt;

    if (completed != null) {
      buffer
        ..write(', completedAt: ')
        ..write(completed);
    }

    final currentDuration = duration;

    if (currentDuration != null) {
      buffer
        ..write(', duration: ')
        ..write(currentDuration);
    }

    final currentLifetime = lifetime;

    if (currentLifetime != null) {
      buffer
        ..write(', lifetime: ')
        ..write(currentLifetime);
    }

    buffer.write(')');

    return buffer.toString();
  }
}
