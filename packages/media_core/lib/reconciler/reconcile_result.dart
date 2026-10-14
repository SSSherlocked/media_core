import 'package:equatable/equatable.dart';
import 'package:media_core/reconciler/reconcile_plan.dart';

/// The outcome category of a reconciliation evaluation.
enum ReconcileResultType {
  /// Nothing to do: the plan was empty.
  noop,

  /// The plan still needs to be executed.
  pending,

  /// The plan finished successfully.
  completed,

  /// The plan finished with an error.
  failed,
}

/// The result of evaluating a [ReconcilePlan].
final class ReconcileResult extends Equatable {
  const ReconcileResult._({required this.type, this.plan, this.error});

  /// Creates a result for an empty plan that requires no action.
  factory ReconcileResult.noop() {
    return const ReconcileResult._(type: ReconcileResultType.noop);
  }

  /// Creates a result carrying the [plan] still to be executed.
  factory ReconcileResult.pending(ReconcilePlan plan) {
    return ReconcileResult._(type: ReconcileResultType.pending, plan: plan);
  }

  /// Creates a result for a plan that completed successfully.
  factory ReconcileResult.completed() {
    return const ReconcileResult._(type: ReconcileResultType.completed);
  }

  /// Creates a result for a plan that failed with [error].
  factory ReconcileResult.failed(Object error) {
    return ReconcileResult._(type: ReconcileResultType.failed, error: error);
  }

  /// The outcome category this result falls under.
  final ReconcileResultType type;

  /// The plan associated with the result, when one exists.
  final ReconcilePlan? plan;

  /// The error that caused the failure, when [type] is [ReconcileResultType.failed].
  final Object? error;

  /// Whether the reconciliation required no action.
  bool get isNoop => type == ReconcileResultType.noop;

  /// Whether the plan is still awaiting execution.
  bool get isPending => type == ReconcileResultType.pending;

  /// Whether the plan completed successfully.
  bool get isCompleted => type == ReconcileResultType.completed;

  /// Whether the plan failed.
  bool get isFailed => type == ReconcileResultType.failed;

  @override
  List<Object?> get props => [type, plan, error];
}
