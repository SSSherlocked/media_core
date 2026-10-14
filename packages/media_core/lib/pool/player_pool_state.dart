import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';

part 'player_pool_state.freezed.dart';

/// Runtime state of player pool.
///
/// [PlayerPoolState] describes current pool condition.
///
/// It does not:
///
/// - allocate players
/// - release players
/// - control playback
///
/// Those belong to:
///
/// - PlayerPoolManager
/// - PlayerPoolAllocator
/// - PlayerPoolRecycler
@freezed
abstract class PlayerPoolState with _$PlayerPoolState {
  /// Creates pool state.
  const factory PlayerPoolState({
    /// Total slots managed by pool.
    @Default(0) int totalPlayers,

    /// Currently idle players.
    @Default(0) int idlePlayers,

    /// Currently active players.
    @Default(0) int activePlayers,

    /// Players being released.
    @Default(0) int releasingPlayers,

    /// Whether pool reached capacity.
    @Default(false) bool isFull,

    /// Current active player ids.
    @Default(<PlayerId>[]) List<PlayerId> activePlayerIds,

    /// Current active sessions.
    @Default(<SessionId>[]) List<SessionId> activeSessionIds,

    /// Whether pool is initialized.
    @Default(false) bool initialized,

    /// Whether pool is disposing.
    @Default(false) bool disposing,
  }) = _PlayerPoolState;
}
