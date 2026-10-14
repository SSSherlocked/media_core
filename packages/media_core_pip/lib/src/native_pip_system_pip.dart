import 'dart:async';

import 'package:media_core_pip/src/system_pip.dart';
import 'package:native_picture_in_picture/native_picture_in_picture.dart';
import 'package:native_picture_in_picture/pip_event.dart';

/// [SystemPip] backed by the `native_picture_in_picture` plugin.
///
/// The plugin owns its own playback surface - ExoPlayer on Android (API 26+),
/// AVKit on iOS (14+) - and shrinks *that* into the system window. Entering
/// picture-in-picture through this backend is therefore a **handoff**, not a
/// re-render: the media keeps playing in the plugin's player while the app's
/// engine is expected to be paused, and on exit the host is called back to
/// hand playback and position back to its own engine. The two things this
/// trades away are the single-decode invariant (two decoders exist across a
/// transition, never playing at the same time) and anything the app's engine
/// did with headers, proxies or DRM for that source - which is why
/// [SystemPipMedia.url] must be openly playable.
///
/// ## Setup the plugin demands of the host app
///
/// - Android: `MainActivity` extends `FlutterFragmentActivity`, and the
///   activity carries `android:supportsPictureInPicture="true"`.
/// - iOS: `UIBackgroundModes` includes `audio`.
///
/// Both are host-side keys; like every [SystemPip] this fails at the platform
/// boundary when they are missing, and the failure surfaces as
/// [SystemPipStatus.unavailable] or a throw - the driver treats both as a
/// refused transition rather than a silent no-op.
final class NativePipSystemPip implements SystemPip {
  /// Creates the implementation.
  ///
  /// [player] exists for tests and for hosts that already own a plugin
  /// instance; production callers omit it.
  /// [onHandoffEnd] is called when the system reports the PiP window gone -
  /// the host should resume its own engine from the plugin's position there
  /// (read it through [position] before tearing the player down).
  NativePipSystemPip({NativePictureInPicture? player, this.onHandoffEnd, this.preferAutoPip = false})
    : _player = player ?? NativePictureInPicture();

  final NativePictureInPicture _player;

  /// Called when the system PiP window has gone for good.
  ///
  /// The host resumes its own engine here - by then the plugin's player holds
  /// the newer position, which is readable through [position].
  final Future<void> Function()? onHandoffEnd;

  /// Reports where the handoff player has reached, for the return handoff.
  ///
  /// Awaited rather than handed straight back: the plugin's own accessor is
  /// non-async, and a host reading this inside a `try` during teardown must see
  /// a platform failure as this future's error, not as a synchronous throw.
  Future<Duration?> get position async => await _player.getPosition();

  /// Whether leaving the app should shrink the window by itself (Android 12+
  /// auto-PiP) instead of only an explicit [enable] call.
  ///
  /// Arming this is what makes "swipe home keeps the video floating" work;
  /// it must be armed *before* the navigation happens, which is why the driver
  /// calls it on the [SystemPipTrigger.onLeaveApp] trigger rather than at the
  /// shrink itself.
  final bool preferAutoPip;

  bool _handoffActive = false;
  bool _disposed = false;
  StreamSubscription<PipEvent>? _eventSubscription;
  final StreamController<SystemPipStatus> _statuses = StreamController<SystemPipStatus>.broadcast();

  @override
  Future<bool> get isAvailable async {
    if (_disposed) {
      return false;
    }
    try {
      return await _player.isPipSupported();
    } on Object catch (_) {
      // A platform the plugin does not serve throws on the channel rather
      // than answering false.
      return false;
    }
  }

  @override
  Future<SystemPipStatus> get status async {
    if (_disposed) {
      return SystemPipStatus.unavailable;
    }
    try {
      return await _player.isPipActive()
          ? SystemPipStatus.enabled
          : (_handoffActive ? SystemPipStatus.automatic : SystemPipStatus.disabled);
    } on Object catch (_) {
      return SystemPipStatus.unavailable;
    }
  }

  @override
  Stream<SystemPipStatus> get statusStream {
    _ensureListening();
    return _statuses.stream;
  }

  @override
  Future<SystemPipStatus> enable({
    required int width,
    required int height,
    SystemPipSourceRect? sourceRect,
    SystemPipTrigger trigger = SystemPipTrigger.immediate,
    SystemPipMedia? media,
  }) async {
    if (_disposed) {
      throw StateError('NativePipSystemPip has been disposed.');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Picture-in-picture needs a positive video size, got ${width}x$height.');
    }

    if (trigger == SystemPipTrigger.onLeaveApp || preferAutoPip) {
      // Arm the system's own shrink-on-leave path first; the explicit start
      // below still works alongside it.
      try {
        await _player.setAutoPipEnabled(true);
      } on Object catch (_) {
        // A platform without auto-PiP only loses the polish, not the mode.
      }
      if (trigger == SystemPipTrigger.onLeaveApp && media == null) {
        _handoffActive = true;
        return SystemPipStatus.automatic;
      }
    }

    // The plugin plays the picture itself; without an openly playable source
    // there is nothing to hand over, and pretending otherwise would show the
    // viewer an empty system window.
    final handoff = media;
    if (handoff == null) {
      throw UnsupportedError(
        'native_picture_in_picture plays the media in its own player: enable() '
        'needs a SystemPipMedia (url, position). Report PiP as unavailable, or '
        'supply the host resolvers when building PipDriver.',
      );
    }

    await _player.initialize(handoff.url);
    final position = handoff.position;
    if (position != null) {
      await _player.seekTo(position);
    }
    await _player.play();
    await _player.startPiP();

    _ensureListening();
    _handoffActive = true;
    _statuses.add(SystemPipStatus.enabled);
    return SystemPipStatus.enabled;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      await _player.dispose();
    } on Object catch (_) {
      // The plugin may already be gone with the engine; teardown is best effort.
    }
    await _statuses.close();
  }

  /// Subscribes to plugin events once, and translates them to statuses.
  ///
  /// The subscription is created on first use rather than in the constructor
  /// because the event channel throws on platforms the plugin does not serve,
  /// and merely building a driver must not break the app.
  void _ensureListening() {
    if (_disposed || _eventSubscription != null) {
      return;
    }
    try {
      _eventSubscription = _player.onPipEvent.listen(_handleEvent);
    } on Object catch (_) {
      // No channel on this platform: availability already reports false.
    }
  }

  void _handleEvent(PipEvent event) {
    switch (event) {
      case PipEvent.willStart:
      case PipEvent.willStop:
        // Transient edges; the settled ones are what callers act on.
        break;
      case PipEvent.didStart:
        _handoffActive = true;
        _statuses.add(SystemPipStatus.enabled);
      case PipEvent.didStop:
        _finishHandoff();
        _statuses.add(SystemPipStatus.disabled);
      case PipEvent.restoreUI:
        // The viewer tapped "return to app": the window is dismissed with it,
        // and the app is about to be foreground again - same meaning here.
        _finishHandoff();
        _statuses.add(SystemPipStatus.disabled);
    }
  }

  void _finishHandoff() {
    if (!_handoffActive) {
      return;
    }
    _handoffActive = false;
    final callback = onHandoffEnd;
    if (callback != null) {
      unawaited(() async {
        try {
          await callback();
        } on Object catch (_) {
          // The host's resume is best effort: a failed handback must not eat
          // the status event the driver is waiting for.
        }
      }());
    }
  }
}
