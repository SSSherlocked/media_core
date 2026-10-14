import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core_logging/media_core_logging.dart';

/// Drives a player's lifecycle from the Flutter application lifecycle.
///
/// The handle's `PlayerHandle.activate` / `PlayerHandle.deactivate` are the
/// designed entry points for foreground/background; this driver connects the
/// platform's lifecycle transitions to them for a single live handle resolved
/// on demand.
///
/// ## Wiring status
///
/// Background-pause is owned in production by `PlayerKernel`, which registers
/// itself as a `WidgetsBindingObserver` and deactivates playing handles directly
/// (gated on `KernelOptions.pauseWhenBackgrounded` and the per-player
/// `PlayerConfig.pauseWhenBackgrounded`). Nothing in the package constructs this
/// driver — it is a standalone, per-handle alternative a host may bind to a
/// controller it owns, and it does nothing until a host instantiates and
/// disposes it.
///
/// The mapping:
///
/// ```text
/// AppLifecycleState.resumed   → handle.activate()
///                               (no auto-play: a TV coming back to the
///                               foreground must not start blaring audio
///                               on its own; the user resumes)
/// AppLifecycleState.inactive  → nothing
///                               (transient: dialogs, iOS app switcher)
/// AppLifecycleState.hidden    → handle.deactivate()
/// AppLifecycleState.paused    → handle.deactivate()
///                               (auto-pause: [PlayerHandle.deactivate]
///                               pauses only when actually playing)
/// AppLifecycleState.detached  → nothing
///                               (the engine is going away anyway)
/// ```
///
/// The driver does not hold a handle. Live playback rebuilds its handle on
/// every engine switch, so a driver bound to one instance would go stale;
/// instead `resolve` is asked for the current handle at every transition,
/// which keeps the wiring correct for whatever player is live.
///
/// Bind once per facade/controller and dispose with it:
///
/// ```dart
/// final driver = AppLifecycleDriver(resolve: () => controller.handle);
/// // ... later ...
/// driver.dispose();
/// ```
final class AppLifecycleDriver with WidgetsBindingObserver {
  /// Creates the driver and registers it with the framework.
  ///
  /// [resolve] returns the handle the transition applies to, or `null`
  /// when no player is currently live.
  AppLifecycleDriver({
    required PlayerHandle? Function() resolve,
    this.resumeOnForeground = false,
    this.onBackgrounded,
    this.onForegrounded,
  }) : _resolve = resolve {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Called after a background transition deactivated the player.
  ///
  /// The playback owner must stand its watchdogs down here: a background
  /// auto-pause is indistinguishable from a network pause to the adapter,
  /// and an unexpected-pause watchdog would silently resume playback the
  /// user cannot see.
  final void Function(PlayerHandle handle)? onBackgrounded;

  /// Called after a foreground transition activated the player.
  final void Function(PlayerHandle handle)? onForegrounded;

  final PlayerHandle? Function() _resolve;

  /// Whether returning to the foreground resumes playback automatically.
  ///
  /// Off by default: on TV, audio that starts by itself after switching
  /// back to the app reads as a bug. The user resumes.
  final bool resumeOnForeground;

  bool _disposed = false;

  /// Removes the driver from the framework.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) {
      return;
    }

    final handle = _resolve();

    if (handle == null || handle.disposed) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        handle.activate();
        onForegrounded?.call(handle);

        if (resumeOnForeground && _playbackWanted(handle)) {
          unawaited(handle.play());
        }

        MediaCoreLog.debug(
          LogCategory.lifecycle,
          'app foregrounded — player activated',
          fields: <String, Object?>{'player': handle.id.value, 'backend': handle.backendId},
        );

      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_deactivate(handle, state));

      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Transient on the way to paused/resumed, or the engine is
        // detaching anyway: no lifecycle action.
        break;
    }
  }

  bool _playbackWanted(PlayerHandle handle) {
    return handle.source != null && handle.playbackStream.value.isPlaying;
  }

  Future<void> _deactivate(PlayerHandle handle, AppLifecycleState state) async {
    // Deactivate pauses only when something is actually playing, so a
    // backgrounded idle player is not disturbed.
    await handle.deactivate();

    MediaCoreLog.info(
      LogCategory.lifecycle,
      'app backgrounded — player deactivated (auto-paused if playing)',
      fields: <String, Object?>{'player': handle.id.value, 'backend': handle.backendId, 'state': state.name},
    );

    onBackgrounded?.call(handle);
  }
}
