import 'dart:async';

import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/kernel/player_kernel.dart';
import 'package:media_core/playback/player_transport_state.dart';
import 'package:media_core/source/player_source.dart';

/// A player the pool drives.
///
/// Narrow on purpose: the pool needs to re-point a player at another source,
/// start and stop it, and hand it back. Keeping the seam this small means the
/// orchestration above it can be tested without a backend, and a host can pool
/// something other than a kernel handle (a live controller's player, a
/// platform view's player) by implementing three methods.
abstract interface class PoolPlayerHandle {
  /// Stable identifier, used in plans and metrics.
  String get id;

  /// Whether the underlying player is gone.
  bool get isDisposed;

  /// Points the player at [source], optionally starting playback.
  ///
  /// This is a re-point, not a re-create: a pooled player keeps its decoder and
  /// its session, which is what makes a swipe cheap.
  Future<void> open(PlayerSource source, {bool autoPlay});

  /// Starts playback.
  Future<void> play();

  /// Stops playback without releasing the player.
  Future<void> pause();

  /// Resets per-source state, preparing the player to take another source.
  Future<void> recycle();

  /// Sets the player's volume.
  Future<void> setVolume(double volume);

  /// Mutes or unmutes the player.
  Future<void> setMute({required bool muted});

  /// Playback state stream of the player.
  Stream<PlayerTransportState> get playbackStream;
}

/// Where the pool gets players and where it puts them back.
abstract interface class PoolPlayerHost {
  /// Takes a reusable player, or creates one when none is available.
  Future<PoolPlayerHandle> acquire();

  /// Returns [handle] for reuse.
  Future<void> release(PoolPlayerHandle handle);

  /// Releases [handle] for good.
  Future<void> disposeHandle(PoolPlayerHandle handle);
}

/// [PoolPlayerHandle] backed by a kernel [PlayerHandle].
final class KernelPoolPlayerHandle implements PoolPlayerHandle {
  /// Drives the kernel [handle] through the pool.
  KernelPoolPlayerHandle(this.handle);

  /// Handle being driven.
  final PlayerHandle handle;

  @override
  String get id => handle.id.value;

  @override
  bool get isDisposed => handle.disposed;

  @override
  Future<void> open(PlayerSource source, {bool autoPlay = false}) => handle.open(source, autoPlay: autoPlay);

  @override
  Future<void> play() => handle.play();

  @override
  Future<void> pause() => handle.pause();

  @override
  Future<void> recycle() => handle.recycle();

  @override
  Future<void> setVolume(double volume) => handle.setVolume(volume);

  @override
  Future<void> setMute({required bool muted}) => handle.setMute(muted: muted);

  @override
  Stream<PlayerTransportState> get playbackStream => handle.playbackStream;
}

/// [PoolPlayerHost] backed by [PlayerKernel].
///
/// Reuse goes through the kernel's instance pool when it is enabled, and falls
/// back to creating a player when it is not — a host that has not enabled
/// pooling still gets correct behaviour, it just pays for a cold player on each
/// take.
final class KernelPoolPlayerHost implements PoolPlayerHost {
  /// Takes and returns players through [kernel].
  KernelPoolPlayerHost(this.kernel);

  /// Kernel the pool takes players from.
  final PlayerKernel kernel;

  @override
  Future<PoolPlayerHandle> acquire() async {
    final pooled = await kernel.acquire();
    if (pooled != null) {
      return KernelPoolPlayerHandle(pooled);
    }
    return KernelPoolPlayerHandle(await kernel.create());
  }

  @override
  Future<void> release(PoolPlayerHandle handle) async {
    if (handle is KernelPoolPlayerHandle) {
      // The pool's own contract: hand the player back for reuse. Going through
      // `kernel.release` here would dispose it, so nothing would ever be
      // reused and every take would pay for a cold player - which is exactly
      // what the pool exists to avoid.
      await handle.handle.recycle();
      kernel.pool.release(handle.handle.id);

      return;
    }

    await handle.pause();
  }

  @override
  Future<void> disposeHandle(PoolPlayerHandle handle) async {
    if (handle is KernelPoolPlayerHandle) {
      // Destruction goes through the kernel so the handle leaves its
      // registrations and the pool row in one step; calling `dispose()` here
      // would leave a dead player registered everywhere.
      await kernel.release(handle.handle.id);

      return;
    }

    await handle.pause();
  }
}
