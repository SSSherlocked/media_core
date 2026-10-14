import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:media_core/media_core.dart';
import 'package:media_core_pip/src/desktop_pip_window.dart';
import 'package:media_core_pip/src/native_pip_system_pip.dart';
import 'package:media_core_pip/src/pip_config.dart';
import 'package:media_core_pip/src/pip_window.dart';
import 'package:media_core_pip/src/system_pip.dart';

/// Records which platform path ran and why a request was refused.
///
/// Desktop and mobile take different routes to the same mode, and on mobile the
/// platform can refuse the request outright; the log is what separates "the
/// driver went the wrong way" from "the device said no".
final LogModule _log = MediaCoreLog.of(LogCategory.presentation);

/// Which platform family the driver is running on.
///
/// Resolved from the OS, but injectable so the two paths can be exercised
/// without a device: the mobile path is the one that cannot be reached on a
/// desktop test host, and it is also the one with the more subtle contract.
enum PipPlatform {
  /// Windows, macOS, Linux: the small window is a real window.
  desktop,

  /// Android/iOS: the small window is the system picture-in-picture window.
  mobile,

  /// Web and anything else: picture-in-picture is not served here.
  unsupported;

  /// Resolves this host's family.
  static PipPlatform resolve() {
    // PlatformUtils is the core's single answer to "what am I running on";
    // re-deriving it here from Platform would let the two drift apart.
    if (kIsWeb) {
      return PipPlatform.unsupported;
    }
    if (PlatformUtils.isDesktop) {
      return PipPlatform.desktop;
    }
    if (PlatformUtils.isMobile) {
      return PipPlatform.mobile;
    }
    return PipPlatform.unsupported;
  }
}

/// Owns the picture-in-picture mode.
///
/// Responsibilities:
///
/// - enter and leave picture-in-picture for one player
/// - size the small window from the video's shape
/// - keep [isPip] truthful, including when the system ends PiP on its own
///
/// It does not:
///
/// - decide when picture-in-picture is appropriate
/// - own fullscreen or the in-app small window (separate packages own those)
/// - restore the host's UI after PiP ends
///
/// ## Desktop vs mobile
///
/// On desktop the feature is a window the app fully controls: capture the
/// window state, shrink it into a corner, restore on the way out.
///
/// On mobile the feature is the platform's own PiP window. Three platform facts
/// shape that path, and none of them are worked around here:
///
/// - picture-in-picture can be **requested** but not exited from the app, so
///   `normal` cannot undo it; the state follows the system's own status stream;
/// - Android accepts only aspect ratios inside 1/2.39..2.39, so an extreme
///   video falls back to the platform default rather than failing the request;
/// - the shipped backend (`native_picture_in_picture`) renders the picture in
///   its **own** native player (ExoPlayer / AVKit, Android 26+ / iOS 14+), so
///   entering on mobile is a handoff: [pipMediaResolver] must name a URL the
///   platform can open, and [onHandoffReturn] gives the host its playback
///   back when the window closes.
///
/// A request the platform cannot serve throws [UnsupportedError] rather than
/// silently doing nothing: the presentation state machine records a failed
/// transition, and the host can tell the viewer why nothing happened.
final class PipDriver implements KernelPresentationDriver {
  /// Creates the driver.
  PipDriver({
    this.config = PipConfig.defaults,
    PipPlatform? platform,
    PipWindow? desktopWindow,
    SystemPip? systemPip,
    PresentationLifecycleHooks? lifecycleHooks,
    this.pipMediaResolver,
    this.onHandoffReturn,
  }) : platform = platform ?? PipPlatform.resolve(),
       _desktopWindow = desktopWindow,
       _systemPip = systemPip,
       lifecycleHooks = lifecycleHooks ?? const PresentationLifecycleHooks();

  /// Fallback identity for system-initiated transitions that happen before
  /// the first app-driven request named a player.
  static final _systemPlayerId = PlayerId('pip-system');

  /// Tunables, assigned directly.
  ///
  /// Exists for hosts that build their settings after the driver was created:
  /// a transition reads the whole object, so replace it with a complete
  /// [PipConfig] (see [PipConfig.copyWith]) rather than editing pieces of it.
  PipConfig config;

  /// Platform family this driver serves.
  final PipPlatform platform;

  PipWindow? _desktopWindow;
  SystemPip? _systemPip;

  /// Lifecycle hooks fired around enter/exit transitions. Replaceable for
  /// hosts that build their hooks after the driver; see [updateLifecycleHooks].
  PresentationLifecycleHooks lifecycleHooks;

  /// Supplies the media a handoff PiP player should take over.
  ///
  /// The shipped mobile backend (`native_picture_in_picture`) plays the picture
  /// in its own native player, so entering PiP is a handoff: this resolver is
  /// asked, at the moment of entry, for the URL the *native* player can open
  /// by itself and the position to resume from. Returning null - a signed
  /// header source, a loopback proxy, anything the platform player cannot
  /// reach - makes the entry throw [UnsupportedError] rather than show an
  /// empty system window. Desktop paths never call it.
  final Future<SystemPipMedia?> Function(PlayerId playerId)? pipMediaResolver;

  /// Called when a handoff PiP window is gone and the system player is torn
  /// down: the host resumes its own engine here (pause it via
  /// [PresentationLifecycleHooks.beforeEnter] at the other edge).
  final Future<void> Function(PlayerId playerId)? onHandoffReturn;

  PlayerId? _lastPlayerId;

  final StreamController<bool> _pipChanges = StreamController<bool>.broadcast();

  StreamSubscription<SystemPipStatus>? _statusSubscription;
  PipWindowSnapshot? _desktopSnapshot;

  bool _initialized = false;
  bool _disposed = false;
  bool _isPip = false;
  int _videoWidth = 0;
  int _videoHeight = 0;

  /// Whether this driver has been initialized.
  bool get initialized => _initialized;

  /// Whether the app is currently in picture-in-picture.
  bool get isPip => _isPip;

  /// Picture-in-picture state changes, including system-initiated ones.
  Stream<bool> get onPipChanged => _pipChanges.stream;

  /// Video width fed through [onVideoSize], for the small window's shape.
  int get videoWidth => _videoWidth;

  /// Video height fed through [onVideoSize], for the small window's shape.
  int get videoHeight => _videoHeight;

  /// The video widget's rectangle on screen, assigned by the host as it lays
  /// out; used as the mobile source hint.
  ///
  /// Null or stale costs animation polish, never correctness — the platform
  /// decides the window's size itself (see [SystemPipSourceRect.fromRect]).
  Rect? videoRect;

  /// Whether picture-in-picture can be entered at all on this host.
  ///
  /// Async on mobile (the platform answers), synchronous on desktop (a window
  /// can always be shrunk), false where the feature is unsupported.
  Future<bool> get isAvailable async {
    switch (platform) {
      case PipPlatform.desktop:
        return true;
      case PipPlatform.mobile:
        return await _systemPip?.isAvailable ?? false;
      case PipPlatform.unsupported:
        return false;
    }
  }

  /// Replaces the lifecycle hooks.
  ///
  /// Exists for hosts that build their hooks after the driver and for tests.
  void updateLifecycleHooks(PresentationLifecycleHooks? hooks) {
    lifecycleHooks = hooks ?? const PresentationLifecycleHooks();
  }

  /// Initializes the driver and starts observing platform PiP state.
  ///
  /// Call once, early. Safe to call again.
  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }
    _initialized = true;

    if (platform != PipPlatform.mobile) {
      return;
    }

    final pip = _systemPip ??= NativePipSystemPip();
    try {
      _statusSubscription = pip.statusStream.listen(_handleSystemStatus, onError: (_) {});
    } on Object catch (_) {
      // A platform without the plugin throws when the stream is created rather
      // than reporting unavailability; the driver stays usable either way.
    }
  }

  /// Feeds the latest video size, used for the small window's shape.
  ///
  /// Called again when the picture changes shape — a stream that reports its
  /// size only after the first frame, or one that switches between landscape
  /// and portrait — the open window is re-derived from the new aspect.
  void onVideoSize(int width, int height) {
    if (width <= 0 || height <= 0) {
      return;
    }
    _videoWidth = width;
    _videoHeight = height;
    if (!_isPip || platform != PipPlatform.desktop || !config.lockAspectRatio) {
      return;
    }
    final aspectRatio = _aspectRatio();
    if (aspectRatio != null) {
      unawaited(_desktopWindow?.setAspectRatio(aspectRatio));
    }
  }

  @override
  Future<void> apply(PlayerId playerId, PresentationRequest request) async {
    if (_disposed) {
      throw StateError('PipDriver has been disposed.');
    }
    _lastPlayerId = playerId;

    switch (request.mode) {
      case PresentationMode.pip:
        await _enterPip(playerId);
      case PresentationMode.normal:
        await _leavePip(playerId);
      case PresentationMode.fullscreen:
      case PresentationMode.windowFullscreen:
      case PresentationMode.floating:
        _log.warning(
          'pip driver asked for a mode it does not serve',
          fields: <String, Object?>{'mode': request.mode.name, 'playerId': playerId.value},
        );
        throw UnsupportedError(
          'PipDriver serves picture-in-picture only; mode "${request.mode.name}" '
          'belongs to another driver (see PresentationDriverChain).',
        );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    await _statusSubscription?.cancel();
    _statusSubscription = null;

    await _systemPip?.dispose();

    _isPip = false;
    await DisposeUtils.close(_pipChanges);
  }

  /// Leaves picture-in-picture and restores the captured window snapshot.
  ///
  /// The presentation chain exits PiP through [apply] with a normal request;
  /// a host that owns the driver directly — a close button, a double-tap on
  /// the PiP surface, a back gesture — should not have to synthesize a
  /// request and a player id for that. On mobile the system owns the PiP
  /// window, so this is a no-op there (see `_leavePip`); the state clears
  /// when the system reports the window gone.
  Future<void> exitPip() async {
    if (_disposed) {
      throw StateError('PipDriver has been disposed.');
    }

    await _leavePip(_lastPlayerId ?? _systemPlayerId);
  }

  /// Enters PiP when it is not active, leaves otherwise.
  ///
  /// Entering goes through `_enterPip`, the same sequence a chain-driven
  /// request takes, so platform resolution and logging stay identical.
  Future<void> togglePip() async {
    if (_disposed) {
      throw StateError('PipDriver has been disposed.');
    }

    if (_isPip) {
      await exitPip();
      return;
    }

    await _enterPip(_lastPlayerId ?? _systemPlayerId);
  }

  // ---------------------------------------------------------------------------
  // Entering and leaving
  // ---------------------------------------------------------------------------

  Future<void> _enterPip(PlayerId playerId) async {
    if (_isPip) {
      return;
    }
    await _fire(PresentationLifecyclePhase.beforeEnter, playerId);

    switch (platform) {
      case PipPlatform.desktop:
        await _enterDesktopPip();
      case PipPlatform.mobile:
        await _enterMobilePip(playerId);
      case PipPlatform.unsupported:
        _log.error('pip is not supported on this platform', fields: <String, Object?>{'platform': platform.name});
        throw UnsupportedError('Picture-in-picture is not supported on this platform.');
    }
  }

  Future<void> _leavePip(PlayerId playerId) async {
    if (!_isPip) {
      return;
    }

    if (platform == PipPlatform.desktop) {
      // An app-driven exit is the only one that leaves here; the lifecycle
      // fires around the actual restore, never for a request that will not
      // change anything.
      await _fire(PresentationLifecyclePhase.beforeExit, playerId);
      final snapshot = _desktopSnapshot;
      if (snapshot != null && config.restoreWindowOnExit) {
        await _desktopWindow?.restore(snapshot);
      }
      _desktopSnapshot = null;
      if (_setPip(false)) {
        await _fire(PresentationLifecyclePhase.afterExit, playerId);
      }
      return;
    }

    // Mobile: the app cannot end the system PiP window. The platform ends it
    // when the viewer returns to the app or closes the window, and
    // `_handleSystemStatus` reports that. Claiming an exit here would make the
    // state machine believe a window is gone while it is still on screen, so
    // no lifecycle fires for this no-op.
    if (platform == PipPlatform.unsupported) {
      if (_setPip(false)) {
        await _fire(PresentationLifecyclePhase.afterExit, playerId);
      }
    }
  }

  Future<void> _enterDesktopPip() async {
    final window = _desktopWindow ??= defaultDesktopPipWindow();

    final snapshot = await window.capture();
    _desktopSnapshot = snapshot;

    final size = _smallWindowSize();
    final anchor = snapshot.bounds;

    _log.debug(
      'entering desktop pip',
      fields: <String, Object?>{
        'size': '${size.width.round()}x${size.height.round()}',
        'videoSize':
            '$_videoWidth'
            'x'
            '$_videoHeight',
        'alwaysOnTop': true,
        'skipTaskbar': config.skipTaskbar,
        'lockAspectRatio': config.lockAspectRatio,
        'minSize': '${config.minWidth.round()}x${config.minHeight.round()}',
      },
    );

    await window.applySmallWindow(
      size: size,
      // Bottom-right corner of the previous bounds, clawed back from the
      // screen edge so the window does not sit flush against it.
      position: Offset(
        (anchor.right - size.width - config.cornerSpacing).clamp(0, double.infinity),
        (anchor.bottom - size.height - config.cornerSpacing).clamp(0, double.infinity),
      ),
      aspectRatio: config.lockAspectRatio ? _aspectRatio() : null,
      alwaysOnTop: true,
      // The compact window is user-adjustable: edge-resizing lets the viewer
      // pick their own size after the video-shaped default.
      resizable: true,
      skipTaskbar: config.skipTaskbar,
      title: config.title,
    );

    if (_setPip(true)) {
      await _fire(PresentationLifecyclePhase.afterEnter, _lastPlayerId ?? _systemPlayerId);
    }

    // The viewer's floor for the compact window. Applied last, and non-fatal:
    // a backend whose minimum can also clamp programmatic resizes must not block
    // the entry above, and a failing minimum must not abort the transition after
    // the window already shrank — that left the host's state machine believing
    // PiP never started (no status change), so the room UI kept rendering its
    // previous layout inside the small window. Leaving PiP restores the host's
    // normal minimum, so this never leaks into the restored window.
    try {
      await window.setMinimumSize(Size(config.minWidth, config.minHeight));
    } on Object catch (error, stackTrace) {
      _log.warning(
        'compact minimum size was not applied',
        fields: <String, Object?>{
          'minSize': '${config.minWidth.round()}x${config.minHeight.round()}',
          'error': '$error',
          'stackTrace': '$stackTrace',
        },
      );
    }
  }

  Future<void> _enterMobilePip(PlayerId playerId) async {
    final pip = _systemPip;
    if (pip == null) {
      _log.error('no system pip implementation installed');
      throw UnsupportedError('No system picture-in-picture implementation is installed.');
    }
    if (!await pip.isAvailable) {
      _log.warning('system pip is not available on this device');
      throw UnsupportedError('System picture-in-picture is not available on this device.');
    }
    if (_videoWidth <= 0 || _videoHeight <= 0) {
      _log.error('system pip needs a video size, none reported yet');
      throw StateError('Picture-in-picture needs a video size. Call onVideoSize() first.');
    }

    _log.debug(
      'requesting system pip',
      fields: <String, Object?>{
        'videoSize':
            '$_videoWidth'
            'x'
            '$_videoHeight',
        'sourceRectHint': config.requestSourceRectHint,
      },
    );

    // A handoff backend renders from its own player, not from this app's
    // surface: ask the host what the native player can play, and refuse the
    // transition rather than open a window with nothing in it.
    SystemPipMedia? media;
    final resolver = pipMediaResolver;
    if (resolver != null) {
      media = await resolver(playerId);
      if (media == null) {
        _log.warning(
          'the source cannot be handed to the system player',
          fields: <String, Object?>{'playerId': playerId.value},
        );
        throw UnsupportedError(
          'Picture-in-picture on this platform replays the source in a native '
          'player, and the host could not name a URL it can open. Serve PiP '
          'only for openly playable sources, or install a shrink-style '
          'SystemPip implementation.',
        );
      }
    }

    final status = await pip.enable(
      width: _videoWidth,
      height: _videoHeight,
      sourceRect: config.requestSourceRectHint ? SystemPipSourceRect.fromRect(videoRect) : null,
      media: media,
    );

    if (status == SystemPipStatus.unavailable) {
      _log.error('the platform refused to enter pip');
      throw UnsupportedError('The platform refused to enter picture-in-picture.');
    }

    await _handleSystemStatus(status);
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  Future<void> _handleSystemStatus(SystemPipStatus status) async {
    final active = status == SystemPipStatus.enabled || status == SystemPipStatus.automatic;
    // The platform also ends picture-in-picture on its own (the viewer returned
    // to the app or closed the window); recording the raw status is what shows
    // a state that changed without the app asking for it.
    _log.debug('system pip status', fields: <String, Object?>{'status': status.name, 'active': active});
    // A system-initiated change has no "before" point, so only the settled
    // after-hook fires for it.
    if (_setPip(active)) {
      await _fire(
        active ? PresentationLifecyclePhase.afterEnter : PresentationLifecyclePhase.afterExit,
        _lastPlayerId ?? _systemPlayerId,
      );
      // A handoff backend keeps a second player alive while the window is up;
      // once the system says it is gone, the host's engine is the picture's
      // home again and must be handed back (resume, position sync).
      if (!active && platform == PipPlatform.mobile) {
        final returnHandoff = onHandoffReturn;
        if (returnHandoff != null) {
          try {
            await returnHandoff(_lastPlayerId ?? _systemPlayerId);
          } on Object catch (error, stackTrace) {
            _log.warning(
              'pip handoff return failed',
              error: error,
              stackTrace: stackTrace,
              fields: <String, Object?>{'playerId': (_lastPlayerId ?? _systemPlayerId).value},
            );
          }
        }
      }
    }
  }

  bool _setPip(bool value) {
    if (value == _isPip) {
      return false;
    }
    _isPip = value;
    _log.info(
      value ? 'pip entered' : 'pip left',
      fields: <String, Object?>{
        'platform': platform.name,
        'videoSize':
            '$_videoWidth'
            'x'
            '$_videoHeight',
      },
    );
    if (!_pipChanges.isClosed) {
      _pipChanges.add(value);
    }
    return true;
  }

  /// Runs one lifecycle hook and reports failures without letting them reach
  /// the transition caller: hooks observe the transition, they never veto it.
  Future<void> _fire(PresentationLifecyclePhase phase, PlayerId playerId) async {
    final hooks = lifecycleHooks;
    final hook = switch (phase) {
      PresentationLifecyclePhase.beforeEnter => hooks.beforeEnter,
      PresentationLifecyclePhase.afterEnter => hooks.afterEnter,
      PresentationLifecyclePhase.beforeExit => hooks.beforeExit,
      PresentationLifecyclePhase.afterExit => hooks.afterExit,
    };
    if (hook == null) {
      return;
    }
    try {
      await hook(PresentationLifecycleEvent(phase: phase, playerId: playerId, mode: PresentationMode.pip));
    } on Object catch (error, stackTrace) {
      _log.warning(
        'presentation lifecycle hook failed',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'phase': phase.name, 'playerId': playerId.value, 'mode': PresentationMode.pip.name},
      );
    }
  }

  /// Small window size, following the video's orientation.
  ///
  /// The configured [PipConfig.width] is the window's *long* side in both
  /// cases and [PipConfig.height] the short one, so a landscape stream gets a
  /// 320x180 window and a portrait stream a 180x320 one. Keeping one dimension
  /// fixed in each direction is what makes the small window read as the same
  /// size regardless of the video's shape; deriving the short side from
  /// `height` instead would shrink portrait windows to a sliver.
  ///
  /// An unknown video size falls back to the configured pair unchanged.
  Size _smallWindowSize() {
    if (_videoWidth <= 0 || _videoHeight <= 0) {
      return Size(config.width, config.height);
    }

    final orientation = VideoOrientation.fromSize(_videoWidth, _videoHeight);
    if (orientation == VideoOrientation.landscape) {
      final ratio = _videoWidth / _videoHeight;
      return Size(config.width, (config.width / ratio).roundToDouble());
    }
    if (orientation == VideoOrientation.portrait) {
      final ratio = _videoHeight / _videoWidth;
      return Size((config.width / ratio).roundToDouble(), config.width);
    }
    return Size(config.width, config.height);
  }

  /// Aspect ratio to lock the desktop window to, or null when unknown.
  double? _aspectRatio() {
    if (_videoWidth <= 0 || _videoHeight <= 0) {
      return null;
    }
    return _videoWidth / _videoHeight;
  }
}
