import 'package:equatable/equatable.dart';
import 'package:media_core/core/player_status.dart';

/// Represents an action required during reconciliation.
///
/// ReconcileAction does not execute anything.
/// It only describes what should happen.
///
/// Execution belongs to:
///
/// - Coordinator
/// - Controller
/// - SessionManager
final class ReconcileAction extends Equatable {
  const ReconcileAction._({required this.type, this.from, this.to});

  /// Changes player lifecycle state.
  factory ReconcileAction.changeState({required PlayerStatus from, required PlayerStatus to}) {
    return ReconcileAction._(type: ReconcileActionType.changeState, from: from, to: to);
  }

  /// Action type.
  final ReconcileActionType type;

  /// Previous status.
  final PlayerStatus? from;

  /// Target status.
  final PlayerStatus? to;

  /// Whether this action changes state.
  bool get isStateChange {
    return type == ReconcileActionType.changeState;
  }

  @override
  List<Object?> get props => [type, from, to];

  @override
  String toString() {
    return 'ReconcileAction('
        'type: $type, '
        'from: $from, '
        'to: $to'
        ')';
  }
}

/// Types of reconciliation actions.
enum ReconcileActionType {
  /// Change player state.
  changeState,
}
