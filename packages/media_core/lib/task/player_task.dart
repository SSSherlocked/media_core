import 'package:clock/clock.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/identity_json_converters.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/operation/operation_context.dart';
import 'package:media_core/task/library.dart' show TaskManager, TaskScheduler;
import 'package:media_core/task/task_context.dart';
import 'package:media_core/task/task_id.dart';
import 'package:media_core/task/task_json_converters.dart';
import 'package:media_core/task/task_priority.dart';
import 'package:media_core/task/task_state.dart';
import 'package:media_core/task/task_type.dart';

part 'player_task.freezed.dart';
part 'player_task.g.dart';

/// Describes a player task that can be queued, scheduled, and executed.
///
/// [PlayerTask] is an immutable task descriptor and lifecycle snapshot.
///
/// It intentionally does not execute asynchronous work itself. Execution is
/// owned by higher-level task components such as [TaskScheduler] and
/// [TaskManager].
///
/// Typical lifecycle:
///
/// ```text
/// created
///    │
///    ▼
/// queued
///    │
///    ▼
/// running
///   /   \
///  ▼     ▼
/// completed failed
///     \   /
///    cancelled
/// ```
///
/// The task layer is intentionally separate from the operation layer:
///
/// ```text
/// Operation
///     │
///     └── describes a logical operation
///
/// PlayerTask
///     │
///     └── describes schedulable work
/// ```
@freezed
abstract class PlayerTask with _$PlayerTask {
  /// Creates a player task.
  const factory PlayerTask({
    /// Unique task identity.
    @TaskIdJsonConverter() required TaskId id,

    /// Type of work represented by this task.
    @TaskTypeJsonConverter() required TaskType type,

    /// Current lifecycle state.
    @TaskStateJsonConverter() @Default(TaskState.created) TaskState state,

    /// Scheduling priority.
    @TaskPriorityJsonConverter() @Default(TaskPriority.normal) TaskPriority priority,

    /// Task-specific execution context.
    TaskContext? context,

    /// Operation context associated with this task.
    ///
    /// The task may carry operation-level identity, but it does not own
    /// operation lifecycle management.
    @OperationContextJsonConverter() OperationContext? operationContext,

    /// PlayerIdentity associated with this task.
    @PlayerIdJsonConverter() PlayerId? playerId,

    /// Request associated with this task.
    @RequestIdJsonConverter() RequestId? requestId,

    /// Generation associated with this task.
    ///
    /// Generation identity is used to prevent stale work from affecting a
    /// newer playback generation.
    @GenerationIdJsonConverter() GenerationId? generationId,

    /// Time at which the task was created.
    DateTime? createdAt,

    /// Time at which the task entered the queue.
    DateTime? queuedAt,

    /// Time at which execution started.
    DateTime? startedAt,

    /// Time at which the task reached a terminal state.
    DateTime? completedAt,

    /// Failure associated with the task, when available.
    Object? error,

    /// Result produced by the task, when available.
    Object? result,
  }) = _PlayerTask;

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Creates a task from JSON.
  factory PlayerTask.fromJson(Map<String, dynamic> json) => _$PlayerTaskFromJson(json);
  const PlayerTask._();

  // ---------------------------------------------------------------------------
  // Factory constructors
  // ---------------------------------------------------------------------------

  /// Creates a newly created task.
  ///
  /// This is equivalent to creating a [PlayerTask] with
  /// [TaskState.created].
  factory PlayerTask.created({
    required TaskId id,
    required TaskType type,
    TaskPriority priority = TaskPriority.normal,
    TaskContext? context,
    OperationContext? operationContext,
    PlayerId? playerId,
    RequestId? requestId,
    GenerationId? generationId,
    DateTime? createdAt,
  }) {
    return PlayerTask(
      id: id,
      type: type,
      priority: priority,
      context: context,
      operationContext: operationContext,
      playerId: playerId,
      requestId: requestId,
      generationId: generationId,
      createdAt: createdAt ?? clock.now(),
    );
  }

  /// Creates a queued task.
  factory PlayerTask.queued({
    required TaskId id,
    required TaskType type,
    TaskPriority priority = TaskPriority.normal,
    TaskContext? context,
    OperationContext? operationContext,
    PlayerId? playerId,
    RequestId? requestId,
    GenerationId? generationId,
    DateTime? createdAt,
    DateTime? queuedAt,
  }) {
    final now = clock.now();

    return PlayerTask(
      id: id,
      type: type,
      state: TaskState.queued,
      priority: priority,
      context: context,
      operationContext: operationContext,
      playerId: playerId,
      requestId: requestId,
      generationId: generationId,
      createdAt: createdAt ?? now,
      queuedAt: queuedAt ?? now,
    );
  }

  /// Creates a running task.
  factory PlayerTask.running({
    required TaskId id,
    required TaskType type,
    TaskPriority priority = TaskPriority.normal,
    TaskContext? context,
    OperationContext? operationContext,
    PlayerId? playerId,
    RequestId? requestId,
    GenerationId? generationId,
    DateTime? createdAt,
    DateTime? queuedAt,
    DateTime? startedAt,
  }) {
    final now = clock.now();

    return PlayerTask(
      id: id,
      type: type,
      state: TaskState.running,
      priority: priority,
      context: context,
      operationContext: operationContext,
      playerId: playerId,
      requestId: requestId,
      generationId: generationId,
      createdAt: createdAt ?? now,
      queuedAt: queuedAt,
      startedAt: startedAt ?? now,
    );
  }

  /// Creates a completed task.
  factory PlayerTask.completed({
    required TaskId id,
    required TaskType type,
    TaskPriority priority = TaskPriority.normal,
    TaskContext? context,
    OperationContext? operationContext,
    PlayerId? playerId,
    RequestId? requestId,
    GenerationId? generationId,
    DateTime? createdAt,
    DateTime? queuedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    Object? result,
  }) {
    return PlayerTask(
      id: id,
      type: type,
      state: TaskState.completed,
      priority: priority,
      context: context,
      operationContext: operationContext,
      playerId: playerId,
      requestId: requestId,
      generationId: generationId,
      createdAt: createdAt ?? clock.now(),
      queuedAt: queuedAt,
      startedAt: startedAt,
      completedAt: completedAt ?? clock.now(),
      result: result,
    );
  }

  /// Creates a failed task.
  factory PlayerTask.failed({
    required TaskId id,
    required TaskType type,
    TaskPriority priority = TaskPriority.normal,
    TaskContext? context,
    OperationContext? operationContext,
    PlayerId? playerId,
    RequestId? requestId,
    GenerationId? generationId,
    DateTime? createdAt,
    DateTime? queuedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    Object? error,
  }) {
    return PlayerTask(
      id: id,
      type: type,
      state: TaskState.failed,
      priority: priority,
      context: context,
      operationContext: operationContext,
      playerId: playerId,
      requestId: requestId,
      generationId: generationId,
      createdAt: createdAt ?? clock.now(),
      queuedAt: queuedAt,
      startedAt: startedAt,
      completedAt: completedAt ?? clock.now(),
      error: error,
    );
  }

  /// Creates a cancelled task.
  factory PlayerTask.cancelled({
    required TaskId id,
    required TaskType type,
    TaskPriority priority = TaskPriority.normal,
    TaskContext? context,
    OperationContext? operationContext,
    PlayerId? playerId,
    RequestId? requestId,
    GenerationId? generationId,
    DateTime? createdAt,
    DateTime? queuedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    Object? error,
  }) {
    return PlayerTask(
      id: id,
      type: type,
      state: TaskState.cancelled,
      priority: priority,
      context: context,
      operationContext: operationContext,
      playerId: playerId,
      requestId: requestId,
      generationId: generationId,
      createdAt: createdAt ?? clock.now(),
      queuedAt: queuedAt,
      startedAt: startedAt,
      completedAt: completedAt ?? clock.now(),
      error: error,
    );
  }

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  /// Whether the task has a player identity.
  bool get hasPlayerId => playerId != null;

  /// Whether the task has a request identity.
  bool get hasRequestId => requestId != null;

  /// Whether the task has a generation identity.
  bool get hasGenerationId => generationId != null;

  /// Whether task execution metadata contains at least one identity.
  bool get hasIdentity {
    return hasPlayerId || hasRequestId || hasGenerationId;
  }

  // ---------------------------------------------------------------------------
  // Context
  // ---------------------------------------------------------------------------

  /// Whether a task context is available.
  bool get hasContext => context != null;

  /// Whether an operation context is available.
  bool get hasOperationContext => operationContext != null;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// Whether this task is newly created.
  bool get isCreated => state.isCreated;

  /// Whether this task is queued.
  bool get isQueued => state.isQueued;

  /// Whether this task is currently running.
  bool get isRunning => state.isRunning;

  /// Whether this task completed successfully.
  bool get isCompleted => state.isCompleted;

  /// Whether this task failed.
  bool get isFailed => state.isFailed;

  /// Whether this task was cancelled.
  bool get isCancelled => state.isCancelled;

  /// Whether this task has reached a terminal state.
  bool get isTerminal => state.isTerminal;

  /// Whether this task is still eligible for execution.
  bool get isPending => state.isPending;

  /// Whether this task is actively executing.
  bool get isActive => state.isActive;

  /// Whether this task has an error.
  bool get hasError => error != null;

  /// Whether this task has a result.
  bool get hasResult => result != null;

  // ---------------------------------------------------------------------------
  // Timing
  // ---------------------------------------------------------------------------

  /// Whether task creation time is available.
  bool get hasCreatedAt => createdAt != null;

  /// Whether the task has entered the queue.
  bool get hasQueuedAt => queuedAt != null;

  /// Whether execution has started.
  bool get hasStarted => startedAt != null;

  /// Whether completion time is available.
  bool get hasCompletedAt => completedAt != null;

  /// Time spent waiting in the queue.
  ///
  /// Returns `null` when either [queuedAt] or [startedAt] is unavailable.
  Duration? get queueDuration {
    final queued = queuedAt;
    final started = startedAt;

    if (queued == null || started == null) {
      return null;
    }

    final duration = started.difference(queued);

    return duration.isNegative ? Duration.zero : duration;
  }

  /// Execution duration of the task.
  ///
  /// When the task is still running, the current clock time is used.
  ///
  /// Returns `null` when execution has not started.
  Duration? get executionDuration {
    final started = startedAt;

    if (started == null) {
      return null;
    }

    final end = completedAt ?? clock.now();
    final duration = end.difference(started);

    return duration.isNegative ? Duration.zero : duration;
  }

  /// Total lifetime from creation until completion or now.
  ///
  /// Returns `null` when [createdAt] is unavailable.
  Duration? get lifetime {
    final created = createdAt;

    if (created == null) {
      return null;
    }

    final end = completedAt ?? clock.now();
    final duration = end.difference(created);

    return duration.isNegative ? Duration.zero : duration;
  }

  // ---------------------------------------------------------------------------
  // State transitions
  // ---------------------------------------------------------------------------

  /// Creates a copy with the task moved to the queued state.
  ///
  /// Throws [StateError] when the transition is invalid.
  PlayerTask queue({DateTime? queuedAt}) {
    _validateTransition(TaskState.queued);

    return copyWith(state: TaskState.queued, queuedAt: queuedAt ?? clock.now());
  }

  /// Creates a copy with the task moved to the running state.
  ///
  /// Throws [StateError] when the transition is invalid.
  PlayerTask start({DateTime? startedAt}) {
    _validateTransition(TaskState.running);

    return copyWith(state: TaskState.running, startedAt: startedAt ?? clock.now());
  }

  /// Creates a copy with the task marked as completed.
  ///
  /// The task result replaces the previous result.
  ///
  /// By default, an existing error is cleared.
  PlayerTask complete({Object? result, DateTime? completedAt, bool clearError = true}) {
    _validateTransition(TaskState.completed);

    return copyWith(
      state: TaskState.completed,
      result: result,
      completedAt: completedAt ?? clock.now(),
      error: clearError ? null : error,
    );
  }

  /// Creates a copy with the task marked as failed.
  ///
  /// The task error replaces the previous error.
  ///
  /// By default, an existing result is cleared.
  PlayerTask fail({Object? error, DateTime? completedAt, bool clearResult = true}) {
    _validateTransition(TaskState.failed);

    return copyWith(
      state: TaskState.failed,
      error: error,
      completedAt: completedAt ?? clock.now(),
      result: clearResult ? null : result,
    );
  }

  /// Creates a copy with the task marked as cancelled.
  ///
  /// By default, an existing result is cleared.
  PlayerTask cancel({Object? error, DateTime? completedAt, bool clearResult = true}) {
    _validateTransition(TaskState.cancelled);

    return copyWith(
      state: TaskState.cancelled,
      error: error,
      completedAt: completedAt ?? clock.now(),
      result: clearResult ? null : result,
    );
  }

  void _validateTransition(TaskState nextState) {
    if (!state.canTransitionTo(nextState)) {
      throw StateError(
        'Invalid task state transition: '
        '${state.value} -> ${nextState.value}.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Metadata
  // ---------------------------------------------------------------------------

  /// Removes all optional execution metadata from this task.
  PlayerTask clearMetadata() {
    return copyWith(context: null, operationContext: null, playerId: null, requestId: null, generationId: null);
  }

  // ---------------------------------------------------------------------------
  // Context helpers
  // ---------------------------------------------------------------------------

  /// Replaces the task context.
  PlayerTask withContext(TaskContext context) {
    return copyWith(context: context);
  }

  /// Removes the task context.
  PlayerTask withoutContext() {
    return copyWith(context: null);
  }

  /// Replaces the operation context.
  PlayerTask withOperationContext(OperationContext context) {
    return copyWith(operationContext: context);
  }

  /// Removes the operation context.
  PlayerTask withoutOperationContext() {
    return copyWith(operationContext: null);
  }

  // ---------------------------------------------------------------------------
  // Identity helpers
  // ---------------------------------------------------------------------------

  /// Associates this task with [playerId].
  PlayerTask withPlayerId(PlayerId playerId) {
    return copyWith(playerId: playerId);
  }

  /// Removes the player identity.
  PlayerTask withoutPlayerId() {
    return copyWith(playerId: null);
  }

  /// Associates this task with [requestId].
  PlayerTask withRequestId(RequestId requestId) {
    return copyWith(requestId: requestId);
  }

  /// Removes the request identity.
  PlayerTask withoutRequestId() {
    return copyWith(requestId: null);
  }

  /// Associates this task with [generationId].
  PlayerTask withGenerationId(GenerationId generationId) {
    return copyWith(generationId: generationId);
  }

  /// Removes the generation identity.
  PlayerTask withoutGenerationId() {
    return copyWith(generationId: null);
  }

  // ---------------------------------------------------------------------------
  // Result / error helpers
  // ---------------------------------------------------------------------------

  /// Replaces the task result and clears the error.
  PlayerTask withResult(Object? result) {
    return copyWith(result: result, error: null);
  }

  /// Removes the task result.
  PlayerTask withoutResult() {
    return copyWith(result: null);
  }

  /// Replaces the task error and clears the result.
  PlayerTask withError(Object? error) {
    return copyWith(error: error, result: null);
  }

  /// Removes the task error.
  PlayerTask withoutError() {
    return copyWith(error: null);
  }
}
