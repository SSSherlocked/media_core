import 'package:media_core/reconciler/reconcile_plan.dart';

/// Queue of reconcile plans.
final class ReconcileQueue {
  final List<ReconcilePlan> _queue = [];

  /// Whether the queue holds no plans.
  bool get isEmpty => _queue.isEmpty;

  /// Whether the queue holds at least one plan.
  bool get isNotEmpty => _queue.isNotEmpty;

  /// The number of queued plans.
  int get length => _queue.length;

  /// Appends [plan], ignoring it when it is empty.
  void add(ReconcilePlan plan) {
    if (plan.isEmpty) {
      return;
    }

    _queue.add(plan);
  }

  /// Removes and returns the oldest queued plan, or `null` when empty.
  ReconcilePlan? poll() {
    if (_queue.isEmpty) {
      return null;
    }

    return _queue.removeAt(0);
  }

  /// Removes every queued plan.
  void clear() {
    _queue.clear();
  }
}
