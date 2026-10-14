import 'dart:async';

import 'package:clock/clock.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/pool/player_pool_allocator.dart';
import 'package:media_core/pool/player_pool_config.dart';
import 'package:media_core/pool/player_pool_metrics.dart';
import 'package:media_core/pool/player_pool_recycler.dart';
import 'package:media_core/pool/player_pool_snapshot.dart';
import 'package:media_core/pool/player_pool_state.dart';
import 'package:rxdart/rxdart.dart';

/// Manages player pool runtime.
///
/// [PlayerPoolManager] coordinates allocation
/// and recycling of player instances.
///
/// It does not:
///
/// - create players
/// - destroy players
/// - control playback
///
/// Those belong to:
///
/// - PlayerFactory
/// - PlayerController
/// - SessionManager
final class PlayerPoolManager {
  /// Creates pool manager.
  PlayerPoolManager({
    PlayerPoolConfig config = const PlayerPoolConfig(),
    PlayerPoolAllocator? allocator,
    PlayerPoolRecycler? recycler,
  }) : _config = config,
       _allocator = allocator ?? PlayerPoolAllocator(),
       _recycler = recycler ?? PlayerPoolRecycler();

  final PlayerPoolConfig _config;

  final PlayerPoolAllocator _allocator;

  final PlayerPoolRecycler _recycler;

  final Set<PlayerId> _players = {};

  final Set<PlayerId> _active = {};

  final Map<PlayerId, SessionId> _sessions = {};

  PlayerPoolMetrics _metrics = PlayerPoolMetrics.empty();

  /// Sum of all measured allocation times.
  ///
  /// Kept alongside the count so the reported average does not drift with
  /// rounding, and so it survives a metrics rebuild.
  Duration _allocationTimeTotal = Duration.zero;

  final BehaviorSubject<PlayerPoolState> _stateSubject = BehaviorSubject.seeded(const PlayerPoolState());

  /// Current state stream.
  Stream<PlayerPoolState> get states {
    return _stateSubject.stream;
  }

  /// Current state.
  PlayerPoolState get state {
    return _stateSubject.value;
  }

  /// Current snapshot.
  PlayerPoolSnapshot get snapshot {
    return PlayerPoolSnapshot(state: state, metrics: _metrics, createdAt: clock.now());
  }

  /// Adds player into pool.
  void add(PlayerId playerId) {
    _players.add(playerId);

    _syncCounts();

    _publish();
  }

  /// Removes player.
  bool remove(PlayerId playerId) {
    final removed = _players.remove(playerId);

    _active.remove(playerId);
    _sessions.remove(playerId);

    if (removed) {
      _metrics = _metrics.copyWith(destroyedCount: _metrics.destroyedCount + 1);

      _syncCounts();

      _publish();
    }

    return removed;
  }

  /// Allocates player.
  PlayerId? allocate({required SessionId sessionId}) {
    final stopwatch = Stopwatch()..start();

    final player = _allocator.allocate(availablePlayers: _availablePlayers, sessionId: sessionId);

    stopwatch.stop();

    if (player == null) {
      _metrics = _metrics.copyWith(allocationFailureCount: _metrics.allocationFailureCount + 1);

      _syncCounts();

      return null;
    }

    _active.add(player);
    _sessions[player] = sessionId;

    _allocationTimeTotal += stopwatch.elapsed;

    _metrics = _metrics.copyWith(allocationCount: _metrics.allocationCount + 1);

    _syncCounts();

    _publish();

    return player;
  }

  /// Marks [playerId] as in use by [sessionId].
  ///
  /// [allocate] takes *any* idle player; this exists for the opposite case — a
  /// handle that was just created and is owned by its creator. Without it such
  /// a handle counts as idle, and the next [allocate] hands out (and recycles)
  /// the player that is currently playing.
  bool reserve(PlayerId playerId, {required SessionId sessionId}) {
    if (!_players.contains(playerId)) {
      return false;
    }

    _active.add(playerId);
    _sessions[playerId] = sessionId;

    _syncCounts();

    _publish();

    return true;
  }

  /// Releases player back to pool.
  bool release(PlayerId playerId) {
    if (!_active.contains(playerId)) {
      _metrics = _metrics.copyWith(recycleFailureCount: _metrics.recycleFailureCount + 1);

      return false;
    }

    _active.remove(playerId);
    _sessions.remove(playerId);

    _metrics = _metrics.copyWith(recycleCount: _metrics.recycleCount + 1);

    _syncCounts();

    _publish();

    return true;
  }

  /// Rewrites the metrics that describe the pool right now.
  ///
  /// Idle/allocated/peak and the timestamp are derived here instead of at each
  /// call site, so every metrics snapshot describes the state it was taken
  /// from.
  void _syncCounts() {
    final allocated = _active.length;

    _metrics = _metrics.copyWith(
      allocatedCount: allocated,
      idleCount: _availablePlayers.length,
      peakCount: allocated > _metrics.peakCount ? allocated : _metrics.peakCount,
      averageAllocationTime: _metrics.allocationCount == 0
          ? null
          : Duration(microseconds: _allocationTimeTotal.inMicroseconds ~/ _metrics.allocationCount),
      updatedAt: clock.now(),
    );
  }

  /// Finds recyclable players.
  List<PlayerId> recycleCandidates({int maxCount = 1}) {
    return _recycler.findCandidates(idlePlayers: _availablePlayers, maxCount: maxCount);
  }

  List<PlayerId> get _availablePlayers {
    return _players.where((id) => !_active.contains(id)).toList(growable: false);
  }

  void _publish() {
    _stateSubject.add(
      PlayerPoolState(
        totalPlayers: _players.length,
        idlePlayers: _availablePlayers.length,
        activePlayers: _active.length,
        isFull: _isFull,
        activePlayerIds: List.unmodifiable(_active),
        activeSessionIds: List.unmodifiable(_sessions.values),
        initialized: true,
      ),
    );
  }

  bool get _isFull {
    if (_config.maxPlayers == 0) {
      return false;
    }

    return _players.length >= _config.maxPlayers;
  }

  /// Disposes manager.
  Future<void> dispose() async {
    await _stateSubject.close();

    _players.clear();
    _active.clear();
    _sessions.clear();
  }
}
