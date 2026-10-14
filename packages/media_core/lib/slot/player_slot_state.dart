import 'package:equatable/equatable.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/slot_id.dart';
import 'package:media_core/slot/player_slot_status.dart';

/// Represents runtime state of a player slot.
///
/// [PlayerSlotState] is an immutable snapshot used
/// for reactive state updates.
///
/// It does not:
///
/// - control playback
/// - manage player lifecycle
/// - allocate resources
///
/// Those belong to:
///
/// - PlayerSlotManager
/// - PlayerPool
/// - PlayerSession
final class PlayerSlotState extends Equatable {
  /// Creates slot state.
  const PlayerSlotState({required this.slotId, this.status = PlayerSlotStatus.empty, this.playerId, this.sessionId});

  /// Creates empty slot state.
  factory PlayerSlotState.empty(SlotId slotId) {
    return PlayerSlotState(slotId: slotId);
  }

  /// Slot identity.
  final SlotId slotId;

  /// Current slot status.
  final PlayerSlotStatus status;

  /// Assigned player.
  final PlayerId? playerId;

  /// Assigned session.
  final SessionId? sessionId;

  /// Whether slot is empty.
  bool get isEmpty {
    return status == PlayerSlotStatus.empty;
  }

  /// Whether slot has assignment.
  bool get isAssigned {
    return status == PlayerSlotStatus.assigned;
  }

  /// Whether slot is active.
  bool get isActive {
    return status == PlayerSlotStatus.active;
  }

  /// Whether slot is releasing.
  bool get isReleasing {
    return status == PlayerSlotStatus.releasing;
  }

  /// Creates changed state.
  PlayerSlotState copyWith({PlayerSlotStatus? status, PlayerId? playerId, SessionId? sessionId}) {
    return PlayerSlotState(
      slotId: slotId,
      status: status ?? this.status,
      playerId: playerId ?? this.playerId,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  /// Whether this state belongs to slot.
  bool matchesSlot(SlotId id) {
    return slotId == id;
  }

  /// Whether this state contains player.
  bool matchesPlayer(PlayerId id) {
    return playerId == id;
  }

  /// Whether this state contains session.
  bool matchesSession(SessionId id) {
    return sessionId == id;
  }

  @override
  List<Object?> get props => [slotId, status, playerId, sessionId];

  @override
  String toString() {
    return 'PlayerSlotState('
        'slot=$slotId, '
        'status=$status, '
        'playerId=$playerId, '
        'sessionId=$sessionId'
        ')';
  }
}
