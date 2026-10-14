import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show Rect;
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode, SystemUiOverlay;
import 'package:media_core/media_core.dart';
import 'package:media_core_fullscreen/src/fullscreen_config.dart';
import 'package:media_core_fullscreen/src/fullscreen_window.dart';
import 'package:media_core_fullscreen/src/window_manager_fullscreen_window.dart';

/// Decision trail for fullscreen.
///
/// Two questions come up whenever fullscreen "does not work": which variant the
/// host actually asked for (screen-wide or window-wide), and which fit strategy
/// the video's orientation selected. Both are recorded on every transition.
final LogModule _log = MediaCoreLog.of(LogCategory.presentation);

// Fullscreen deliberately has no memory account: it is a layout and window-state
// change over the *same* surface the page already had, so it allocates nothing a
// report could attribute to it. The player it renders is counted by the kernel,
// and the video surface by whichever module built it. A zero-valued entry here
// would suggest the mode was measured instead of saying it holds nothing.

/// Which fullscreen variants the host can actually present.
enum FullscreenPlatform {
  /// Windows, macOS, Linux: system fullscreen is a window state.
  desktop,

  /// Android/iOS: there is no window to make fullscreen, so "fullscreen" means
  /// the host hides the system UI and fills the screen.
  mobile,

  /// Web and anything else.
  unsupported;

  /// Resolves this host's family.
  static FullscreenPlatform resolve() {
    // PlatformUtils is the core's single answer to "what am I running on";
    // re-deriving it here from Platform would let the two drift apart.
    if (kIsWeb) {
      return FullscreenPlatform.unsupported;
    }
    if (PlatformUtils.isDesktop) {
      return FullscreenPlatform.desktop;
    }
    if (PlatformUtils.isMobile) {
      return FullscreenPlatform.mobile;
    }
    return FullscreenPlatform.unsupported;
  }
}

/// Owns both fullscreen variants.
///
/// Responsibilities:
///
/// - enter and leave system fullscreen ([PresentationMode.fullscreen])
/// - track window-level fullscreen ([PresentationMode.windowFullscreen])
/// - answer which fit strategy the current video orientation wants
/// - keep the two variants mutually exclusive
///
/// It does not:
///
/// - draw the fullscreen layout (the host does)
/// - decide when to go fullscreen on rotation (the presentation policy does)
/// - own picture-in-picture or the small windows (separate packages do)
///
/// ## The two variants
///
/// [PresentationMode.fullscreen] is the platform's own fullscreen: a desktop
/// window covers the screen, a phone hides the system UI. It is a real platform
/// state, so it can fail and has to be restored on exit. On mobile the driver
/// performs the immersive switch itself (`SystemUiMode`); the orientation to
/// lock and the status bar styling are presentation policy and stay with the
/// host.
///
/// [PresentationMode.windowFullscreen] is the host's layout: the video fills
/// the application window while the window stays a window. Nothing platform
/// facing happens here, and the mode is tracked so that PiP, the small windows
/// and the host's own chrome all agree on what is being left when the mode
/// changes.
///
/// Because one driver owns both, it is also the place that guarantees they do
/// not overlap: entering window fullscreen while the system fullscreen is
/// active leaves the system one first. That hand-off cannot be delegated to the
/// driver chain, which only knows about *different* drivers.
///
/// ## Orientation
///
/// Mobile "fullscreen" is not one layout per platform but one per orientation:
/// portrait media fills a portrait screen, landscape media takes the long axis,
/// and a portrait stream on a landscape screen is either letterboxed or
/// rotated. The driver answers that question through `strategyFor` so a host
/// does not re-derive it, and configures it through [FullscreenConfig].
final class FullscreenDriver implements KernelPresentationDriver {
  /// Creates the driver.
  FullscreenDriver({
    this.config = FullscreenConfig.defaults,
    FullscreenPlatform? platform,
    FullscreenWindow? desktopWindow,
    PresentationLifecycleHooks? lifecycleHooks,
  }) : platform = platform ?? FullscreenPlatform.resolve(),
       _desktopWindow = desktopWindow,
       lifecycleHooks = lifecycleHooks ?? const PresentationLifecycleHooks();

  /// Tunables, including the per-orientation fit strategies.
  final FullscreenConfig config;

  /// Platform family this driver serves.
  final FullscreenPlatform platform;

  FullscreenWindow? _desktopWindow;

  /// Lifecycle hooks fired around enter/exit transitions. Replaceable for
  /// hosts that build their hooks after the driver; see [updateLifecycleHooks].
  PresentationLifecycleHooks lifecycleHooks;

  PlayerId? _lastPlayerId;

  final StreamController<bool> _fullscreenChanges = StreamController<bool>.broadcast();

  Rect? _preFullscreenBounds;

  static final _togglePlayerId = PlayerId('fullscreen-toggle');

  bool _initialized = false;
  bool _disposed = false;
  bool _isSystemFullscreen = false;
  bool _isWindowFullscreen = false;
  int _videoWidth = 0;
  int _videoHeight = 0;

  /// Whether this driver has been initialized.
  bool get initialized => _initialized;

  /// Whether system fullscreen is active.
  bool get isSystemFullscreen => _isSystemFullscreen;

  /// Whether window-level fullscreen is active.
  bool get isWindowFullscreen => _isWindowFullscreen;

  /// Whether either variant is active.
  bool get isAnyFullscreen => _isSystemFullscreen || _isWindowFullscreen;

  /// Fullscreen state changes (either variant).
  Stream<bool> get onFullscreenChanged => _fullscreenChanges.stream;

  /// Replaces the lifecycle hooks.
  ///
  /// Exists for hosts that build their hooks after the driver and for tests.
  void updateLifecycleHooks(PresentationLifecycleHooks? hooks) {
    lifecycleHooks = hooks ?? const PresentationLifecycleHooks();
  }

  /// Orientation of the last reported video size.
  VideoOrientation get orientation {
    if (_videoWidth <= 0 || _videoHeight <= 0) {
      return config.fallbackOrientation;
    }
    return VideoOrientation.fromSize(_videoWidth, _videoHeight);
  }

  /// The fit strategy the current orientation wants.
  ///
  /// A host applies this to its fullscreen surface; the driver does not, since
  /// only the host knows what it is drawing into.
  FullscreenFitStrategy get strategy {
    final current = orientation;
    if (current == VideoOrientation.portrait) {
      return config.portraitStrategy;
    }
    return config.landscapeStrategy;
  }

  /// Initializes the driver.
  ///
  /// Call once, early. Safe to call again.
  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }
    _initialized = true;
  }

  /// Feeds the latest video size, used to pick the fit strategy.
  void onVideoSize(int width, int height) {
    if (width <= 0 || height <= 0) {
      return;
    }
    _videoWidth = width;
    _videoHeight = height;
  }

  @override
  Future<void> apply(PlayerId playerId, PresentationRequest request) async {
    if (_disposed) {
      throw StateError('FullscreenDriver has been disposed.');
    }

    _lastPlayerId = playerId;
    final wasAnyFullscreen = isAnyFullscreen;

    _log.info(
      'applying presentation',
      fields: <String, Object?>{
        'mode': request.mode.name,
        'playerId': playerId.value,
        'platform': platform.name,
        'orientation': orientation.name,
        'fit': strategy.name,
        'videoSize':
            '$_videoWidth'
            'x'
            '$_videoHeight',
      },
    );

    switch (request.mode) {
      case PresentationMode.fullscreen:
        if (!wasAnyFullscreen) {
          await _fire(PresentationLifecyclePhase.beforeEnter, playerId, PresentationMode.fullscreen);
        }
        await _enterSystemFullscreen();
        if (!wasAnyFullscreen && isAnyFullscreen) {
          await _fire(PresentationLifecyclePhase.afterEnter, playerId, PresentationMode.fullscreen);
        }
      case PresentationMode.windowFullscreen:
        if (!wasAnyFullscreen) {
          await _fire(PresentationLifecyclePhase.beforeEnter, playerId, PresentationMode.windowFullscreen);
        }
        await _enterWindowFullscreen();
        if (!wasAnyFullscreen && isAnyFullscreen) {
          await _fire(PresentationLifecyclePhase.afterEnter, playerId, PresentationMode.windowFullscreen);
        }
      case PresentationMode.normal:
        await _leaveWithLifecycle(playerId, wasAnyFullscreen);
      case PresentationMode.pip:
      case PresentationMode.floating:
        _log.warning(
          'fullscreen driver asked for a mode it does not serve',
          fields: <String, Object?>{'mode': request.mode.name, 'playerId': playerId.value},
        );
        throw UnsupportedError(
          'FullscreenDriver serves the two fullscreen variants only; mode "${request.mode.name}" '
          'belongs to another driver (see PresentationDriverChain).',
        );
    }

    _notifyIfChanged(wasAnyFullscreen);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    // Leaving the platform state behind on dispose would strand a desktop
    // window in fullscreen after the host has torn the player down.
    final wasAnyFullscreen = isAnyFullscreen;
    if (_isSystemFullscreen) {
      await _leaveSystemFullscreen();
    }
    _isWindowFullscreen = false;
    _notifyIfChanged(wasAnyFullscreen);

    await DisposeUtils.close(_fullscreenChanges);
  }

  /// Leaves whatever fullscreen variant is active and restores the window.
  ///
  /// The presentation chain exits fullscreen through [apply] with a normal
  /// request, but a host that owns the driver directly — an ESC handler, a
  /// back gesture, a fullscreen button that only knows "leave" — should not
  /// have to synthesize a request and a player id for that. No-op when no
  /// fullscreen variant is active.
  Future<void> exitFullscreen() async {
    if (_disposed) {
      throw StateError('FullscreenDriver has been disposed.');
    }

    final wasAnyFullscreen = isAnyFullscreen;
    await _leaveWithLifecycle(_lastPlayerId ?? _togglePlayerId, wasAnyFullscreen);
    _notifyIfChanged(wasAnyFullscreen);
  }

  /// Enters system fullscreen when no fullscreen is active, leaves otherwise.
  ///
  /// Entering goes through [apply] so the transition is logged and the fit
  /// strategy is resolved exactly like a chain-driven enter.
  Future<void> toggleFullscreen() async {
    if (_disposed) {
      throw StateError('FullscreenDriver has been disposed.');
    }

    if (isAnyFullscreen) {
      await exitFullscreen();
      return;
    }

    await apply(_togglePlayerId, PresentationRequest.fullscreen());
  }

  // ---------------------------------------------------------------------------
  // Variants
  // ---------------------------------------------------------------------------

  Future<void> _enterSystemFullscreen() async {
    // The two variants are mutually exclusive, and this driver owns both, so
    // the hand-off happens here rather than in the chain.
    if (_isWindowFullscreen) {
      _setWindowFullscreen(false);
    }
    if (_isSystemFullscreen) {
      return;
    }

    switch (platform) {
      case FullscreenPlatform.desktop:
        final window = _desktopWindow ??= WindowManagerFullscreenWindow();
        if (config.restorePreviousBounds) {
          _preFullscreenBounds = await window.captureBounds();
          _log.debug(
            'captured pre-fullscreen bounds',
            fields: <String, Object?>{'bounds': _preFullscreenBounds?.toString()},
          );
        }
        await window.setFullscreen(value: true);
      case FullscreenPlatform.mobile:
        // Mobile fullscreen is the system UI itself: immersive sticky hides
        // the status and navigation bars for the presentation. The
        // orientation to lock is presentation policy and stays with the host.
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      case FullscreenPlatform.unsupported:
        _log.error('system fullscreen is not supported on this platform');
        throw UnsupportedError('System fullscreen is not supported on this platform.');
    }

    _setSystemFullscreen(true);
  }

  Future<void> _enterWindowFullscreen() async {
    if (_isWindowFullscreen) {
      return;
    }

    if (platform == FullscreenPlatform.unsupported) {
      _log.error('window-level fullscreen is not supported on this platform');
      throw UnsupportedError('Window-level fullscreen is not supported on this platform.');
    }

    // Filling the window while the screen is also fullscreen would leave the
    // host with two active variants and no defined exit.
    if (_isSystemFullscreen) {
      _log.debug('handing over from system fullscreen to window fullscreen');
      await _leaveSystemFullscreen();
    }

    _setWindowFullscreen(true);
  }

  Future<void> _leaveFullscreen() async {
    if (_isSystemFullscreen) {
      await _leaveSystemFullscreen();
    }
    if (_isWindowFullscreen) {
      _setWindowFullscreen(false);
    }
  }

  /// Wraps [_leaveFullscreen] with the exit lifecycle.
  ///
  /// The lifecycle tracks the any-fullscreen level, so a variant hand-off
  /// (window fullscreen → system fullscreen, routed through
  /// `_enterSystemFullscreen`) stays fullscreen and fires no exit hooks here.
  Future<void> _leaveWithLifecycle(PlayerId playerId, bool wasAnyFullscreen) async {
    if (!wasAnyFullscreen) {
      await _leaveFullscreen();
      return;
    }
    final mode = _isSystemFullscreen ? PresentationMode.fullscreen : PresentationMode.windowFullscreen;
    await _fire(PresentationLifecyclePhase.beforeExit, playerId, mode);
    await _leaveFullscreen();
    if (!isAnyFullscreen) {
      await _fire(PresentationLifecyclePhase.afterExit, playerId, mode);
    }
  }

  /// Runs one lifecycle hook and reports failures without letting them reach
  /// the transition caller: hooks observe the transition, they never veto it.
  Future<void> _fire(PresentationLifecyclePhase phase, PlayerId playerId, PresentationMode mode) async {
    final hook = switch (phase) {
      PresentationLifecyclePhase.beforeEnter => lifecycleHooks.beforeEnter,
      PresentationLifecyclePhase.afterEnter => lifecycleHooks.afterEnter,
      PresentationLifecyclePhase.beforeExit => lifecycleHooks.beforeExit,
      PresentationLifecyclePhase.afterExit => lifecycleHooks.afterExit,
    };
    if (hook == null) {
      return;
    }
    try {
      await hook(PresentationLifecycleEvent(phase: phase, playerId: playerId, mode: mode));
    } on Object catch (error, stackTrace) {
      _log.warning(
        'presentation lifecycle hook failed',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'phase': phase.name, 'playerId': playerId.value, 'mode': mode.name},
      );
    }
  }

  Future<void> _leaveSystemFullscreen() async {
    if (platform == FullscreenPlatform.desktop) {
      final window = _desktopWindow ??= WindowManagerFullscreenWindow();
      await window.setFullscreen(
        value: false,
        restoreBounds: config.restorePreviousBounds ? _preFullscreenBounds : null,
      );
    } else if (platform == FullscreenPlatform.mobile) {
      // Restores the status and navigation bars. The status bar styling and
      // the orientation release are host policy and stay there.
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    }
    _preFullscreenBounds = null;
    _setSystemFullscreen(false);
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  void _setSystemFullscreen(bool value) {
    if (value != _isSystemFullscreen) {
      _log.debug('system fullscreen variant changed', fields: <String, Object?>{'active': value});
    }
    _isSystemFullscreen = value;
  }

  void _setWindowFullscreen(bool value) {
    if (value != _isWindowFullscreen) {
      _log.debug('window fullscreen variant changed', fields: <String, Object?>{'active': value});
    }
    _isWindowFullscreen = value;
  }

  /// Publishes the final value once per transition.
  ///
  /// Handing over between the two variants passes through a moment where
  /// neither is set. Publishing each flag change would emit that moment as a
  /// `false`, and a host reacting to it would flash its non-fullscreen chrome
  /// mid-transition — so only the settled value is reported.
  void _notifyIfChanged(bool previous) {
    final current = isAnyFullscreen;
    if (previous == current || _fullscreenChanges.isClosed) {
      return;
    }
    _log.debug('fullscreen state settled', fields: <String, Object?>{'fullscreen': current});
    _fullscreenChanges.add(current);
  }
}
