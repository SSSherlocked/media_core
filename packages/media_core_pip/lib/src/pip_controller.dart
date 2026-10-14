import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_core/media_core.dart';

import 'package:media_core_pip/src/pip_config.dart';
import 'package:media_core_pip/src/pip_driver.dart';

/// Decision trail for the small-window handover.
///
/// `presentation/debug` answers the question that a bug report about PiP always
/// asks: was the window not opened because the policy said no, because the
/// player was already gone, or because the platform refused?
final LogModule _log = MediaCoreLog.of(LogCategory.presentation);

/// Ledger of the small window's surface.
///
/// Picture-in-picture holds one extra surface on top of the player the kernel
/// already counts: on desktop a second window with its own texture, on mobile the
/// system's own surface. One item is the whole footprint, which is the point —
/// it is small, and a report that omits it would suggest the mode is free.
final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.pip);

/// When the small window should open on its own.
///
/// Each flag is a decision the viewer makes in settings, and each is separate:
/// someone may want the window when they leave the page but not when they
/// switch apps, or the other way round.
final class PipAutoEnterPolicy {
  /// Chooses which triggers may open the window on their own.
  const PipAutoEnterPolicy({this.onPageExit = true, this.onAppBackground = true, this.requirePlaying = true});

  /// Caller-accepted defaults: both triggers, and only while playing.
  static const PipAutoEnterPolicy defaults = PipAutoEnterPolicy();

  /// Enter when the page showing the player goes away.
  final bool onPageExit;

  /// Enter when the app moves to the background.
  final bool onAppBackground;

  /// Require playback to be running.
  ///
  /// On by default: opening a small window for a paused video shows a frozen
  /// frame the viewer did not ask for, which reads as a bug.
  final bool requirePlaying;

  /// Returns a copy with the named flags replaced, leaving the rest as-is.
  ///
  /// The policy is immutable and read at trigger time, so a host that flips one
  /// setting in response to its own viewer preference builds from this instead
  /// of mutating a policy a pending trigger may already be evaluating.
  PipAutoEnterPolicy copyWith({bool? onPageExit, bool? onAppBackground, bool? requirePlaying}) {
    return PipAutoEnterPolicy(
      onPageExit: onPageExit ?? this.onPageExit,
      onAppBackground: onAppBackground ?? this.onAppBackground,
      requirePlaying: requirePlaying ?? this.requirePlaying,
    );
  }
}

/// What the small window is currently carrying.
final class PipSession {
  /// Describes the small window's content at one point in time.
  const PipSession({this.playerId, this.active = false, this.reason});

  /// PlayerIdentity being carried, or `null` when nothing is.
  final PlayerId? playerId;

  /// Whether the small window is up.
  final bool active;

  /// Why the last transition happened, for logs and for a host that wants to
  /// explain it.
  final String? reason;

  @override
  String toString() => 'PipSession(${active ? 'active' : 'idle'}${playerId == null ? '' : ', $playerId'})';
}

/// Owns the handover between a page and the picture-in-picture window.
///
/// Distinct from the core `presentation` module's `PipController`, which owns
/// the *logical mode state* (entered, transitioning, capabilities). This class
/// owns the *session*: which player is carried, when the window opens on its
/// own, and how the carried player is rendered. The mode controller answers
/// "is the app in PiP?"; this one answers "what is playing in it, and where did
/// it come from?".
///
/// Responsibilities:
///
/// - hold the player the small window carries, above the page's lifetime
/// - decide when to enter and leave, from an [PipAutoEnterPolicy]
/// - build the surface the small window renders
///
/// It does not:
///
/// - own the player (the kernel does; see below)
/// - speak to the platform ([PipDriver] does)
/// - render chrome around the video (the host does)
///
/// ## The handover, and why nothing is re-created
///
/// A viewer who leaves the page while a stream is playing expects the picture
/// to continue — same stream, same position, no gap. That rules out creating a
/// second player for the small window: a new player would re-open the source,
/// re-buffer, and pay for a second decode of the same stream.
///
/// The framework already has the mechanism for this. A [PlayerHandle] belongs
/// to the kernel, not to a page; a video surface is a widget built *from* that
/// handle (`MediaPlayerView(handle: ...)`). So handing over is not a transfer of
/// ownership at all: the page's widget simply goes away with the page, and this
/// controller builds another widget for the same handle in the small window.
///
/// The one thing the host must do is **not dispose the handle** when the page
/// that showed it goes away. Dispose it and there is nothing to carry — the
/// controller reports that rather than opening an empty window.
///
/// ## Page exit and app background are different events
///
/// Leaving the page usually means the host is about to pop a route while the
/// app stays in the foreground; backgrounding the app can happen while the page
/// is still mounted (the viewer pressed home). Both are reported here so the
/// policy can treat them separately, and both are host-triggered because only
/// the host knows when its own navigation or lifecycle events happen. The app
/// side can be wired to the core's `AppLifecycleDriver`, which already observes
/// the platform lifecycle.
final class PipSessionController {
  /// Wires a driver to the registry the carried players are looked up in.
  ///
  /// The registry is separate from the kernel on purpose: a host that owns its
  /// players outside a [PlayerKernel] can hand over its own lookup instead of
  /// losing the handover.
  PipSessionController({
    required PipDriver driver,
    required PortablePlayerRegistry registry,
    this.config = PipConfig.defaults,
    this.autoEnter = PipAutoEnterPolicy.defaults,
    this.surfaceBuilder,
  }) : _driver = driver,
       _registry = registry;

  /// Builds a controller over a kernel's players.
  factory PipSessionController.forKernel({
    required PipDriver driver,
    required PlayerKernel kernel,
    PipConfig config = PipConfig.defaults,
    PipAutoEnterPolicy autoEnter = PipAutoEnterPolicy.defaults,
    Widget Function(BuildContext context, PlayerId playerId)? surfaceBuilder,
  }) {
    return PipSessionController(
      driver: driver,
      registry: KernelPortablePlayerRegistry(kernel),
      config: config,
      autoEnter: autoEnter,
      surfaceBuilder: surfaceBuilder,
    );
  }

  /// This instance's key in the shared account: a module can have several
  /// live instances, and a report sums their contributions rather than
  /// keeping whichever reported last.
  late final String _memoryKey = memoryContributorKey(this);

  final PipDriver _driver;
  final PortablePlayerRegistry _registry;

  /// Geometry and platform tunables.
  final PipConfig config;

  /// When the window opens on its own.
  final PipAutoEnterPolicy autoEnter;

  /// Builds the small window's video surface for a player id.
  ///
  /// Defaults to the framework's own [MediaPlayerView] over the carried handle.
  /// A host overrides it to add controls, a danmaku layer or gestures — or to
  /// render a player the framework does not own, which is why the callback takes
  /// the id rather than a handle: an id always exists, a handle does not.
  final Widget Function(BuildContext context, PlayerId playerId)? surfaceBuilder;

  final StreamController<PipSession> _sessionController = StreamController<PipSession>.broadcast();

  PlayerId? _playerId;
  bool _disposed = false;

  /// PlayerIdentity currently carried, or `null`.
  PlayerId? get playerId => _playerId;

  /// Whether the small window is up.
  bool get isActive => _driver.isPip;

  /// Session changes.
  Stream<PipSession> get onSessionChanged => _sessionController.stream;

  /// Whether a player is being carried and still exists in the kernel.
  bool get hasCarriedPlayer {
    final id = _playerId;
    if (id == null) {
      return false;
    }
    final player = _registry.find(id);
    return player != null && !player.isDisposed;
  }

  /// Takes [playerId] into the small window and shows it.
  ///
  /// The handle must still exist: a page that disposed its player has nothing
  /// to hand over, and pretending otherwise would show a window with no video.
  Future<void> enter(PlayerId playerId, {String reason = 'requested'}) async {
    _ensureNotDisposed();

    final player = _registry.find(playerId);
    if (player == null || player.isDisposed) {
      _log.error(
        'cannot enter pip: player is gone',
        fields: <String, Object?>{'playerId': playerId.value, 'reason': reason},
      );
      throw StateError(
        'PlayerIdentity $playerId is gone: the page disposed it instead of leaving it to the kernel to carry.',
      );
    }

    _log.info(
      'entering pip',
      fields: <String, Object?>{
        'playerId': playerId.value,
        'reason': reason,
        'videoWidth': player.videoWidth,
        'videoHeight': player.videoHeight,
      },
    );

    _playerId = playerId;
    _emit(PipSession(playerId: playerId, active: true, reason: reason));

    _driver.onVideoSize(player.videoWidth, player.videoHeight);
    await _driver.initialize();
    await _driver.apply(playerId, PresentationRequest.pip());

    _reportMemory(active: _driver.isPip, playerId: playerId);
    _log.debug('pip window applied', fields: <String, Object?>{'active': _driver.isPip});
  }

  /// Leaves the small window. The player stays alive for the host to re-attach.
  Future<void> exit({String reason = 'requested'}) async {
    _ensureNotDisposed();
    _log.info('leaving pip', fields: <String, Object?>{'playerId': _playerId?.value, 'reason': reason});
    await _driver.initialize();
    await _driver.apply(_playerId ?? PlayerId('pip-idle'), PresentationRequest.normal());
    _emit(PipSession(playerId: _playerId, reason: reason));
    _reportMemory(active: false, playerId: _playerId);
  }

  /// Enters if idle, leaves if active.
  Future<void> toggle(PlayerId playerId) =>
      isActive ? exit(reason: 'toggled off') : enter(playerId, reason: 'toggled on');

  /// Reports that the page showing [playerId] is going away.
  ///
  /// Returns whether the window was opened, so a host can log or react.
  Future<bool> onPageExit({required PlayerId playerId, required bool playing}) {
    if (!autoEnter.onPageExit) {
      return Future<bool>.value(false);
    }
    return _autoEnter(playerId, playing: playing, reason: 'page exit');
  }

  /// Reports that the app moved to the background while showing [playerId].
  Future<bool> onAppBackgrounded({required PlayerId playerId, required bool playing}) {
    if (!autoEnter.onAppBackground) {
      return Future<bool>.value(false);
    }
    return _autoEnter(playerId, playing: playing, reason: 'app backgrounded');
  }

  /// Reports that the app came back to the foreground.
  ///
  /// The window is left alone: the viewer may have started it deliberately, and
  /// closing it here would undo a choice they made.
  Future<void> onAppResumed() async {
    _ensureNotDisposed();
  }

  /// Builds the small window's surface for [playerId].
  Widget buildSurface(BuildContext context, PlayerId playerId, {BoxFit fit = BoxFit.contain}) {
    final builder = surfaceBuilder;
    if (builder != null) {
      return builder(context, playerId);
    }

    final handle = _registry.find(playerId)?.handle;
    if (handle == null) {
      throw StateError(
        'PlayerIdentity $playerId has no framework handle; supply surfaceBuilder to render a host-owned player.',
      );
    }
    return MediaPlayerView(handle: handle, fit: fit);
  }

  /// Releases the controller.
  ///
  /// The player is left running: it belongs to the kernel, and a host that
  /// disposes this controller while the window is up is closing the window, not
  /// stopping playback.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _memory.withdraw(_memoryKey);
    await DisposeUtils.close(_sessionController);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<bool> _autoEnter(PlayerId playerId, {required bool playing, required String reason}) async {
    _ensureNotDisposed();
    if (autoEnter.requirePlaying && !playing) {
      _log.debug(
        'auto-enter skipped: not playing',
        fields: <String, Object?>{'playerId': playerId.value, 'trigger': reason},
      );
      return false;
    }
    if (isActive && _playerId == playerId) {
      _log.debug(
        'auto-enter skipped: already carrying this player',
        fields: <String, Object?>{'playerId': playerId.value, 'trigger': reason},
      );
      return true;
    }
    await enter(playerId, reason: reason);
    return true;
  }

  /// Reports the carried surface.
  void _reportMemory({required bool active, PlayerId? playerId}) {
    _memory.report(
      _memoryKey,
      items: active ? 1 : 0,
      bytes: active ? MemoryEstimates.videoSurface : 0,
      note: active ? 'carrying ${playerId?.value}' : 'idle',
    );
  }

  void _emit(PipSession session) {
    if (!_sessionController.isClosed) {
      _sessionController.add(session);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PipSessionController has been disposed.');
    }
  }
}
