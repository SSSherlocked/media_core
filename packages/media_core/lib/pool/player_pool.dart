import 'dart:async';

import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/pool/player_pool_config.dart';
import 'package:media_core/pool/player_pool_manager.dart';
import 'package:media_core/pool/player_pool_snapshot.dart';
import 'package:media_core/pool/player_pool_state.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// Public player pool API.
///
/// [PlayerPool] is the public entry point
/// for player pool operations.
///
/// It hides internal pool coordination.
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
/// - PlayerSession
/// - PlaybackController
final class PlayerPool {
  /// Creates player pool.
  PlayerPool({PlayerPoolConfig config = const PlayerPoolConfig()}) : _manager = PlayerPoolManager(config: config);

  final PlayerPoolManager _manager;

  /// Current pool state stream.
  Stream<PlayerPoolState> get states {
    return _manager.states;
  }

  /// Current pool state.
  PlayerPoolState get state {
    return _manager.state;
  }

  /// Current snapshot.
  PlayerPoolSnapshot get snapshot {
    return _manager.snapshot;
  }

  /// Number of players.
  int get count {
    return state.totalPlayers;
  }

  /// Ledger of the players held by this pool.
  /// This instance's key in the shared account.
  late final String _memoryKey = memoryContributorKey(this);

  final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.pool);

  /// Adds player into pool.
  void add(PlayerId playerId) {
    _manager.add(playerId);
    _reportMemory();
  }

  /// Removes player.
  bool remove(PlayerId playerId) {
    final removed = _manager.remove(playerId);
    _reportMemory();
    return removed;
  }

  /// Allocates player for session.
  PlayerId? allocate({required SessionId sessionId}) {
    return _manager.allocate(sessionId: sessionId);
  }

  /// Releases player.
  bool release(PlayerId playerId) {
    return _manager.release(playerId);
  }

  /// Marks a specific player as in use.
  ///
  /// Used by the kernel for freshly created handles, which belong to their
  /// creator and must not be handed out by [allocate].
  bool reserve(PlayerId playerId, {required SessionId sessionId}) {
    return _manager.reserve(playerId, sessionId: sessionId);
  }

  /// Gets recycle candidates.
  List<PlayerId> recycleCandidates({int maxCount = 1}) {
    return _manager.recycleCandidates(maxCount: maxCount);
  }

  /// Reports how many players the pool holds.
  ///
  /// The pool reuses players rather than opening them, so this is the count that
  /// answers "how many decoders is the pool keeping alive?" — the number that
  /// grows when recycling stops working.
  void _reportMemory() {
    final players = _manager.state.totalPlayers;
    _memory.report(
      _memoryKey,
      items: players,
      bytes: players * MemoryEstimates.videoStream720p,
      note: '$players pooled player(s)',
    );
  }

  /// Disposes pool.
  Future<void> dispose() async {
    await _manager.dispose();
    _memory.withdraw(_memoryKey);
  }
}
