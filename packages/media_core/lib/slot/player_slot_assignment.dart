import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/slot_id.dart';
import 'package:media_core/slot/player_slot_owner.dart';

/// Represents a player slot assignment.
///
/// A [PlayerSlotAssignment] describes the relationship
/// between a slot and its current consumer.
///
/// Responsibilities:
///
/// - record assignment information
/// - track ownership
///
/// It does not:
///
/// - create player
/// - create session
/// - control playback
///
/// Those belong to:
///
/// - PlayerFactory
/// - SessionManager
/// - PlayerSlotManager
final class PlayerSlotAssignment extends Equatable {
  /// Creates assignment.
  const PlayerSlotAssignment({
    required this.slotId,
    required this.owner,
    required this.playerId,
    required this.sessionId,
    required this.createdAt,
  });

  /// Creates assignment.
  factory PlayerSlotAssignment.create({
    required SlotId slotId,
    required PlayerSlotOwner owner,
    required PlayerId playerId,
    required SessionId sessionId,
  }) {
    return PlayerSlotAssignment(
      slotId: slotId,
      owner: owner,
      playerId: playerId,
      sessionId: sessionId,
      createdAt: clock.now(),
    );
  }

  /// Slot identity.
  final SlotId slotId;

  /// Assignment owner.
  final PlayerSlotOwner owner;

  /// Assigned player.
  final PlayerId playerId;

  /// Assigned session.
  final SessionId sessionId;

  /// Assignment creation time.
  final DateTime createdAt;

  /// Whether assignment belongs to page.
  bool get isPage {
    return owner.isPage;
  }

  /// Whether assignment belongs to preload.
  bool get isPreload {
    return owner.isPreload;
  }

  /// Whether assignment belongs to PIP.
  bool get isPip {
    return owner.isPip;
  }

  /// Checks whether assignment matches slot.
  bool matchesSlot(SlotId id) {
    return slotId == id;
  }

  /// Checks whether assignment owns player.
  bool matchesPlayer(PlayerId id) {
    return playerId == id;
  }

  /// Checks whether assignment owns session.
  bool matchesSession(SessionId id) {
    return sessionId == id;
  }

  @override
  List<Object?> get props => [slotId, owner, playerId, sessionId, createdAt];

  @override
  String toString() {
    return 'PlayerSlotAssignment('
        'slot=$slotId, '
        'owner=$owner'
        ')';
  }
}
