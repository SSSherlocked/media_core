import 'dart:async';

import 'package:media_core/adapter/engine_option.dart';
import 'package:media_core/adapter/player_adapter.dart';
import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/adapter/player_adapter_context.dart';
import 'package:media_core/adapter/player_adapter_event.dart';
import 'package:media_core/adapter/player_adapter_metrics.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/adapter/player_adapter_selector.dart';
import 'package:media_core/composition/media_timeline.dart';
import 'package:media_core/core/player_config.dart';
import 'package:media_core/core/player_core_state.dart';
import 'package:media_core/core/player_identity.dart';
import 'package:media_core/event/event_context.dart';
import 'package:media_core/event/event_priority.dart';
import 'package:media_core/event/player_event.dart';
import 'package:media_core/event/player_event_bus.dart';
import 'package:media_core/event/player_event_type.dart';
import 'package:media_core/geometry/geometry_controller.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/kernel/kernel_options.dart';
import 'package:media_core/kernel/player_handle_snapshot.dart';
import 'package:media_core/lifecycle/lifecycle_controller.dart';
import 'package:media_core/lifecycle/lifecycle_snapshot.dart';
import 'package:media_core/media_core.dart' show MediaPlayerView, PlayerKernel;
import 'package:media_core/operation/operation.dart';
import 'package:media_core/operation/operation_cancel_token.dart';
import 'package:media_core/operation/operation_registry.dart';
import 'package:media_core/operation/operation_tracker.dart';
import 'package:media_core/operation/operation_type.dart';
import 'package:media_core/planning/default_media_source_planner.dart';
import 'package:media_core/planning/media_source_plan.dart';
import 'package:media_core/planning/media_source_planner.dart';
import 'package:media_core/playback/playback_buffer.dart';
import 'package:media_core/playback/playback_command.dart';
import 'package:media_core/playback/playback_controller.dart';
import 'package:media_core/playback/player_transport_state.dart';
import 'package:media_core/policy/player_policy.dart';
import 'package:media_core/recovery/recovery_candidate_provider.dart';
import 'package:media_core/recovery/recovery_failure.dart';
import 'package:media_core/recovery/recovery_ladder.dart';
import 'package:media_core/recovery/recovery_ladder_event.dart';
import 'package:media_core/recovery/recovery_session.dart';
import 'package:media_core/recovery/recovery_snapshot.dart';
import 'package:media_core/recovery/recovery_step.dart';
import 'package:media_core/recovery/recovery_target.dart';
import 'package:media_core/runtime/player_runtime.dart';
import 'package:media_core/screenshot/player_screenshot.dart';
import 'package:media_core/screenshot/screenshot_options.dart';
import 'package:media_core/screenshot/screenshot_surface.dart';
import 'package:media_core/session/player_session.dart';
import 'package:media_core/session/session_context.dart';
import 'package:media_core/session/session_controller.dart';
import 'package:media_core/session/session_snapshot.dart';
import 'package:media_core/session/session_state.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_source_bridge.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/util/retry_utils.dart';
import 'package:media_core_logging/media_core_logging.dart';
import 'package:rxdart/rxdart.dart';

part 'player_handle_adapter.dart';
part 'player_handle_engine_options.dart';
part 'player_handle_lifecycle.dart';
// The implementation of [PlayerHandle] is split by concern across `part`
// files next to this one:
//
// - `player_handle_operations.dart`  operation records + serialization guards
// - `player_handle_playback.dart`    open / play / pause / stop / seek / volume / rate
// - `player_handle_lifecycle.dart`   screenshots, close, activate, recycle
// - `player_handle_recovery.dart`    recovery knobs, failure reporting, step execution
// - `player_handle_adapter.dart`     adapter subscription and event bridge
//
// Fields, the constructor, the [RecoveryTarget] overrides and [dispose]
// stay in this file. Extensions are library-private, so the public API
// is unchanged.

part 'player_handle_operations.dart';
part 'player_handle_playback.dart';
part 'player_handle_recovery.dart';

/// Describes the backend a handle just switched to.
///
/// Emitted on [PlayerHandle.backendChanges] when the recovery ladder
/// attaches another backend. Consumers that keep per-adapter state
/// (watchdog capability snapshots, custom overlays) re-read it from
/// [adapter] instead of holding on to the previous adapter instance,
/// which is already disposed by the time the change is published.
final class PlayerBackendChange {
  /// Creates a backend change record.
  const PlayerBackendChange({required this.from, required this.to, required this.adapter});

  /// Backend that was attached before the change.
  final String from;

  /// Backend that is attached now.
  final String to;

  /// The newly attached adapter.
  final PlayerAdapter adapter;

  @override
  String toString() => 'PlayerBackendChange($from → $to)';
}

/// Runtime facade for one logical player.
///
/// [PlayerHandle] wires the per-player modules together:
///
/// ```text
/// PlayerRuntime ──adapter events──▶ PlaybackController
///       │                        ├──▶ SessionController
///       │                        ├──▶ GeometryController
///       │                        └──▶ (adapter-scoped bindings)
///       │
///       └── PlayerHandle ────────▶ LifecycleController
///                                  RecoveryLadder
///                                  PlayerEventBus
/// ```
///
/// Responsibilities:
///
/// - forward playback commands to the runtime's adapter
/// - execute the recovery ladder's steps
/// - publish normalized events
/// - serialize backend operations
/// - protect backend operations with lifecycle generations
///
/// It does not:
///
/// - own the adapter, session or per-runtime controllers
///   (those belong to [PlayerRuntime])
/// - decide when to reopen, switch source or switch backend
///   (that belongs to [RecoveryLadder] and [RecoveryCandidateProvider])
/// - select or create adapters
///
/// Those belong to:
///
/// - PlayerRuntime
/// - RecoveryLadder
/// - PlayerAdapterSelector
/// - PlayerKernel
///
/// ## Recovery boundary
///
/// The handle is the *execution* side of recovery: it implements
/// [RecoveryTarget] and owns the [RecoveryLadder] that decides. Nothing
/// else may start a recovery — consumers report a failure through
/// [reportFailure] and observe what the ladder decided through
/// [recoveryEvents].
///
/// This is deliberate. One failure used to be handled by the handle's
/// own retry loop, the kernel's fallback loop and the live controller's
/// ladder at the same time, and each of the three invalidated the
/// others' operations, so a single fault produced a storm of adapter
/// create/dispose cycles. One decision point, many reporters.
final class PlayerHandle implements RecoveryTarget {
  /// Creates a handle. Prefer [PlayerKernel.create] over calling
  /// this directly.
  PlayerHandle({
    required PlayerIdentity player,
    required PlayerAdapter adapter,
    required PlayerAdapterRegistration registration,
    required PlayerAdapterContext adapterContext,
    required PlayerEventBus eventBus,
    required KernelOptions options,
    this.config = PlayerConfig.defaults,
    this.policy = const PlayerPolicy(),
    PlayerAdapterRegistry? registry,
    PlayerAdapterSelector? selector,
    MediaSourcePlanner? planner,
  }) : _player = player,
       _registration = registration,
       _adapterContext = adapterContext,
       _eventBus = eventBus,
       _options = options,
       _registry = registry,
       _selector = selector,
       _planner = planner ?? const DefaultMediaSourcePlanner(),
       _loop = config.loop,
       _runtime = PlayerRuntime(
         adapter: adapter,
         session: PlayerSession(
           context: SessionContext(
             playerId: player.id,
             sessionId: adapterContext.sessionId,
             generationId: GenerationId.generate(),
             sourceId: PlayerSource.unknown().id,
             source: PlayerSource.unknown(),
             policy: policy,
             // The session reports the platform the kernel was told about; a
             // hardcoded `const PlatformCapabilities()` here is what used to
             // make every session claim the same device.
             platform: adapterContext.platform,
           ),
         ),
       ) {
    _ladder = RecoveryLadder(
      target: this,
      candidates: _HandleRecoveryCandidates(this),
      retryDelay: _retryDelayForAttempt,
    );

    _ladderEvents = _ladder.events.listen(_onLadderEvent);

    _subscribeAdapter(_runtime.adapter);
  }

  final PlayerIdentity _player;
  final PlayerAdapterContext _adapterContext;
  final PlayerEventBus _eventBus;
  final KernelOptions _options;
  final PlayerAdapterRegistry? _registry;
  final PlayerAdapterSelector? _selector;
  final MediaSourcePlanner _planner;

  final PlayerRuntime _runtime;

  PlayerAdapterRegistration _registration;
  PlayerSource? _currentSource;

  final LifecycleController _lifecycle = LifecycleController();

  /// The single decision point for recovery on this player.
  late final RecoveryLadder _ladder;

  late final StreamSubscription<RecoveryLadderEvent> _ladderEvents;

  final StreamController<PlayerBackendChange> _backendChanges = StreamController<PlayerBackendChange>.broadcast();
  final StreamController<PlayerSource?> _sourceChanges = StreamController<PlayerSource?>.broadcast();

  /// Adapter events of whichever adapter is currently attached.
  ///
  /// Broadcast, so several consumers can listen, and — unlike
  /// `adapter.events` — stable across backend swaps: a listener stays
  /// bound to this handle and therefore keeps receiving events after
  /// recovery swapped the backend underneath it.
  final StreamController<PlayerAdapterEvent> _adapterEvents = StreamController<PlayerAdapterEvent>.broadcast();

  /// Alternative sources the caller allows recovery to fall back to.
  ///
  /// Set through [setSourceCandidates]: the handle cannot know that a
  /// live stream carries several lines unless the caller says so.
  List<PlayerSource> _sourceCandidates = const <PlayerSource>[];

  StreamSubscription<PlayerAdapterEvent>? _adapterSubscription;

  bool _disposed = false;

  /// The caller's play intent, once it has declared one.
  ///
  /// Behaviour after a recovery step is decided by what the *caller* wants,
  /// not by what the adapter last reported. The two disagree in practice:
  /// an engine that autoplays (ExoPlayer on a live stream, mpv with a
  /// stream that starts on its own) never emits a `Playing` event until
  /// something asks it to play, so the playback mirror reads "paused"
  /// while video is on screen. Restoring from that mirror paused the
  /// stream after every recovery.
  ///
  /// `null` means the caller never declared an intent, in which case the
  /// playback mirror is the best available answer.
  ///
  /// Declaring is not commanding: [play] and [pause] set this as a side
  /// effect, and writing it only changes what recovery restores to — a
  /// caller whose engine starts on its own has to declare `true` here
  /// because nothing else in the framework knows the stream is meant to
  /// be running.
  bool? playIntent;

  /// Whether output is currently muted.
  ///
  /// Mute is implemented by the handle, not the adapter: every engine
  /// understands volume, so muting stores the previous volume and drives
  /// the adapter to 0. A fresh adapter attached by recovery is re-muted
  /// by `_applyMute` instead of coming back audible.
  bool _muted = false;

  /// Volume to restore on unmute.
  double _unmutedVolume = 1;

  /// Whether playback restarts after completion.
  ///
  /// Mutable at runtime; [PlayerConfig.loop] only seeds the initial value.
  bool _loop;

  // ---------------------------------------------------------------------------
  // Operation record
  //
  // Every stateful backend operation this handle performs is recorded here,
  // on the handle, because the handle is the one layer every consumer
  // already holds. Streams of these records are the diagnostic surface for
  // "what did the player actually do, in what order, and what failed" —
  // readable without touching the modules underneath.
  // ---------------------------------------------------------------------------

  final OperationRegistry _operationRegistry = OperationRegistry();
  final OperationTracker _operationTracker = OperationTracker();
  Operation? _currentOperation;

  /// Track preference applied to whichever adapter is attached.
  ///
  /// Preserved by the handle for the same reason volume and rate are:
  /// recovery can replace the adapter without the owner of the
  /// preference being involved, and a freshly attached engine would
  /// otherwise come back with video enabled.
  bool _audioOnly = false;

  /// Whether the currently attached adapter has an opened source.
  ///
  /// This is deliberately maintained by [PlayerHandle] instead of
  /// relying only on `PlayerAdapter.initialized`. An initialized
  /// adapter may have already been closed and therefore must not
  /// receive playback commands.
  bool _backendReady = false;

  /// Monotonically increasing lifecycle generation owned by this handle.
  ///
  /// Every destructive lifecycle transition invalidates older
  /// operations. See the class comment for the full description.
  int _operationGeneration = 0;

  /// Serializes all backend operations owned by this handle.
  ///
  /// Cancellation of a Dart [Future] cannot forcibly interrupt a native
  /// player call. Serializing operations ensures backend mutations
  /// happen in a deterministic order, while [_operationGeneration]
  /// prevents stale operations from committing state after a newer
  /// lifecycle transition.
  Future<void> _operation = Future<void>.value();

  /// Cancellation token for the currently active recovery/playback
  /// continuation.
  ///
  /// Lifecycle operations such as open/close use the operation
  /// generation instead of sharing this token. This prevents
  /// pause/stop from accidentally cancelling a source-opening
  /// lifecycle operation.
  OperationCancelToken? _activeCancelToken;

  /// PlayerIdentity configuration applied to this handle.
  final PlayerConfig config;

  /// PlayerIdentity policy applied to this handle.
  final PlayerPolicy policy;

  /// Volume queued by a caller before the source was ready.
  ///
  /// `setVolume` used to require an open source and throw otherwise.
  /// That contract is wrong for callers that legitimately race the
  /// source-open (engine switches, autoplay paths): they would fail
  /// the whole switch with a `StateError` even though the adapter was
  /// still opening. The value is now remembered here and applied at
  /// the end of [open], after the adapter has accepted the source.
  double? _pendingVolume;

  /// Playback rate queued by a caller before the source was ready.
  ///
  /// See [_pendingVolume].
  double? _pendingRate;

  /// Count of volume requests, newest last.
  ///
  /// A slider is one request per frame of the drag, and only the value the
  /// viewer stopped on is a thing they asked for: a queued set whose number is
  /// no longer the newest is an intermediate and never reaches the engine.
  /// This coalescing stands in for the shared cancellation slot, which a
  /// volume request must not take — that slot belongs to the play/seek that
  /// may be running, and grabbing it used to cancel that operation outright.
  int _volumeRequest = 0;

  /// See [_volumeRequest].
  int _rateRequest = 0;

  /// Whether this handle's own recovery ladder reacts to failures.
  ///
  /// On by default. A playback owner that runs its own recovery loop (the
  /// live controller's task-queue sweep) turns it off, so adapter errors
  /// are reported as events only and there is exactly one recovery path
  /// for the player. Without this, two loops would race — the exact
  /// multiply-driven recovery this framework once suffered from.
  bool recoveryEnabled = true;

  /// Whether recovery may attach another engine when every line failed.
  ///
  /// Enabled by default. The caller turns it off for the "single line,
  /// and *I* decide what happens next" contract: with it off, the ladder's
  /// candidate list simply contains no backends, so once the line rungs
  /// are spent the run terminates and the failure is reported instead of
  /// being answered by a silent engine swap.
  bool engineFallbackEnabled = true;

  /// Engine options applied through engine-option configuration.
  ///
  /// Keyed by (domain, key) so a later value for the same option replaces
  /// an earlier one. Persisted across backend swaps and engine rebuilds:
  /// every fresh engine created for this handle replays the whole map, so
  /// the caller's configuration survives recovery and fallback too.
  final Map<(String, String), EngineOption> _engineOptions = <(String, String), EngineOption>{};

  // ---------------------------------------------------------------------------
  // Identity and state
  // ---------------------------------------------------------------------------

  /// The logical player identity.
  PlayerIdentity get player => _player;

  /// Identifier of this player.
  PlayerId get id => _player.id;

  /// Current session identifier.
  SessionId get sessionId => _runtime.session.context.sessionId;

  /// Current playback generation identifier.
  GenerationId get generationId => _runtime.session.generation.id;

  /// Identifier of the backend currently attached.
  String get backendId => _registration.id;

  /// Capabilities of the attached backend.
  PlayerAdapterCapabilities get backendCapabilities => _registration.capabilities;

  /// The attached adapter.
  PlayerAdapter get adapter => _runtime.adapter;

  /// Semantic state reported by the adapter.
  PlayerCoreState get state => _runtime.adapter.state;

  /// Metrics reported by the adapter.
  PlayerAdapterMetrics get metrics => _runtime.adapter.metrics;

  /// Currently open source, if any.
  PlayerSource? get source => _currentSource;

  /// The presentation timeline of the currently open media source.
  ///
  /// Derived from the [MediaSource] this handle opened (see
  /// [openMedia] and [PlayerKernel.createFromMedia]): composite
  /// tracks are aligned onto one clock through
  /// [MediaTimeline.from], so an adapter or overlay can convert
  /// between a track's media time and the position the player
  /// reports without re-reading every `startOffset`.
  ///
  /// Null when the open source never crossed
  /// [MediaSourceBridge] — a plain `PlayerSource` carries no track
  /// information to align.
  MediaTimeline? get timeline {
    final current = _currentSource;
    if (current == null) {
      return null;
    }
    final media = MediaSourceBridge.fromPlayerSource(current);
    if (media == null) {
      return null;
    }
    return MediaTimeline.from(media);
  }

  /// Current playback state.
  PlayerTransportState get playback => _runtime.playback.current;

  /// Playback state stream.
  ValueStream<PlayerTransportState> get playbackStream => _runtime.playback.state;

  /// Session snapshots stream.
  Stream<SessionSnapshot> get snapshots => _runtime.session.snapshots;

  /// Latest session snapshot.
  SessionSnapshot get snapshot => _runtime.session.snapshot;

  /// A transient aggregate snapshot of this handle.
  ///
  /// Aggregates the handle's own modules (lifecycle, recovery) and the
  /// runtime's controllers (session, playback, geometry) into a single
  /// immutable view. Constructed on every access; nothing is cached.
  PlayerHandleSnapshot get combinedSnapshot => PlayerHandleSnapshot(
    playerId: _player.id,
    sessionId: _runtime.session.context.sessionId,
    generationId: _runtime.session.generation.id,
    backendId: _registration.id,
    source: _currentSource,
    session: _runtime.session.snapshot,
    playback: _runtime.playback.snapshot,
    geometry: _runtime.geometry.snapshot,
    lifecycle: _lifecycle.snapshot,
    recovery: _ladder.snapshot,
    disposed: _disposed,
  );

  /// Lifecycle snapshot.
  LifecycleSnapshot get lifecycle => _lifecycle.snapshot;

  /// Recovery snapshot.
  ///
  /// Diagnostic view of the ladder: what it is working on, how far it
  /// got, and whether it gave up. Decisions are not driven from here.
  RecoverySnapshot get recovery => _ladder.snapshot;

  /// Whether this handle has been disposed.
  bool get disposed => _disposed;

  /// The player session owned by the runtime.
  PlayerSession get session => _runtime.session;

  /// The session controller owned by the runtime.
  SessionController get sessionController => _runtime.sessionController;

  /// The playback controller owned by the runtime.
  PlaybackController get playbackController => _runtime.playback;

  /// The geometry controller owned by the runtime.
  GeometryController get geometryController => _runtime.geometry;

  /// The lifecycle controller owned by this handle.
  LifecycleController get lifecycleController => _lifecycle;

  /// The recovery ladder owned by this handle.
  ///
  /// Exposed for diagnostics and for tests that want to await
  /// [RecoveryLadder.settled]. Recovery is driven by reporting failures
  /// through [reportFailure], not by calling the ladder directly.
  RecoveryLadder get recoveryLadder => _ladder;

  /// The runtime composition root owned by this handle.
  PlayerRuntime get runtime => _runtime;

  // ---------------------------------------------------------------------------
  // Recovery boundary
  // ---------------------------------------------------------------------------

  /// Decision events of the recovery ladder.
  ///
  /// The observability contract of recovery: one event per rung the
  /// ladder climbs, plus a terminal event. A consumer that needs to know
  /// whether recovery gave up subscribes here.
  Stream<RecoveryLadderEvent> get recoveryEvents => _ladder.events;

  /// Adapter events of the currently attached adapter.
  ///
  /// Stays valid across backend swaps, unlike `adapter.events`.
  Stream<PlayerAdapterEvent> get adapterEvents => _adapterEvents.stream;

  /// Emitted whenever a different backend is attached.
  Stream<PlayerBackendChange> get backendChanges => _backendChanges.stream;

  /// Emitted whenever the open source changes.
  ///
  /// A recovery step that switches to another line changes the source
  /// without the caller asking, so callers that display or reference the
  /// current source must follow this stream instead of remembering what
  /// they passed to [open].
  Stream<PlayerSource?> get sourceChanges => _sourceChanges.stream;

  /// Failure the ladder is currently working on, if any.
  RecoveryFailure? get recoveryFailure => _ladder.failure;

  /// Decision context of the current recovery, if any.
  RecoverySession? get recoverySession => _ladder.session;

  /// Whether playback is restricted to the audio track.
  bool get audioOnly => _audioOnly;

  /// Current playback position, `Duration.zero` before any position event.
  Duration get position => _runtime.playback.current.position;

  /// What the engine currently reports as buffered, canonicalized.
  ///
  /// A progress bar's ahead-fill and a scrubber's "is the hovered
  /// position already downloaded" answer come from here. Empty is a
  /// fact about the backend (it declares
  /// [PlayerAdapterCapabilities.supportsBufferedRanges] false), not an
  /// error — draw no ahead-fill in that case rather than inventing
  /// one.
  PlaybackBuffer get buffer => _runtime.playback.current.buffer;

  /// Stream duration, `Duration.zero` while unknown.
  Duration get duration => _runtime.playback.current.duration;

  /// Buffered position: the end of the contiguous stretch at or ahead
  /// of the playhead.
  ///
  /// A backend that reports no ranges answers with the position itself,
  /// which reads as "no ahead fill" rather than inventing data; check
  /// [buffer] for the ranges behind the answer.
  Duration get buffered {
    final state = _runtime.playback.current;
    return state.buffer.bufferedEndAt(state.position);
  }

  /// Current volume (0.0–1.0) as last commanded or mirrored.
  double get volume => _runtime.playback.current.volume;

  /// Current playback rate.
  double get rate => _runtime.playback.current.rate;

  /// Progress through the stream, 0.0–1.0 (0.0 when duration is unknown).
  double get progress => _runtime.playback.current.progress;

  /// Whether the playback mirror currently reads "playing".
  bool get isPlaying => _runtime.playback.current.isPlaying;

  /// Whether output is muted.
  bool get muted => _muted;

  /// Whether playback restarts after completion.
  bool get loop => _loop;

  /// Typed playback-state stream. Identical to [playbackStream]; kept as
  /// the conventional name consumers reach for first.
  ValueStream<PlayerTransportState> get stateChanges => _runtime.playback.state;

  // ---------------------------------------------------------------------------
  // Recovery execution (RecoveryTarget)
  //
  // The ladder decides; this section performs. Every physical recovery
  // operation in the framework goes through one of these two methods, so
  // there is exactly one place where a backend is reopened or replaced.
  // ---------------------------------------------------------------------------

  @override
  bool get isRecoveryAvailable {
    return !_disposed && _currentSource != null;
  }

  @override
  Stream<RecoveryTargetEvent> get executionEvents => _targetEvents.stream;

  final StreamController<RecoveryTargetEvent> _targetEvents = StreamController<RecoveryTargetEvent>.broadcast();

  @override
  RecoverySession buildRecoverySession(RecoveryFailure failure, RecoveryCandidates candidates) {
    final current = _runtime.playback.current;

    return RecoverySession(
      failure: failure,
      source: _currentSource,
      sourceCandidates: candidates.sources,
      backendCandidates: candidates.backends,
      position: current.position,
      // The caller's intent wins over the adapter mirror. See [playIntent].
      //
      // The mirror is the fallback only when the caller never declared an
      // intent, and it is read from the session rather than from
      // `current.isPlaying`: a buffering notification replaces the transport
      // command in the mirror, so a stalled stream can read as "not playing"
      // and would then skip verification entirely.
      wasPlaying:
          playIntent ??
          _runtime.session.state.status == SessionStatus.playing ||
              _runtime.session.state.status == SessionStatus.buffering,
      volume: current.volume,
      rate: current.rate,
      backendId: _registration.id,
      generationId: _runtime.session.generation.id,
      attempt: _ladder.attempt,
    );
  }

  @override
  Future<void> reopenForRecovery(RecoveryStep step, RecoverySession session) {
    _ensureNotDisposed();

    final source = step.source ?? session.source ?? _currentSource;

    if (source == null) {
      throw StateError('Recovery step ${step.label} has no source to open.');
    }

    return _reopenOnCurrentBackend(step, source, session);
  }

  @override
  Future<void> swapToForRecovery(RecoveryStep step, RecoverySession session) {
    _ensureNotDisposed();

    final backendId = step.backendId;

    if (backendId == null) {
      throw StateError('Recovery step ${step.label} names no backend.');
    }

    final registration = _registry?.get(backendId);

    if (registration == null) {
      throw StateError('Backend "$backendId" is no longer registered.');
    }

    return _swapTo(step, registration, session);
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  /// Releases all resources owned by this handle.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _operationGeneration++;

    _currentSource = null;
    _backendReady = false;
    playIntent = null;

    MediaCoreLog.debug(LogCategory.player, 'disposing player ${_player.id.value} (backend ${_registration.id})');

    _cancelActiveOperation(StateError('PlayerHandle for ${_player.id} is being disposed.'));

    _ladder.suspend();

    // Stop handle-level adapter events first, then tear down the
    // runtime (which detaches its own bindings).
    await _adapterSubscription?.cancel();
    _adapterSubscription = null;

    _lifecycle.detach();

    await _record(
      OperationType.dispose,
      _enqueue(() async {
        // Runtime owns the adapter, session controller, playback
        // controller, geometry controller and both bindings.
        try {
          await _runtime.dispose();
        } on Object catch (_) {
          // Disposal continues even when the backend refuses.
        }

        // Handle-scoped modules.
        await _ladderEvents.cancel();
        await _ladder.dispose();
        await _backendChanges.close();
        await _sourceChanges.close();
        await _adapterEvents.close();

        // The recovery-target channel and the operation records are handle
        // scoped as well: leaving their controllers open means `executionEvents`
        // and `onOperation` never complete, and a subscriber keeps the handle
        // (and its whole operation history) alive after disposal.
        await _targetEvents.close();

        _operationTracker.dispose();
        _operationRegistry.dispose();

        _lifecycle.dispose();
      }, allowDisposed: true),
    );

    await _drainOperations();
  }
}

/// Supplies the ladder with the alternatives this handle may fall back to.
///
/// Two very different sources feed one candidate set: the caller owns the
/// list of playable sources (a live request knows its lines, the handle
/// does not), and the adapter registry owns the list of backends. Both
/// are filtered against what is currently in use, because the ladder must
/// never be offered the failing source or backend as its own alternative.
final class _HandleRecoveryCandidates implements RecoveryCandidateProvider {
  _HandleRecoveryCandidates(this._handle);

  final PlayerHandle _handle;

  @override
  RecoveryCandidates candidatesFor(RecoveryFailure failure) {
    final currentSourceId = _handle._currentSource?.id;
    final currentBackendId = _handle._registration.id;
    final source = _handle._currentSource;

    final sources = _handle._sourceCandidates
        .where((candidate) => candidate.id != currentSourceId)
        .toList(growable: false);

    final registry = _handle._registry;

    if (registry == null) {
      return RecoveryCandidates(sources: sources);
    }

    if (!_handle.engineFallbackEnabled) {
      return RecoveryCandidates(sources: sources);
    }

    final selector = _handle._selector ?? PlayerAdapterSelector(registry);

    // A composite handed to a single-URL backend plays video with no audio
    // and reports nothing, so recovery must not offer one as a swap target:
    // the ladder would burn every rung on a swap that cannot work, and an
    // adapter that implements PlayerAdapter directly would not even throw.
    final bridged = source == null ? null : MediaSourceBridge.fromPlayerSource(source);
    final needsComposite = bridged is CompositeMediaSource;

    // Ordering is the selector's job: it already scores protocol, format
    // and live support, so recovery does not re-implement "which backend
    // is most likely to play this".
    final backends = selector
        .candidatesFor(source ?? PlayerSource.unknown())
        .where((registration) => registration.id != currentBackendId)
        .where((registration) => registration.enabled)
        .where((registration) => !needsComposite || registration.capabilities.supportsComposite)
        .toList(growable: false);

    return RecoveryCandidates(sources: sources, backends: backends);
  }
}
