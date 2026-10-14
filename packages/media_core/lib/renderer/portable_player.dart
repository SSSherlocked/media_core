import 'package:media_core/diagnostics/library.dart' show LogCategory, LogModule, MediaCoreLog;
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/kernel/player_kernel.dart';
import 'package:media_core/renderer/media_player_view.dart' show MediaPlayerView;

/// Records handover lookups that found nothing.
///
/// "The small window opened empty" and "the small window did not open" are two
/// different bugs, and the difference is exactly whether a registry lookup found
/// a live player. A `null` here means the page disposed what it should have left
/// to the kernel.
final LogModule _log = MediaCoreLog.of(LogCategory.presentation);

/// A player that can be shown on more than one surface.
///
/// The framework's answer to "the page is going away while the video is
/// playing" is that a player is not owned by a page: the kernel owns a
/// [PlayerHandle], and a surface is a widget built from it. This interface names
/// that property so small-window features (picture-in-picture, the in-app
/// floating window) can carry a player without depending on the kernel directly
/// — and so they can be tested without one.
///
/// [handle] is the escape hatch that makes the handover free: a feature that has
/// it can build the framework's own video surface over the *same* player, so the
/// stream, the position and the decoder are reused rather than re-created.
abstract interface class PortablePlayer {
  /// PlayerIdentity identity.
  PlayerId get id;

  /// Whether the player is gone.
  bool get isDisposed;

  /// Video width in pixels, or `0` when unknown.
  int get videoWidth;

  /// Video height in pixels, or `0` when unknown.
  int get videoHeight;

  /// The framework handle, when this player is a kernel player.
  ///
  /// `null` for a host-owned player: such a host must supply its own surface
  /// builder, because only it knows how to render what it owns.
  PlayerHandle? get handle;
}

/// Looks up the player a small window should carry.
abstract interface class PortablePlayerRegistry {
  /// The player with [id], or `null` when it no longer exists.
  PortablePlayer? find(PlayerId id);
}

/// [PortablePlayerRegistry] over a [PlayerKernel].
///
/// This is what makes the handover work in practice: the kernel keeps the handle
/// after a page is popped, so the small window can pick the same player up and
/// render it with [MediaPlayerView].
final class KernelPortablePlayerRegistry implements PortablePlayerRegistry {
  /// Looks players up in [kernel], the one that owns the handles a page left
  /// behind.
  KernelPortablePlayerRegistry(this.kernel);

  /// Kernel owning the players.
  final PlayerKernel kernel;

  @override
  PortablePlayer? find(PlayerId id) {
    final handle = kernel.get(id);
    if (handle == null) {
      _log.warning('handover lookup found no player', fields: <String, Object?>{'playerId': id.value});
      return null;
    }
    if (handle.disposed) {
      _log.warning('handover lookup found a disposed player', fields: <String, Object?>{'playerId': id.value});
    }
    return _KernelPortablePlayer(handle);
  }
}

final class _KernelPortablePlayer implements PortablePlayer {
  _KernelPortablePlayer(this._handle);

  final PlayerHandle _handle;

  @override
  PlayerId get id => _handle.id;

  @override
  bool get isDisposed => _handle.disposed;

  @override
  int get videoWidth => _handle.combinedSnapshot.geometry.videoSize?.width ?? 0;

  @override
  int get videoHeight => _handle.combinedSnapshot.geometry.videoSize?.height ?? 0;

  @override
  PlayerHandle? get handle => _handle.disposed ? null : _handle;
}
