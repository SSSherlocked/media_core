import 'dart:async';

import 'package:media_core/media_core.dart';

import 'package:media_core_live/src/live_source_request.dart';
import 'package:media_core_live/src/live_watchdogs.dart';

// The implementation of [LivePlaybackController] is split by concern
// across `part` files next to this one:
//
// - `live_playback_sweep.dart`     engine × source sweep with staged verification
// - `live_playback_pipeline.dart`  engine order, handle lifecycle, watchdog
//                                  wiring, single-slot task queue
//
// The public API — streams, getters and the queued actions — stays here.

part 'live_playback_sweep.dart';
part 'live_playback_pipeline.dart';

/// Resolves the sources for the next engine of a sweep.
///
/// Invoked *before* the controller attaches the next engine, with the
/// engine id that is about to be attached and the sources that just
/// failed. Many live-site URLs are signed and single-use — consumed by
/// the first engine's attempt — so the caller usually wants to refetch
/// fresh lines here. Return the new sources to sweep from line 0, an
/// empty list to reuse the current ones.
typedef EngineFallbackSourceResolver =
    Future<List<PlayerSource>> Function(String nextEngine, List<PlayerSource> currentSources);

/// Resolves fresh sources for a recovery attempt.
///
/// Invoked at the top of a recover task — a watchdog stall or an adapter
/// error during otherwise normal playback — before the sweep re-opens
/// anything, with the sources that just died. Signed live URLs expire on
/// the platform's clock, not the player's, so re-opening the line that
/// stalled retries an address the server has already rejected; the caller
/// is the only party that can ask the platform again.
///
/// Return the candidates **in preference order** — the sweep starts at
/// index 0 — an empty list to reuse the current ones, and let a failure
/// propagate: the recovery keeps the lines it has and reports the stall
/// instead of hanging on the refresh.
typedef RecoverySourceResolver = Future<List<PlayerSource>> Function(List<PlayerSource> currentSources);

/// Orchestrates live playback on top of a [PlayerKernel].
///
/// One structural idea holds the module together: **every action is a task
/// on a single-slot [TaskManager]** — play, switch line, retry, pause,
/// resume, close, recover. The queue serializes them, so none of the
/// classic live-playback races can exist by construction:
///
/// - a recovery task and a user action cannot interleave — the user's task
///   runs first, and queued recovery work is cancelled when the user takes
///   over ([pause], [close], [play], [retry], [switchLine]);
/// - two rapid `play()` calls cannot double-open — the first is cancelled
///   out of the queue before the second starts;
/// - an engine switch cannot replay a stale request over a newer one —
///   there is no delayed replay anywhere; a switch is just the next task.
///
/// Recovery is a plain function of the caller's declarations, not a
/// subsystem:
///
/// ```text
/// attempt(source, engine) fails
///   → next source on the same engine           (the lines the caller gave)
///   → sources exhausted → next engine, sweep again    (if the caller allowed)
///   → nothing left → PlayerFailure on [onError]
/// ```
///
/// "Fails" means one of: the open threw, the engine could not be attached,
/// or — the case that used to look like a freeze — the source opened
/// cleanly but playback position never advanced within
/// [LiveWatchdogs.sourceReadyTimeout]. Verification is what makes the
/// sweep honest.
///
/// Watchdogs stay pure detectors: a stall or an adapter error becomes a
/// recover task, which offers the caller a chance to hand over fresh lines
/// ([onRecoverySources]) and then joins the same sweep — on the refreshed
/// lines if there are any, on the line that was playing otherwise. The
/// kernel-side recovery ladder is disabled for live players, so there is
/// exactly one recovery path and the caller can read all of it here.

final class LivePlaybackController {
  /// Creates a live playback owner on [kernel].
  ///
  /// [watchdogs] defaults to a bundle with this module's deadlines; pass one
  /// with `enabled: false` to drive the sweep without stall detection, or a
  /// shorter [LiveWatchdogs.sourceReadyTimeout] to shorten the sweep's
  /// verification window. [onEngineFallbackSources] and [onRecoverySources]
  /// are the caller's chances to hand over fresh lines before lines are
  /// re-opened.
  LivePlaybackController(this.kernel, {LiveWatchdogs? watchdogs, this.onEngineFallbackSources, this.onRecoverySources})
    : watchdogs = watchdogs ?? LiveWatchdogs() {
    _wireWatchdogs();
  }

  /// The kernel providing players and adapters.
  final PlayerKernel kernel;

  /// Called before the sweep attaches the next engine, when every line
  /// failed on the current one. See [EngineFallbackSourceResolver].
  ///
  /// Null — the default — reuses the existing lines for the next engine.
  final EngineFallbackSourceResolver? onEngineFallbackSources;

  /// Called before a recovery attempt re-opens anything, so an expired
  /// signed URL can be replaced instead of retried. See
  /// [RecoverySourceResolver].
  ///
  /// Null — the default — re-opens the lines the sweep already holds.
  final RecoverySourceResolver? onRecoverySources;

  /// Watchdog bundle inferring stalls.
  final LiveWatchdogs watchdogs;

  /// Single-slot queue. Every user action and every recovery step is a
  /// task here; capacity one makes the controller sequential by design.
  final TaskManager _tasks = TaskManager();

  final Map<TaskId, _PendingTask> _pending = <TaskId, _PendingTask>{};

  bool _draining = false;
  bool _disposed = false;

  /// Last adapter error seen while a sweep is running.
  ///
  /// The verification loop checks this, so an engine-reported failure fails
  /// the candidate immediately instead of waiting out the full verification
  /// window.
  ///
  /// While a sweep is running, adapter errors and watchdog stalls are the
  /// *running sweep's* business — its own catch already advances to the next
  /// candidate. Enqueueing a recovery task on top used to start a second
  /// sweep that re-opened line 0 behind the first one's back.
  String? _sweepAdapterError;

  /// Bumped by [play] and [close]. A sweep captures it when it starts and
  /// abandons itself if it moved meanwhile.
  int _playGeneration = 0;

  LiveSourceRequest? _request;

  /// Ledger of the candidate lines and engines this sweep holds.
  ///
  /// The player being watched is counted by the kernel, not here: what this
  /// module owns is the fallback list, and the list is what tells a reader how
  /// many signed URLs are being kept alive.
  /// This instance's key in the shared account.
  late final String _memoryKey = memoryContributorKey(this);

  final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.live);

  /// Reports the candidate lines and engines the sweep is holding.
  void _reportMemory() {
    final entries = _sources.length + _engines.length;
    _memory.report(
      _memoryKey,
      items: entries,
      bytes: entries * MemoryEstimates.cacheEntry,
      note: '${_sources.length} line(s), ${_engines.length} engine(s) in the sweep',
    );
  }

  List<PlayerSource> _sources = const <PlayerSource>[];
  List<String> _engines = const <String>[];
  int _engineIndex = 0;
  int _sourceIndex = 0;
  PlayerHandle? _handle;
  PlayerSource? _currentSource;
  String? _preferredBackend;
  bool _engineFallbackAllowed = true;
  bool _playbackRequested = false;
  bool _audioOnly = false;

  /// The playback state the controller mirrors for its consumers.
  ///
  /// Written on every transition the controller observes — the sweep's own
  /// phases plus the adapter events it re-mirrors — and published on
  /// [onStateChanged]; read directly by callers that want the current value
  /// without subscribing.
  PlayerCoreState state = PlayerCoreState.idle;

  /// Line each engine's sweep starts from: the line that was being played
  /// when the previous engine failed, so a fresh engine first retries the
  /// line the user was watching.
  int _sweepStart = 0;

  final StreamController<PlayerCoreState> _stateController = StreamController<PlayerCoreState>.broadcast();
  final StreamController<PlayerHandle> _handleController = StreamController<PlayerHandle>.broadcast();
  final StreamController<PlayerFailure> _failureController = StreamController<PlayerFailure>.broadcast();
  StreamSubscription<PlayerAdapterEvent>? _adapterSub;
  StreamSubscription<PlayerBackendChange>? _backendSub;

  /// Playback state stream.
  Stream<PlayerCoreState> get onStateChanged => _stateController.stream;

  /// Emitted whenever the attached handle changes - an engine switch
  /// committed a staged player, or the player was released. Consumers that
  /// render the video surface must rebind on this and not on the old
  /// handle's own streams: the old handle is disposed by the time the new
  /// one is committed, so subscriptions taken from it go dead.
  Stream<PlayerHandle> get onHandleChanged => _handleController.stream;

  /// Terminal failure stream. Emitted exactly once per exhausted sweep.
  Stream<PlayerFailure> get onError => _failureController.stream;

  /// The active player handle, when one exists.
  PlayerHandle? get handle => _handle;

  /// Current backend id, when a handle exists.
  String? get backendId => _handle?.backendId;

  /// Identity of the logical player, when a handle exists.
  ///
  /// One identity per player, owned by the handle — the controller does
  /// not mint its own.
  PlayerId? get playerId => _handle?.id;

  /// Latest session snapshot of the player.
  ///
  /// The session is the handle's; this is a passthrough, not a second one.
  SessionSnapshot? get sessionSnapshot => _handle?.snapshot;

  /// Candidate sources of the active request.
  List<PlayerSource> get sources => _sources;

  /// Index of the source currently being played.
  int get sourceIndex => _sourceIndex;

  /// Whether playback is restricted to the audio track.
  bool get audioOnly => _audioOnly;

  // ---------------------------------------------------------------------------
  // Public actions — every one of them a queued task
  // ---------------------------------------------------------------------------

  /// Starts playing [request].
  ///
  /// [preferredBackend] pins the engine for this playback; when omitted the
  /// engine order is the selector's scored order for the primary source.
  Future<void> play(LiveSourceRequest request, {String? preferredBackend}) {
    _request = request;
    _sources = request.sources;
    _reportMemory();
    _preferredBackend = preferredBackend;
    _engineFallbackAllowed = request.allowEngineFallback ?? true;
    // Engine escalation is allowed for every request unless the caller
    // explicitly refuses it. A single-URL request has no other line to
    // sweep, so its sweep is one engine, one line — but if that fails the
    // next engine still gets its turn on the same URL before the failure
    // is surfaced. The number of URLs decides how much *line* fallback
    // there is, never whether engines may be tried.
    _playbackRequested = true;
    _playGeneration++;
    _sweepStart = 0;

    _supersedeQueued('superseded by play');

    return _enqueue(TaskType.open, (_) => _startPlayback());
  }

  /// Switches to the source at [index].
  Future<void> switchLine(int index) {
    if (index < 0 || index >= _sources.length) {
      return Future<void>.value();
    }

    _sourceIndex = index;
    _sweepStart = index;
    _playbackRequested = true;
    _playGeneration++;

    _supersedeQueued('superseded by line switch');

    return _enqueue(TaskType.load, (_) => _openCurrentSource());
  }

  /// Replays the current source from scratch.
  Future<void> retry() {
    if (_request == null || _sources.isEmpty) {
      return Future<void>.value();
    }

    _playbackRequested = true;
    _playGeneration++;

    _supersedeQueued('superseded by retry');

    return _enqueue(TaskType.retry, (_) => _openCurrentSource());
  }

  /// Pauses playback. Cancels queued recovery: a user pause is a recovery
  /// boundary, not a recovery opportunity.
  Future<void> pause() async {
    _playbackRequested = false;
    _playGeneration++;

    _supersedeQueued('superseded by pause');

    watchdogs.cancelAll();

    await _enqueue(TaskType.pause, (token) async {
      await _handle?.pause();
      _setState(_liveState(PlayerPlaybackState.paused));
    });
  }

  /// Resumes playback.
  Future<void> resume() async {
    _playbackRequested = true;

    await _enqueue(TaskType.play, (token) async {
      final handle = _handle;

      if (handle == null || handle.disposed) {
        return;
      }

      await handle.play();
      _setState(_liveState(PlayerPlaybackState.playing));
    });
  }

  /// Toggles pause/resume.
  Future<void> togglePlayPause() async {
    if (state.playback == PlayerPlaybackState.playing) {
      await pause();
    } else {
      await resume();
    }
  }

  /// Sets volume (0.0–1.0).
  Future<void> setVolume(double volume) {
    return _handle?.setVolume(volume.clamp(0.0, 1.0)) ?? Future<void>.value();
  }

  /// Mutes or unmutes audio output.
  ///
  /// Mute lives on the attached engine, so with no handle yet — or a released
  /// one — there is nothing to mute and the request is dropped quietly, like
  /// every other transport command issued between playbacks.
  Future<void> setMute({required bool muted}) {
    return _handle?.setMute(muted: muted) ?? Future<void>.value();
  }

  /// Whether audio output is muted.
  bool get muted => _handle?.muted ?? false;

  /// Sets whether playback restarts after completion.
  Future<void> setLoop({required bool loop}) {
    return _handle?.setLoop(loop: loop) ?? Future<void>.value();
  }

  /// Current playback position on the attached engine.
  Duration get position => _handle?.position ?? Duration.zero;

  /// Stream duration on the attached engine, `Duration.zero` while no handle
  /// is attached.
  ///
  /// Passed through exactly as the engine reports it, which is not the same
  /// thing on every backend: some answer zero for a live line, others answer
  /// the elapsed time since the stream started. A UI that needs "is this
  /// live" reads the source declaration, not this value.
  Duration get duration => _handle?.duration ?? Duration.zero;

  /// Restricts playback to the audio track.
  ///
  /// The preference is remembered by the controller as well as the engine, so
  /// an engine switch or a recovery that reopens a fresh adapter keeps audio
  /// only instead of silently restoring video.
  Future<void> setAudioOnly({required bool audioOnly}) async {
    _audioOnly = audioOnly;

    watchdogs.setVideoExpected(expected: !audioOnly);

    await _handle?.setAudioOnly(audioOnly: audioOnly);
  }

  /// Marks whether the current route owns the mounted video presentation.
  void setPresentationVisible({required bool visible}) {
    watchdogs.setPresentationVisible(visible: visible);
  }

  /// Records that the app was backgrounded and the player was auto-paused.
  ///
  /// Without this, the unexpected-pause watchdog reads the background
  /// auto-pause as a network fault and silently resumes playback the user
  /// cannot see. A background pause is a system intent: playback is no
  /// longer requested until the user resumes.
  void noteBackgrounded() {
    _playbackRequested = false;

    watchdogs.cancelAll();
  }

  /// Stops playback and releases the player.
  Future<void> close() async {
    _playbackRequested = false;
    _playGeneration++;

    _supersedeQueued('superseded by close');

    watchdogs.cancelAll();

    await _enqueue(TaskType.close, (token) async {
      await _releaseHandle();
      _setState(PlayerCoreState.idle);
    });
  }

  /// Disposes the controller.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _playbackRequested = false;
    _playGeneration++;

    _supersedeQueued('superseded by dispose');
    watchdogs.cancelAll();

    await _adapterSub?.cancel();
    _adapterSub = null;
    await _backendSub?.cancel();
    _backendSub = null;

    await _releaseHandle();

    watchdogs.dispose();

    _memory.withdraw(_memoryKey);

    _tasks.dispose();
    await _stateController.close();
    await _handleController.close();
    await _failureController.close();
  }
  // ---------------------------------------------------------------------------
  // State mirroring
  // ---------------------------------------------------------------------------

  PlayerCoreState _liveState(PlayerPlaybackState playback) {
    return PlayerCoreState(lifecycle: PlayerLifecycleState.ready, playback: playback, hasSource: _sources.isNotEmpty);
  }

  void _setState(PlayerCoreState next) {
    if (state == next) {
      return;
    }

    state = next;

    // Mirror into the handle's session — the one session this player has.
    // Consumers reading SessionSnapshot from the handle see the same
    // lifecycle the controller reports on [onStateChanged].
    _handle?.session.updateState(_toSessionState(next));

    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  SessionState _toSessionState(PlayerCoreState playerState) {
    return switch (playerState.playback) {
      PlayerPlaybackState.idle => const SessionState.idle(),
      PlayerPlaybackState.opening => const SessionState.opening(),
      PlayerPlaybackState.playing => const SessionState.playing(),
      PlayerPlaybackState.paused => const SessionState.paused(),
      PlayerPlaybackState.buffering => const SessionState.buffering(),
      PlayerPlaybackState.stopped || PlayerPlaybackState.stopping => const SessionState.stopped(),
      PlayerPlaybackState.completed => const SessionState.completed(),
      PlayerPlaybackState.error => const SessionState.error(),
      // Live streams do not seek; treat as an in-flight transition.
      PlayerPlaybackState.seeking => const SessionState.buffering(),
    };
  }
}
