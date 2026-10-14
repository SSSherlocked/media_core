import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/slot_id.dart';
import 'package:media_core/slot/player_slot_state.dart';
import 'package:media_core/slot/player_slot_status.dart';

/// Represents a logical player slot.
///
/// A [PlayerSlot] is a container that binds:
///
/// - one player
/// - one session
///
/// during runtime.
///
/// It does not:
///
/// - create players
/// - create sessions
/// - control playback
///
/// Those belong to:
///
/// - PlayerFactory
/// - SessionManager
/// - SessionController
final class PlayerSlot {
  /// Creates player slot.
  PlayerSlot({required this.id});

  /// Slot identity.
  final SlotId id;

  /// Current slot status.
  PlayerSlotStatus status = PlayerSlotStatus.empty;

  /// Assigned player.
  PlayerId? playerId;

  /// Assigned session.
  SessionId? sessionId;

  /// Whether slot is empty.
  bool get isEmpty {
    return status == PlayerSlotStatus.empty;
  }

  /// Whether slot has player assignment.
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

  /// Assigns player and session.
  void assign({required PlayerId playerId, required SessionId sessionId}) {
    this.playerId = playerId;

    this.sessionId = sessionId;

    status = PlayerSlotStatus.assigned;
  }

  /// Marks slot active.
  void activate() {
    status = PlayerSlotStatus.active;
  }

  /// Marks slot releasing.
  void release() {
    status = PlayerSlotStatus.releasing;
  }

  /// Clears slot assignment.
  void clear() {
    playerId = null;

    sessionId = null;

    status = PlayerSlotStatus.empty;
  }

  /// Creates state snapshot.
  ///
  /// Used by PlayerSlotManager.
  PlayerSlotState toState() {
    return PlayerSlotState(slotId: id, status: status, playerId: playerId, sessionId: sessionId);
  }

  @override
  String toString() {
    return 'PlayerSlot('
        'id=$id, '
        'status=$status, '
        'playerId=$playerId, '
        'sessionId=$sessionId'
        ')';
  }
}
