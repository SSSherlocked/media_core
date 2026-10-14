import 'package:clock/clock.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/pool/player_pool_metrics.dart';
import 'package:media_core/pool/player_pool_state.dart';

part 'player_pool_snapshot.freezed.dart';

/// Immutable snapshot of player pool.
///
/// [PlayerPoolSnapshot] represents a captured
/// point-in-time view of the player pool.
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
/// - manage pool lifecycle
/// - allocate players
/// - recycle players
///
/// Those belong to:
///
/// - PlayerPoolManager
/// - PlayerPoolAllocator
/// - PlayerPoolRecycler
@freezed
abstract class PlayerPoolSnapshot with _$PlayerPoolSnapshot {
  /// Creates pool snapshot.
  const factory PlayerPoolSnapshot({
    /// Current pool state.
    required PlayerPoolState state,

    /// Current pool metrics.
    required PlayerPoolMetrics metrics,

    /// Snapshot creation time.
    required DateTime createdAt,
  }) = _PlayerPoolSnapshot;

  /// Creates empty snapshot.
  factory PlayerPoolSnapshot.empty() {
    return PlayerPoolSnapshot(
      state: const PlayerPoolState(),
      metrics: PlayerPoolMetrics.empty(),
      createdAt: clock.now(),
    );
  }
}
