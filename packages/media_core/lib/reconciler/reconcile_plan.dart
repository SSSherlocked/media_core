import 'package:equatable/equatable.dart';
import 'package:media_core/reconciler/reconcile_action.dart';

/// Describes a set of actions required
/// to reach desired state.
final class ReconcilePlan extends Equatable {
  /// Creates a plan from the given [actions].
  const ReconcilePlan({required this.actions});

  /// Creates a plan that requires no actions.
  factory ReconcilePlan.empty() {
    return const ReconcilePlan(actions: []);
  }

  /// The ordered actions needed to reach the desired state.
  final List<ReconcileAction> actions;

  /// Whether the plan requires no actions.
  bool get isEmpty {
    return actions.isEmpty;
  }

  /// Whether the plan requires at least one action.
  bool get isNotEmpty {
    return actions.isNotEmpty;
  }

  /// The number of actions in the plan.
  int get length {
    return actions.length;
  }

  /// Returns the action at [index].
  ReconcileAction operator [](int index) {
    return actions[index];
  }

  @override
  List<Object?> get props => [actions];

  @override
  String toString() {
    return 'ReconcilePlan(actions: $actions)';
  }
}
