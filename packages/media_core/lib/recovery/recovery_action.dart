import 'package:equatable/equatable.dart';

/// Describes an action that the recovery system may perform.
///
/// A recovery action is a decision value, not an execution request.
/// It describes what should happen after a playback or resource failure.
///
/// Execution belongs to the recovery manager or the corresponding
/// subsystem. This keeps recovery policy separate from side effects.
sealed class RecoveryAction extends Equatable {
  const RecoveryAction();

  /// Do nothing and leave the current operation unchanged.
  const factory RecoveryAction.none() = RecoveryActionNone;

  /// Retry the current operation.
  const factory RecoveryAction.retry() = RecoveryActionRetry;

  /// Retry after restarting the current operation.
  const factory RecoveryAction.restart() = RecoveryActionRestart;

  /// Reinitialize the affected subsystem before retrying.
  const factory RecoveryAction.reinitialize() = RecoveryActionReinitialize;

  /// Stop the current operation and give up recovery.
  const factory RecoveryAction.stop() = RecoveryActionStop;

  /// Whether recovery decided to leave the operation untouched.
  bool get isNone => this is RecoveryActionNone;

  /// Whether the decision is to attempt the current operation again.
  bool get isRetry => this is RecoveryActionRetry;

  /// Whether the operation is to be restarted before it is attempted again.
  bool get isRestart => this is RecoveryActionRestart;

  /// Whether the affected subsystem is to be rebuilt before the next attempt.
  bool get isReinitialize => this is RecoveryActionReinitialize;

  /// Whether recovery gives up, which terminates the affected operation.
  bool get isStop => this is RecoveryActionStop;

  /// Whether this action requires another attempt.
  bool get requiresRetry => isRetry || isRestart || isReinitialize;

  /// Whether this action terminates recovery.
  bool get isTerminal => isNone || isStop;

  @override
  List<Object?> get props => [];
}

/// No recovery action.
final class RecoveryActionNone extends RecoveryAction {
  /// Creates the action that leaves the operation unchanged.
  const RecoveryActionNone();

  @override
  String toString() => 'RecoveryActionNone';
}

/// Retry the current operation.
final class RecoveryActionRetry extends RecoveryAction {
  /// Creates the action that attempts the current operation again.
  const RecoveryActionRetry();

  @override
  String toString() => 'RecoveryActionRetry';
}

/// Restart the current operation before retrying.
final class RecoveryActionRestart extends RecoveryAction {
  /// Creates the action that restarts the operation before retrying it.
  const RecoveryActionRestart();

  @override
  String toString() => 'RecoveryActionRestart';
}

/// Reinitialize the affected subsystem before retrying.
final class RecoveryActionReinitialize extends RecoveryAction {
  /// Creates the action that rebuilds the affected subsystem before retrying.
  const RecoveryActionReinitialize();

  @override
  String toString() => 'RecoveryActionReinitialize';
}

/// Stop recovery and terminate the affected operation.
final class RecoveryActionStop extends RecoveryAction {
  /// Creates the action that ends recovery and terminates the operation.
  const RecoveryActionStop();

  @override
  String toString() => 'RecoveryActionStop';
}
