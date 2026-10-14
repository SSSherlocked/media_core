import 'dart:async';

import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/slot_id.dart';
import 'package:media_core/slot/player_slot.dart';
import 'package:media_core/slot/player_slot_state.dart';
import 'package:rxdart/rxdart.dart';

/// Manages player slots.
///
/// A [PlayerSlotManager] owns slot lifecycle.
///
/// Responsibilities:
///
/// - create slots
/// - assign players
/// - activate slots
/// - release slots
/// - expose slot states
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
final class PlayerSlotManager {
  /// Creates slot manager.
  PlayerSlotManager();

  final Map<SlotId, PlayerSlot> _slots = {};

  final BehaviorSubject<List<PlayerSlotState>> _stateSubject = BehaviorSubject.seeded(const []);

  /// Stream of slot states.
  Stream<List<PlayerSlotState>> get states {
    return _stateSubject.stream;
  }

  /// Current slots.
  List<PlayerSlot> get slots {
    return _slots.values.toList(growable: false);
  }

  /// Number of slots.
  int get count {
    return _slots.length;
  }

  /// Creates a new slot.
  PlayerSlot create(SlotId id) {
    final slot = PlayerSlot(id: id);

    _slots[id] = slot;

    _publish();

    return slot;
  }

  /// Gets slot by id.
  PlayerSlot? get(SlotId id) {
    return _slots[id];
  }

  /// Assigns player and session.
  PlayerSlot? assign({required SlotId slotId, required PlayerId playerId, required SessionId sessionId}) {
    final slot = _slots[slotId];

    if (slot == null) {
      return null;
    }

    slot.assign(playerId: playerId, sessionId: sessionId);

    _publish();

    return slot;
  }

  /// Marks slot active.
  PlayerSlot? activate(SlotId slotId) {
    final slot = _slots[slotId];

    if (slot == null) {
      return null;
    }

    slot.activate();

    _publish();

    return slot;
  }

  /// Releases slot.
  PlayerSlot? release(SlotId slotId) {
    final slot = _slots[slotId];

    if (slot == null) {
      return null;
    }

    slot.release();

    _publish();

    return slot;
  }

  /// Clears slot assignment.
  PlayerSlot? clearSlot(SlotId slotId) {
    final slot = _slots[slotId];

    if (slot == null) {
      return null;
    }

    slot.clear();

    _publish();

    return slot;
  }

  /// Removes slot.
  bool remove(SlotId slotId) {
    final removed = _slots.remove(slotId) != null;

    if (removed) {
      _publish();
    }

    return removed;
  }

  /// Clears all slots.
  void clear() {
    _slots.clear();

    _publish();
  }

  /// Publishes current states.
  void _publish() {
    _stateSubject.add(_slots.values.map((slot) => slot.toState()).toList(growable: false));
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await _stateSubject.close();

    _slots.clear();
  }
}
