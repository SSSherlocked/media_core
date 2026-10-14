import 'package:equatable/equatable.dart';

/// Runtime state of reconciliation process.
final class ReconcileState extends Equatable {
  /// Creates a reconciliation state from its phase flags and pending count.
  const ReconcileState({this.running = false, this.completed = false, this.failed = false, this.pendingActions = 0});

  /// Whether reconciliation is running.
  final bool running;

  /// Whether reconciliation completed.
  final bool completed;

  /// Whether reconciliation failed.
  final bool failed;

  /// Number of pending actions.
  final int pendingActions;

  /// Whether no reconciliation phase is active and nothing is pending.
  bool get isIdle {
    return !running && !completed && !failed && pendingActions == 0;
  }

  /// Whether reconciliation is currently running.
  bool get isProcessing {
    return running;
  }

  /// Whether reconciliation ended in failure.
  bool get hasFailure {
    return failed;
  }

  /// Returns a copy with the given fields replaced.
  ReconcileState copyWith({bool? running, bool? completed, bool? failed, int? pendingActions}) {
    return ReconcileState(
      running: running ?? this.running,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      pendingActions: pendingActions ?? this.pendingActions,
    );
  }

  /// Returns the running state with [count] actions pending.
  ReconcileState start(int count) {
    return ReconcileState(running: true, pendingActions: count);
  }

  /// Returns the completed state.
  ReconcileState finish() {
    return const ReconcileState(completed: true);
  }

  /// Returns the failed state.
  ReconcileState fail() {
    return const ReconcileState(failed: true);
  }

  @override
  List<Object?> get props => [running, completed, failed, pendingActions];
}
