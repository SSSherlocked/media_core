import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/slot_id.dart';
import 'package:media_core/slot/player_slot_status.dart';

/// Immutable snapshot of a player slot.
///
/// A [PlayerSlotSnapshot] represents a captured
/// point-in-time view of a slot.
///
/// It is used for:
///
/// - diagnostics
/// - debugging
/// - testing
/// - state inspection
///
/// It does not:
///
/// - control slot lifecycle
/// - mutate player assignment
/// - manage playback
final class PlayerSlotSnapshot extends Equatable {
  /// Creates slot snapshot.
  const PlayerSlotSnapshot({
    required this.slotId,
    required this.status,
    required this.createdAt,
    this.playerId,
    this.sessionId,
  });

  /// Creates snapshot from runtime slot.
  factory PlayerSlotSnapshot.fromState(
    SlotId slotId,
    PlayerSlotStatus status, {
    PlayerId? playerId,
    SessionId? sessionId,
  }) {
    return PlayerSlotSnapshot(
      slotId: slotId,
      status: status,
      playerId: playerId,
      sessionId: sessionId,
      createdAt: clock.now(),
    );
  }

  /// Slot identity.
  final SlotId slotId;

  /// Slot status at snapshot time.
  final PlayerSlotStatus status;

  /// Assigned player.
  final PlayerId? playerId;

  /// Assigned session.
  final SessionId? sessionId;

  /// Snapshot creation time.
  final DateTime createdAt;

  /// Whether slot was empty.
  bool get isEmpty {
    return status == PlayerSlotStatus.empty;
  }

  /// Whether slot had player assignment.
  bool get isAssigned {
    return status == PlayerSlotStatus.assigned;
  }

  /// Whether slot was active.
  bool get isActive {
    return status == PlayerSlotStatus.active;
  }

  /// Creates copy with changes.
  PlayerSlotSnapshot copyWith({
    SlotId? slotId,
    PlayerSlotStatus? status,
    PlayerId? playerId,
    SessionId? sessionId,
    DateTime? createdAt,
  }) {
    return PlayerSlotSnapshot(
      slotId: slotId ?? this.slotId,
      status: status ?? this.status,
      playerId: playerId ?? this.playerId,
      sessionId: sessionId ?? this.sessionId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [slotId, status, playerId, sessionId, createdAt];

  @override
  String toString() {
    return 'PlayerSlotSnapshot('
        'slot=$slotId, '
        'status=$status, '
        'playerId=$playerId, '
        'sessionId=$sessionId, '
        'createdAt=$createdAt'
        ')';
  }
}
