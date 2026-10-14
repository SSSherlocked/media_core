import 'package:equatable/equatable.dart';
import 'package:media_core/recovery/recovery_action.dart';
import 'package:media_core/recovery/recovery_context.dart';
import 'package:media_core/recovery/recovery_state.dart';

/// Immutable snapshot of the complete recovery state.
///
/// A snapshot combines the state machine state with the context that caused
/// the recovery.
///
/// Snapshots are suitable for:
///
/// - diagnostics
/// - logging
/// - state observation
/// - persistence
/// - debugging
///
/// A snapshot does not execute recovery.
final class RecoverySnapshot extends Equatable {
  /// Pairs the recovery state with the context that caused it for one observation.
  const RecoverySnapshot({required this.state, required this.context});

  /// Builds a snapshot from [state], attaching the [context] that triggered recovery when it is known.
  ///
  /// The context is optional because a state change can be observed without a failure behind it.
  factory RecoverySnapshot.fromState(RecoveryState state, {RecoveryContext? context}) {
    return RecoverySnapshot(state: state, context: context);
  }

  /// The recovery state machine state captured with this snapshot.
  final RecoveryState state;

  /// The failure context that led to recovery, when one was recorded.
  final RecoveryContext? context;

  /// The action the current state prescribes, or none while recovery is idle.
  RecoveryAction get action => state.action;

  /// How many recovery attempts the state has recorded so far.
  int get attempt => state.attempt;

  /// Whether a recovery operation is in progress.
  bool get active => state.active;

  /// Whether recovery restored playback.
  bool get completed => state.completed;

  /// Whether recovery ran out of actions without restoring playback.
  bool get exhausted => state.exhausted;

  /// Whether the snapshot can be correlated with a recorded failure context.
  bool get hasContext => context != null;

  /// Whether the recovery lifecycle has not started or has been reset.
  bool get isIdle => state.isIdle;

  /// Whether the recovery lifecycle has finished, successfully or not.
  bool get isTerminal => state.isTerminal;

  /// Returns a snapshot with the given state or context replaced.
  RecoverySnapshot copyWith({RecoveryState? state, RecoveryContext? context}) {
    return RecoverySnapshot(state: state ?? this.state, context: context ?? this.context);
  }

  /// Serialises the snapshot for diagnostics and persistence.
  ///
  /// Both halves are written as maps, so a snapshot can be stored without exposing the recovery types.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{'state': state.toMap(), 'context': context?.toMap()};
  }

  @override
  List<Object?> get props => <Object?>[state, context];

  @override
  String toString() {
    return 'RecoverySnapshot('
        'state: $state, '
        'context: $context'
        ')';
  }
}
