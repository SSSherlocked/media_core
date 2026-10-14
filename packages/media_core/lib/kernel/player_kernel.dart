import 'dart:async';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:media_core/adapter/player_adapter_capabilities.dart' show PlayerAdapterCapabilities;
import 'package:media_core/adapter/player_adapter_config.dart';
import 'package:media_core/adapter/player_adapter_context.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/adapter/player_adapter_selector.dart';
import 'package:media_core/coordinator/global_player_coordinator.dart';
import 'package:media_core/core/player_config.dart';
import 'package:media_core/core/player_identity.dart';
import 'package:media_core/event/event_context.dart';
import 'package:media_core/event/event_priority.dart';
import 'package:media_core/event/event_subscription.dart';
import 'package:media_core/event/player_event.dart';
import 'package:media_core/event/player_event_bus.dart';
import 'package:media_core/event/player_event_type.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/kernel/kernel_audio_driver.dart';
import 'package:media_core/kernel/kernel_options.dart';
import 'package:media_core/kernel/kernel_presentation_driver.dart';
import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/planning/default_media_source_planner.dart';
import 'package:media_core/planning/media_source_plan.dart';
import 'package:media_core/planning/media_source_planner.dart';
import 'package:media_core/platform/platform_capabilities.dart';
import 'package:media_core/platform/platform_codec_capabilities.dart';
import 'package:media_core/platform/platform_device_profile.dart';
import 'package:media_core/platform/platform_provider.dart';
import 'package:media_core/pool/player_pool.dart';
import 'package:media_core/preload/preload_manager.dart';
import 'package:media_core/preload/preload_priority.dart';
import 'package:media_core/preload/preload_request.dart';
import 'package:media_core/presentation/presentation_request.dart';
import 'package:media_core/screenshot/player_screenshot.dart';
import 'package:media_core/screenshot/screenshot_options.dart';
import 'package:media_core/session/player_session.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_source_bridge.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/source/source_format.dart';
import 'package:media_core/source/source_media_type.dart';
import 'package:media_core/source/source_protocol.dart';
import 'package:media_core/source/source_service.dart';
import 'package:media_core_logging/media_core_logging.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// The orchestration root of the media core.
///
/// [PlayerKernel] turns the individual modules into one working
/// player framework:
///
/// ```text
/// MediaSource (Progressive / Composite)      PlayerSource
///     │  MediaSourcePlanner + capabilities        │  SourceService (resolve)
///     ▼                                           ▼
/// DirectPlan / CompositePlan / UnsupportedPlan
///     │  bridge to PlayerSource                   │
///     └────────────────┬──────────────────────────┘
///                      ▼
///              PlayerAdapterSelector ──▶ PlayerAdapterRegistry
///                      │  best backend
///                      ▼
///              PlayerHandle ──▶ PlayerAdapter (media_kit / ijk / video_player / ...)
///                      │
///                      ├── PlayerSession + SessionController
///                      ├── PlaybackController
///                      ├── LifecycleController
///                      ├── RecoveryLadder (report → escalate → reopen / next line / next backend)
///                      ├── GlobalPlayerCoordinator (audio/page/resource/presentation)
///                      ├── PlayerPool (instance reuse)
///                      ├── PreloadManager (warm-up bookkeeping)
///                      └── PlayerEventBus (normalized events)
/// ```
///
/// [create] is the PlayerSource entry; [createFromMedia] is the
/// MediaSource entry and the one a provider that produces composite
/// DASH pairs should reach for.
///
/// Responsibilities:
///
/// - create and release players
/// - select backends for sources
/// - provide the per-player recovery context (registry, selector, budget)
/// - expose a global event stream
///
/// It does not:
///
/// - decode media
/// - own per-player playback state
/// - drive recovery across backends
/// - render video
///
/// Those belong to:
///
/// - PlayerAdapter
/// - PlayerHandle / PlaybackController
/// - RecoveryLadder
/// - presentation widgets
///
/// Example:
///
/// ```dart
/// final kernel = PlayerKernel()
///   ..registerBackend(MediaKitPlayerAdapter.defaultRegistration());
///
/// final handle = await kernel.create(
///   config: PlayerConfig.defaults,
///   source: TestSourceFactory.httpMp4(),
/// );
/// await handle.play();
/// ```
final class PlayerKernel with WidgetsBindingObserver {
  /// Creates a kernel.
  ///
  /// Every dependency is optional and lazily constructed, so
  /// `PlayerKernel()` works out of the box once at least one
  /// backend is registered.
  PlayerKernel({
    PlayerAdapterRegistry? registry,
    PlayerAdapterSelector? selector,
    SourceService? sourceService,
    PlayerEventBus? eventBus,
    PlayerPool? pool,
    PreloadManager? preloadManager,
    GlobalPlayerCoordinator? coordinator,
    MediaSourcePlanner? planner,
    this.options = const KernelOptions(),
  }) : registry = registry ?? PlayerAdapterRegistry(),
       _selector = selector,
       _sourceService = sourceService,
       _eventBus = eventBus ?? PlayerEventBus(),
       _pool = pool ?? PlayerPool(),
       _preloadManager = preloadManager ?? PreloadManager(),
       _coordinator = coordinator ?? GlobalPlayerCoordinator(),
       _planner = planner ?? const DefaultMediaSourcePlanner() {
    _trackActivePlayer();

    // A capability package may have installed a process-wide media-session
    // driver; taking it here is what makes the surfaces automatic for every
    // player this kernel ever creates. `attachAudio` still wins for a host that
    // wants a specific driver, and assigning over the same instance is a no-op.
    if (options.shouldAttachAudio(hasFactory: audioDriverFactory != null)) {
      _audioDriver = audioDriverFactory!.call();
    }

    if (options.pauseWhenBackgrounded) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observesLifecycle = true;
      } on Object {
        // No Flutter binding in this process: nothing to observe, and the
        // players carry on. A host that wants the pause asks for it from a
        // widget context instead.
      }
    }
  }

  /// Registry of available backends.
  final PlayerAdapterRegistry registry;

  final PlayerAdapterSelector? _selector;
  final SourceService? _sourceService;
  final PlayerEventBus _eventBus;
  final PlayerPool _pool;
  final PreloadManager _preloadManager;
  final GlobalPlayerCoordinator _coordinator;
  final MediaSourcePlanner _planner;

  /// Kernel-wide options.
  final KernelOptions options;

  final Map<PlayerId, PlayerHandle> _handles = {};

  /// Whether this kernel is registered with the app-lifecycle broadcast.
  ///
  /// Tracked because the registration is conditional on
  /// [KernelOptions.pauseWhenBackgrounded] *and* on a binding existing: a
  /// pure-Dart host (a CLI, an isolate, a suite without a platform) gets no
  /// observer, and `removeObserver` for one that was never added is a wrong call.
  bool _observesLifecycle = false;

  /// Ledger of the players this kernel holds.
  /// This instance's key in the shared account.
  late final String _memoryKey = memoryContributorKey(this);

  final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.kernel);

  KernelAudioDriver? _audioDriver;

  /// The presentation driver this kernel publishes window requests to, if any.
  ///
  /// Assigned directly (or cleared through [detachPresentation]) by a host that
  /// owns a presentation capability package; null means fullscreen and PiP
  /// requests from this kernel throw instead of being half-applied.
  KernelPresentationDriver? presentationDriver;

  /// The platform capability source players are created from, if any.
  ///
  /// Assigned directly (or cleared through [detachPlatformProvider]) once the
  /// host has loaded a provider. Without one, every session and every adapter is
  /// handed the optimistic defaults in `PlatformCapabilities` — playback works,
  /// but nothing knows what the device can actually decode.
  ///
  /// Set it before creating players: the provider is consulted once per created
  /// player and its answers are carried into the session and adapter contexts,
  /// so a backend can pick a decoder from facts instead of guesses. It is never
  /// awaited — the provider caches its own probe, and a player created while
  /// the probe is still running gets the provider's documented "unknown"
  /// answers rather than waiting for a device query before it can start.
  ///
  /// ```dart
  /// final provider = await NativePlatformProvider.load();
  /// kernel.platformProvider = provider;
  /// ```
  PlatformProvider? platformProvider;

  /// The driver a new kernel takes when nothing else was attached.
  ///
  /// The platform has exactly one media notification per app, so this slot is
  /// process-wide and holds one driver: a capability package installs it once
  /// (`MediaSessionBootstrap.enable()` in `media_core_mediasession`), and every
  /// kernel created afterwards publishes to it without the host wiring
  /// anything per player.
  ///
  /// Null means the app has not enabled the capability, which is the default:
  /// posting notifications and starting a foreground service is an app-level
  /// decision, not something a library does behind a host's back.
  ///
  /// A kernel that must stay off the platform surfaces passes
  /// `KernelOptions(autoAttachAudio: false)`; a kernel created *before* the
  /// capability was enabled attaches it explicitly with `attachAudio`.
  static KernelAudioDriver Function()? audioDriverFactory;
  StreamSubscription<PlayerEvent>? _activeTrackingSub;
  PlayerHandle? _activeHandle;

  /// Lazy selector bound to [registry].
  PlayerAdapterSelector get selector => _selector ?? PlayerAdapterSelector(registry);

  /// The planner consulted by [createFromMedia] before any adapter
  /// sees a source.
  MediaSourcePlanner get mediaSourcePlanner => _planner;

  /// Runs the planner against [source] without touching any
  /// adapter or handle.
  ///
  /// UI layers and pre-flight checks use this to answer
  /// "can this be played, and if so by whom" before the caller
  /// commits to a [create] or [createFromMedia] — for example, to
  /// disable the 4K HDR option on a build whose registry contains
  /// only Fijk.
  ///
  /// The method never throws for an unsupported source: an
  /// [UnsupportedPlan] is a legitimate answer and the caller decides
  /// what to do with it. A [StateError] from
  /// [PlayerAdapterSelector.requireMedia] still surfaces, because "no
  /// backend registered at all" is a configuration bug rather than a
  /// planning outcome.
  ({PlayerAdapterRegistration registration, MediaSourcePlan plan}) planFor(
    MediaSource source, {
    String? preferredBackend,
  }) {
    final registration = selector.requireMedia(source, preferredId: preferredBackend);
    final plan = _planner.plan(source, registration.capabilities);

    return (registration: registration, plan: plan);
  }

  /// Global event bus.
  PlayerEventBus get eventBus => _eventBus;

  /// Global player pool.
  PlayerPool get pool => _pool;

  /// Global preload manager.
  PreloadManager get preloadManager => _preloadManager;

  /// Cross-player coordination layer.
  GlobalPlayerCoordinator get coordinator => _coordinator;

  /// The currently active player, if any.
  ///
  /// The active player is the one most recently playing. Pausing
  /// keeps a player active; stopping or releasing clears this.
  PlayerHandle? get activeHandle => _activeHandle;

  // ---------------------------------------------------------------------------
  // Backend registration
  // ---------------------------------------------------------------------------

  /// Registers a backend.
  ///
  /// Logged at info: which backends exist and with what priority is the
  /// first question behind "why is this engine playing?", and the answer
  /// has to be visible without reading the application's setup code.
  void registerBackend(PlayerAdapterRegistration registration) {
    registry.register(registration);

    MediaCoreLog.info(
      LogCategory.fallback,
      'backend registered: ${registration.id} (priority ${registration.priority}'
      '${registration.enabled ? '' : ', disabled'})',
      fields: <String, Object?>{
        'registered': registry.ids.toList(),
        'live': registration.capabilities.supportsLive,
        'protocols': registration.capabilities.supportedProtocols.toList(),
        'formats': registration.capabilities.supportedFormats.toList(),
      },
    );
  }

  /// Removes a backend registration.
  void unregisterBackend(String id) {
    registry.unregister(id);

    MediaCoreLog.info(
      LogCategory.fallback,
      'backend unregistered: $id',
      fields: <String, Object?>{'registered': registry.ids.toList()},
    );
  }

  // ---------------------------------------------------------------------------
  // PlayerIdentity lifecycle
  // ---------------------------------------------------------------------------

  /// Creates a new player.
  ///
  /// When [source] is given the kernel resolves it through the
  /// [SourceService] (when available), selects the best backend,
  /// initializes the adapter and opens the source. [preferredBackend]
  /// overrides automatic selection.
  Future<PlayerHandle> create({
    PlayerConfig config = PlayerConfig.defaults,
    PlayerSource? source,
    String? preferredBackend,
  }) async {
    var effectiveSource = source;
    if (effectiveSource != null) {
      effectiveSource = await _resolveSource(effectiveSource);
    }

    final registration = selector.require(effectiveSource ?? PlayerSource.unknown(), preferredId: preferredBackend);

    MediaCoreLog.info(
      LogCategory.player,
      'create: backend "${registration.id}"'
      '${preferredBackend == null ? ' (selected by score)' : ' (requested: $preferredBackend)'}'
      ' for ${effectiveSource?.uri ?? '<no source>'}',
      fields: <String, Object?>{
        'backend': registration.id,
        'preferredBackend': preferredBackend,
        'registered': registry.ids.toList(),
        'autoPlay': config.autoPlay,
        'scores': selector.scoreTable(effectiveSource ?? PlayerSource.unknown()),
      },
    );

    final player = PlayerIdentity.create();
    final sessionId = SessionId.generate();
    final adapter = registration.factory.create(registration.id);
    final platform = platformProvider;

    final adapterContext = PlayerAdapterContext(
      playerId: player.id,
      sessionId: sessionId,
      config: PlayerAdapterConfig(
        volume: config.volume,
        playbackRate: config.playbackRate,
        hardwareAcceleration: config.preferHardwareDecoding,
        audioEnabled: config.enableAudio,
      ),
      playerConfig: config,
      // What the device can do, as far as anyone knows. A player created with
      // no provider attached carries the defaults, which report themselves as
      // unreported rather than as a healthy device.
      platform: platform?.capabilities ?? const PlatformCapabilities(),
      device: platform?.device ?? PlatformDeviceProfile.unknown,
      codecs: platform?.codecs ?? PlatformCodecCapabilities.unknown,
    );

    final handle = PlayerHandle(
      player: player,
      adapter: adapter,
      registration: registration,
      adapterContext: adapterContext,
      eventBus: _eventBus,
      options: options,
      config: config,
      registry: registry,
      selector: selector,
      planner: _planner,
    );

    // The config carries playback preferences the handle cannot read from the
    // adapter context alone; applying them here is what makes
    // `PlayerConfig(muted: true)` actually silent and keeps
    // `options.enableFallback` / `config.enableFallback` meaningful.
    if (config.muted) {
      await handle.setMute(muted: true);
    }

    handle.engineFallbackEnabled = options.enableFallback && config.enableFallback;

    await handle.initialize();

    _registerEverywhere(handle);

    if (effectiveSource != null) {
      try {
        await handle.open(effectiveSource, autoPlay: config.autoPlay);
      } catch (_) {
        // The caller never received the handle, so leaving it registered would
        // strand a live player in the pool and in every coordinator - one that
        // `acquire()` could later hand out. Release it and rethrow.
        await release(handle.id);

        rethrow;
      }
    }

    return handle;
  }

  /// Creates a player from a [MediaSource].
  ///
  /// Where [create] takes the flat [PlayerSource] an existing adapter
  /// already understands, [createFromMedia] accepts the shape-aware
  /// [MediaSource] model the provider layer produces — a Bilibili
  /// DASH pair becomes one [CompositeMediaSource] here and this
  /// method figures out what to do with it:
  ///
  /// 1. Pick a backend from the primary track's protocol/format.
  /// 2. Ask [mediaSourcePlanner] how that backend should consume the
  ///    source, given its declared
  ///    [PlayerAdapterCapabilities.compositeSupport].
  /// 3. For a [DirectPlan] or [CompositePlan], bridge the source to
  ///    [PlayerSource] and delegate to [create]. The original
  ///    [MediaSource] is preserved under
  ///    [MediaSourceBridge.metadataKey] so a composite-capable
  ///    adapter can recover the extra tracks.
  /// 4. For an [UnsupportedPlan], throw. Silently falling back to the
  ///    primary track is what lets a composite ship to a
  ///    single-URL backend with no audio and no signal that anything
  ///    went wrong — an explicit exception keeps the failure at the
  ///    layer that can react.
  Future<PlayerHandle> createFromMedia(
    MediaSource source, {
    PlayerConfig config = PlayerConfig.defaults,
    String? preferredBackend,
  }) async {
    final registration = selector.requireMedia(source, preferredId: preferredBackend);
    final plan = _planner.plan(source, registration.capabilities);

    // Kept `async` on purpose: the two throws below (no backend registered,
    // unsupported plan) reach callers as an error on the returned Future,
    // which is what every caller of this method awaits.
    switch (plan) {
      case DirectPlan():
      case CompositePlan():
        final handle = await create(config: config, source: source.toPlayerSource(), preferredBackend: registration.id);

        return handle;

      case UnsupportedPlan(:final reason):
        throw UnsupportedError(reason);
    }
  }

  /// Acquires an idle player from the pool.
  ///
  /// Returns `null` when the pool has no reusable player. The
  /// returned handle is recycled: fresh generation, no source.
  Future<PlayerHandle?> acquire({Duration timeout = const Duration(seconds: 2)}) async {
    if (!options.enablePool) {
      return null;
    }

    final sessionId = SessionId.generate();
    final pooledId = _pool.allocate(sessionId: sessionId);
    if (pooledId == null) {
      return null;
    }

    final handle = _handles[pooledId];
    if (handle == null || handle.disposed) {
      // Drop the row entirely: releasing it back as "idle" would keep it
      // available forever, so `allocate` would keep returning a dead player and
      // the pool's counts would describe decoders that do not exist.
      _pool.remove(pooledId);
      return null;
    }

    await handle.recycle();
    _coordinator.player.attachSession(playerId: pooledId, session: handle.session);
    return handle;
  }

  /// Looks up a player by identifier.
  PlayerHandle? get(PlayerId playerId) {
    return _handles[playerId];
  }

  /// Looks up a player by identifier.
  PlayerHandle? operator [](PlayerId playerId) {
    return _handles[playerId];
  }

  /// All live handles.
  List<PlayerHandle> get handles {
    return List.unmodifiable(_handles.values);
  }

  /// Session bound to a player, if any.
  PlayerSession? sessionOf(PlayerId playerId) {
    return _coordinator.player.sessionOf(playerId);
  }

  /// Releases a player completely.
  ///
  /// The handle is disposed, unregistered from every coordinator
  /// and removed from the pool. Use `PlayerHandle.recycle` plus
  /// [acquire] for soft reuse.
  Future<void> release(PlayerId playerId) async {
    final handle = _handles.remove(playerId);
    if (handle == null) {
      return;
    }
    _reportMemory();

    if (_activeHandle?.id == playerId) {
      _activeHandle = null;
      _audioDriver?.onPlayerDeactivated();
    }

    _coordinator.player.detachSession(playerId);
    _coordinator.player.unregister(playerId);
    _coordinator.playback.unregister(playerId);
    _coordinator.lifecycle.unregister(playerId);
    _pool.remove(playerId);

    await handle.dispose();
  }

  // ---------------------------------------------------------------------------
  // Preload
  // ---------------------------------------------------------------------------

  /// Registers [source] for preloading.
  ///
  /// The preload manager orders requests by [priority]. Callers
  /// observe ordering through `preloadManager.next()`.
  void preload(PlayerSource source, {PreloadPriority priority = PreloadPriority.normal}) {
    _preloadManager.add(PreloadRequest(sourceId: source.id, priority: priority));

    if (options.enableEventBus) {
      _eventBus.publish(
        GenericPlayerEvent(
          type: PlayerEventType.cache,
          data: <String, Object?>{'action': 'preloadQueued', 'uri': source.uri.toString()},
          context: EventContext(sourceId: source.id),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  /// Global normalized event stream.
  Stream<PlayerEvent> get events => _eventBus.stream;

  /// Subscribes to the global event stream.
  EventSubscription subscribe(void Function(PlayerEvent event) listener, {EventPriority? minimumPriority}) {
    return _eventBus.subscribe(listener, minimumPriority: minimumPriority);
  }

  // ---------------------------------------------------------------------------
  // Audio capability
  // ---------------------------------------------------------------------------

  /// The audio capability driver in use, if any.
  ///
  /// Set explicitly by [attachAudio], or taken from [audioDriverFactory] when
  /// the capability is installed process-wide. Null when this kernel publishes
  /// nothing to the platform.
  KernelAudioDriver? get audioDriver => _audioDriver;

  /// Attaches an audio capability driver.
  ///
  /// The driver receives active-player notifications; see
  /// [KernelAudioDriver] for the exact semantics. Requires the
  /// event bus, which is enabled by default.
  ///
  /// An explicit driver wins over the process-wide one, and attaching is what a
  /// host uses for a kernel that was created before
  /// `MediaSessionBootstrap.enable()` ran.
  ///
  /// ```dart
  /// final session = await MediaSessionBootstrap.enable();
  /// kernel.attachAudio(session);
  /// ```
  void attachAudio(KernelAudioDriver driver) {
    _audioDriver = driver;
    final active = _activeHandle;
    if (active != null) {
      driver.onPlayerActivated(active);
    }
  }

  /// Detaches the audio capability driver.
  void detachAudio() {
    final driver = _audioDriver;
    _audioDriver = null;
    if (driver != null && _activeHandle != null) {
      driver.onPlayerDeactivated();
    }
  }

  // ---------------------------------------------------------------------------
  // Platform capability
  // ---------------------------------------------------------------------------

  /// Detaches the platform capability source, clearing [platformProvider].
  ///
  /// Players created afterwards fall back to the optimistic defaults in
  /// `PlatformCapabilities`; live players keep the context they were built
  /// with.
  void detachPlatformProvider() {
    platformProvider = null;
  }

  // ---------------------------------------------------------------------------
  // Presentation capability
  // ---------------------------------------------------------------------------

  /// Detaches the presentation driver.
  void detachPresentation() {
    presentationDriver = null;
  }

  /// Requests fullscreen for [playerId].
  ///
  /// Throws [StateError] when no presentation driver is attached
  /// or the player is unknown.
  Future<void> enterFullscreen(PlayerId playerId) {
    return _requestPresentation(playerId, PresentationRequest.fullscreen());
  }

  /// Leaves fullscreen for [playerId].
  Future<void> exitFullscreen(PlayerId playerId) {
    return _requestPresentation(playerId, PresentationRequest.normal());
  }

  /// Requests picture-in-picture for [playerId].
  Future<void> enterPip(PlayerId playerId) {
    return _requestPresentation(playerId, PresentationRequest.pip());
  }

  /// Leaves picture-in-picture for [playerId].
  Future<void> exitPip(PlayerId playerId) {
    return _requestPresentation(playerId, PresentationRequest.normal());
  }

  /// Requests a floating always-on-top window for [playerId].
  Future<void> enterFloating(PlayerId playerId) {
    return _requestPresentation(playerId, PresentationRequest.floating());
  }

  /// Leaves the floating window for [playerId].
  Future<void> exitFloating(PlayerId playerId) {
    return _requestPresentation(playerId, PresentationRequest.normal());
  }

  /// Captures a frame of [playerId].
  ///
  /// Returns null when the player is unknown, has no source open, or neither
  /// capture route could produce an image; see
  /// `PlayerHandle.captureScreenshot` for which route is tried and why a
  /// capture can legitimately produce nothing.
  Future<PlayerScreenshot?> captureScreenshot(
    PlayerId playerId, {
    ScreenshotOptions options = ScreenshotOptions.defaults,
  }) async {
    final handle = _handles[playerId];

    if (handle == null) {
      return null;
    }

    // Awaited instead of returned directly: this method stays `async` so a
    // disposed handle's synchronous `StateError` reaches callers as an error
    // on the Future, exactly as it did before.
    final screenshot = await handle.captureScreenshot(options: options);

    return screenshot;
  }

  Future<void> _requestPresentation(PlayerId playerId, PresentationRequest request) async {
    final driver = presentationDriver;
    if (driver == null) {
      throw StateError('No presentation driver attached. Assign PlayerKernel.presentationDriver first.');
    }
    if (!_handles.containsKey(playerId)) {
      throw StateError('Unknown player: $playerId');
    }
    await driver.apply(playerId, request);
  }

  void _trackActivePlayer() {
    _activeTrackingSub = _eventBus.stream.listen((event) {
      if (event is! GenericPlayerEvent) {
        return;
      }
      if (event.type != PlayerEventType.playback) {
        return;
      }

      final playerId = event.context?.playerId;
      if (playerId == null) {
        return;
      }

      switch (event.data['action']) {
        case 'play':
          final handle = _handles[playerId];
          if (handle != null && !identical(handle, _activeHandle)) {
            _activeHandle = handle;
            _audioDriver?.onPlayerActivated(handle);
          }
        case 'stop':
          if (_activeHandle?.id == playerId) {
            _activeHandle = null;
            _audioDriver?.onPlayerDeactivated();
          }
        default:
          break;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Recovery
  //
  // The kernel no longer runs a fallback loop. It used to: when a handle
  // exhausted its own recovery, the kernel walked the registry and called
  // `handle.attachAdapter` in a while loop, invalidating whatever
  // recovery the handle was still running. Backend switching is now the
  // ladder's `nextBackend` rung, executed by the handle that owns the
  // backend — the kernel only supplies the registry and selector the
  // handle draws candidates from.
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<PlayerSource> _resolveSource(PlayerSource source) async {
    final service = _sourceService;
    if (service == null || !service.canResolve(source)) {
      return source;
    }

    try {
      final resolved = await service.resolve(source);
      final carried = resolved.source;
      if (carried != null) {
        return _preserveBridgeMetadata(carried, source);
      }

      // A resolver that answers with a fresh address still owes the
      // access details that go with it: a signed URL and the Referer or
      // token that unlocks it arrive together, and copying one without
      // the other yields an open that 403s and blames the backend.
      // `unknown` means "the resolver had nothing to say", so those
      // fields stay as they were.
      return source.copyWith(
        uri: resolved.uri,
        headers: resolved.headers,
        protocol: resolved.protocol == SourceProtocol.unknown ? source.protocol : resolved.protocol,
        mediaType: resolved.mediaType == SourceMediaType.unknown ? source.mediaType : resolved.mediaType,
        format: resolved.format == SourceFormat.unknown ? source.format : resolved.format,
      );
    } on Object catch (error, stackTrace) {
      // Resolution is an enhancement, so the original source still
      // opens — but a resolver that throws (expired token, dead
      // provider) has to leave a trace, or the failure resurfaces as a
      // backend error nobody can attribute.
      MediaCoreLog.warning(
        LogCategory.source,
        'source resolution failed; opening the unresolved source',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'uri': source.uri.toString()},
      );
      return source;
    }
  }

  /// Keeps the [MediaSourceBridge] entry alive across a resolver hop.
  ///
  /// A resolver that carries its own [PlayerSource] replaces the
  /// object wholesale, and a resolver-built source knows nothing about
  /// the composite the provider produced. Without this re-attachment,
  /// a DASH pair would reach the adapter as a bare video URL and a
  /// composite-capable backend would play it with no audio and no
  /// signal that anything was lost. Only the bridge key is preserved;
  /// everything else stays the resolver's answer, because the
  /// resolver is the authority on the rest of the source.
  PlayerSource _preserveBridgeMetadata(PlayerSource carried, PlayerSource original) {
    final bridge = original.metadata[MediaSourceBridge.metadataKey];
    if (bridge == null || carried.metadata.containsKey(MediaSourceBridge.metadataKey)) {
      return carried;
    }
    return carried.copyWith(metadata: <String, Object?>{...carried.metadata, MediaSourceBridge.metadataKey: bridge});
  }

  void _registerEverywhere(PlayerHandle handle) {
    _handles[handle.id] = handle;
    _reportMemory();

    if (options.enablePool) {
      // A freshly created handle belongs to its creator. Without reserving it
      // the pool counts it as idle, and the next acquire() (e.g. a feed cell
      // taking a warm player) would hand out - and recycle - the player that is
      // currently playing.
      _pool
        ..add(handle.id)
        ..reserve(handle.id, sessionId: handle.session.context.sessionId);
    }

    _coordinator.player.register(handle.player);
    _coordinator.player.attachSession(playerId: handle.id, session: handle.session);
    _coordinator.playback.register(playerId: handle.id, controller: handle.playbackController);
    _coordinator.lifecycle.register(playerId: handle.id, lifecycle: handle.lifecycleController);
  }

  /// Reports how many players this kernel is holding.
  ///
  /// One entry per open handle: the kernel owns the players, so this is the
  /// count every other module's players ultimately come from. The byte figure is
  /// a declared estimate (the kernel does not know each player's resolution
  /// without asking every snapshot), which is why the item count is reported
  /// alongside it.
  void _reportMemory() {
    _memory.report(
      _memoryKey,
      items: _handles.length,
      bytes: _handles.length * MemoryEstimates.videoStream720p,
      note: '${_handles.length} open player(s)',
    );
  }

  /// App-lifecycle transitions, applied to every player this kernel owns.
  ///
  /// The framework has had a class for this for a long time and nothing ever
  /// installed it, so a video kept decoding with the app in the background and a
  /// background-playback switch had nothing to switch off.
  ///
  /// Every *playing* handle is deactivated, not only the active one: a wall or a
  /// warm pool has several, and pausing the visible one leaves nine decoders
  /// running behind a widget nobody can see. Nothing is resumed on the way back —
  /// audio starting by itself after an app switch reads as a bug, so the viewer
  /// presses play.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!options.pauseWhenBackgrounded) {
      return;
    }

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        for (final handle in List<PlayerHandle>.from(_handles.values)) {
          if (handle.disposed ||
              !(handle.config.pauseWhenBackgrounded ?? true) ||
              !handle.playbackStream.value.isPlaying) {
            continue;
          }

          unawaited(handle.deactivate());
        }
      case AppLifecycleState.resumed:
        // Back in the foreground: the players are addressable again, which is
        // what `activate` records. Playback stays where the viewer left it.
        for (final handle in List<PlayerHandle>.from(_handles.values)) {
          if (handle.disposed) {
            continue;
          }

          handle.activate();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Transient on the way to paused, or the process is going away: no
        // player action, and no surprise pause when a dialog steals focus.
        break;
    }
  }

  /// Disposes the kernel and every live player.
  ///
  /// Releases each handle through [release] — which disposes its adapter and
  /// takes the player out of the pool and every coordinator — drops the app
  /// lifecycle observer this kernel installed when it asked for one, withdraws
  /// the memory ledger entry, and then tears down the shared services (preload
  /// manager, coordinator, pool, event bus) in that order.
  Future<void> dispose() async {
    if (_observesLifecycle) {
      _observesLifecycle = false;

      try {
        WidgetsBinding.instance.removeObserver(this);
      } on Object {
        // The binding is already gone; there is nobody left to notify.
      }
    }

    final ids = List<PlayerId>.from(_handles.keys);
    for (final id in ids) {
      await release(id);
    }

    await _activeTrackingSub?.cancel();
    _activeTrackingSub = null;
    _audioDriver = null;

    _memory.withdraw(_memoryKey);

    await _preloadManager.dispose();
    await _coordinator.dispose();
    await _pool.dispose();
    await _eventBus.dispose();
  }
}
