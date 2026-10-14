import 'dart:async';

import 'package:media_core/concurrency/serial_executor.dart';
import 'package:media_core/diagnostics/library.dart' show LogCategory, LogModule, MediaCoreLog;
import 'package:media_core/pool/player_pool_config.dart';
import 'package:media_core/pool/pool_player_host.dart';
import 'package:media_core/resource/resource_pressure.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// Decision trail for the pool.
///
/// Pool behaviour is invisible by design — the viewer sees the right item
/// playing, not the mechanism. When it goes wrong (a leaked player, a warm item
/// that never opens, playback stuck on the previous item), these are the lines
/// that say which of those it was.
final LogModule _log = MediaCoreLog.of(LogCategory.pool);

/// What the pool is doing with one item.
enum PooledItemRole {
  /// Playing or about to play: the item the viewer is looking at.
  active,

  /// Open but paused, so a swipe reaches it without a cold start.
  warming,

  /// Open for nothing: the item left the visible window and is only waiting to
  /// be reused or released.
  idle,

  /// Not held by the pool at all.
  released,
}

/// One item's assignment in the current plan.
final class PooledItemState {
  /// Describes item [index] of [source] carrying [role], on [playerId] when a
  /// player holds it.
  const PooledItemState({required this.index, required this.source, required this.role, this.playerId});

  /// Position of the item in the list.
  final int index;

  /// Source the item plays.
  final PlayerSource source;

  /// Role the pool gave this item in the current plan.
  final PooledItemRole role;

  /// PlayerIdentity holding this item, when one does.
  final String? playerId;

  @override
  String toString() => 'PooledItemState($index, ${role.name}${playerId == null ? '' : ', $playerId'})';
}

/// The pool's decision for the whole list after a reconciliation.
final class PlaybackPoolPlan {
  /// Describes the pool's holding after a reconciliation.
  const PlaybackPoolPlan({
    required this.items,
    required this.activeIndex,
    required this.playing,
    required this.warming,
    required this.released,
  });

  /// Every list item with the role the pool assigned to it.
  final List<PooledItemState> items;

  /// Item that should be playing, or `null` when nothing qualifies.
  final int? activeIndex;

  /// Indexes that were (re)started by this reconciliation.
  final Set<int> playing;

  /// Indexes opened to be warm.
  final Set<int> warming;

  /// Indexes whose player was given back.
  final Set<int> released;

  /// Number of players the pool is holding.
  int get heldCount => items.where((item) => item.role != PooledItemRole.released).length;

  @override
  String toString() =>
      'PlaybackPoolPlan(active: $activeIndex, held: $heldCount, warming: ${warming.length}, released: ${released.length})';
}

/// One item's bookkeeping inside the pool.
final class _Assignment {
  _Assignment({required this.handle, required this.index, required this.role, required this.since});

  final PoolPlayerHandle handle;
  int index;
  PooledItemRole role;
  Duration since;
  Duration? openedFor;

  /// The source the handle was last opened on.
  ///
  /// A list refresh, or an insertion above this item, can put a different video
  /// behind the same index; without this the pool would happily resume the
  /// stale source and the viewer would keep watching the item that used to be
  /// there.
  PlayerSource? openedSource;
}

/// Keeps a small set of players warm for an ordered list.
///
/// Responsibilities:
///
/// - decide which item plays, which neighbours stay warm and which player is
///   given back
/// - re-point an idle player at the next item instead of creating one
/// - pause instead of destroying when an item scrolls out of view
/// - shrink its own concurrency under resource pressure
///
/// It does not:
///
/// - render anything or own gestures (the host reports visibility)
/// - create players itself (a [PoolPlayerHost] does)
/// - decide a list's contents
///
/// ## Why this exists
///
/// Creating and destroying a player per item is the behaviour that makes a feed
/// stutter: every swipe pays decoder setup and teardown, and the teardown is
/// what leaks and heats. A bounded pool that re-points its players turns
/// "unlimited items" into "a handful of players", which is the whole idea behind
/// this orchestration.
///
/// ## What the host tells it
///
/// Visibility, per item, as a ratio — the same number a scroll view computes
/// for an item's intersection with the viewport. Playback follows that number
/// with hysteresis: above [PlayerPoolConfig.playVisibilityThreshold] an item
/// plays, below [PlayerPoolConfig.pauseVisibilityThreshold] it stops, and in
/// between nothing changes, so a partly visible item does not flap.
final class PlaybackPoolOrchestrator {
  /// Creates a pool over [host] with [config] and an injectable [clock].
  PlaybackPoolOrchestrator({
    required PoolPlayerHost host,
    PlayerPoolConfig config = const PlayerPoolConfig(),
    DateTime Function()? clock,
  }) : _host = host,
       _config = config,
       _clock = clock ?? DateTime.now;

  final PoolPlayerHost _host;
  final DateTime Function() _clock;

  PlayerPoolConfig _config;

  final Map<String, _Assignment> _assignments = <String, _Assignment>{};
  final Map<int, double> _ratios = <int, double>{};
  final Map<int, int> _reportOrder = <int, int>{};
  int _reportSequence = 0;
  final List<PlayerSource> _sources = <PlayerSource>[];

  /// Serializes reconciliations with the core's serial executor.
  final SerialExecutor _operations = SerialExecutor();

  /// Ledger of the players this pool holds.
  ///
  /// The pool is the module that decides how many decoders exist at once, so when
  /// memory is tight this is the account that says whether the pool is respecting
  /// its own limits (warm size, max players) or quietly growing past them.
  final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.pool);

  /// This instance's key in the shared pool account.
  late final String _memoryKey = memoryContributorKey(this);
  bool _disposed = false;
  bool _viewportVisible = true;
  bool _occluded = false;
  int? _activeIndex;
  int? _lastActiveIndex;
  ResourcePressure _pressure = ResourcePressure.none;

  /// Indexes the current reconciliation is about to need. Set while planning so
  /// a reusable player is never taken from an item that is about to become
  /// active or warm.
  Set<int> _plannedWindow = <int>{};

  /// Current configuration.
  PlayerPoolConfig get config => _config;

  /// Items the pool serves, in order.
  List<PlayerSource> get sources => List<PlayerSource>.unmodifiable(_sources);

  /// Number of players currently held.
  int get heldCount => _assignments.length;

  /// Item that should be playing, or `null`.
  int? get activeIndex => _activeIndex;

  /// Whether the list's viewport is visible at all.
  bool get isViewportVisible => _viewportVisible;

  /// Current resource pressure.
  ResourcePressure get pressure => _pressure;

  /// PlayerIdentity holding [index], when one does.
  PoolPlayerHandle? handleFor(int index) {
    for (final assignment in _assignments.values) {
      if (assignment.index == index) {
        return assignment.handle;
      }
    }
    return null;
  }

  /// Role of [index] in the current plan.
  PooledItemRole roleOf(int index) => handleFor(index) == null ? PooledItemRole.released : _roleOf(index);

  /// Replaces the list.
  ///
  /// Items that are still present keep their players, so refreshing a feed does
  /// not restart what is playing. Everything else is released.
  Future<PlaybackPoolPlan> setItems(List<PlayerSource> sources) {
    _ensureNotDisposed();
    _sources
      ..clear()
      ..addAll(sources);

    _ratios.removeWhere((index, _) => index >= _sources.length);
    return _enqueue(() async {
      final stale = _assignments.values.where((assignment) => assignment.index >= _sources.length).toList();
      for (final assignment in stale) {
        await _releaseAssignment(assignment);
      }
      // Indexes shift when items are inserted or removed, so an assignment that
      // survived keeps its player but must re-check whether it still holds the
      // source it was opened for.
      return await _reconcileLocked();
    });
  }

  /// Reports how much of item [index] is visible, as a 0..1 ratio.
  Future<PlaybackPoolPlan> onVisibilityChanged(int index, double ratio) {
    _ensureNotDisposed();
    _ratios[index] = ratio.clamp(0.0, 1.0);
    _reportOrder[index] = _reportSequence++;
    return _enqueue(_reconcileLocked);
  }

  /// Reports that the whole list scrolled out of view.
  Future<PlaybackPoolPlan> setViewportVisible({required bool visible}) {
    _ensureNotDisposed();
    if (_viewportVisible == visible) {
      return Future<PlaybackPoolPlan>.value(currentPlan);
    }
    _viewportVisible = visible;
    _log.debug('list viewport visibility changed', fields: <String, Object?>{'visible': visible});
    return _enqueue(_reconcileLocked);
  }

  /// Reports that the app itself is not visible (backgrounded, another route).
  Future<PlaybackPoolPlan> setOccluded({required bool occluded}) {
    _ensureNotDisposed();
    if (_occluded == occluded) {
      return Future<PlaybackPoolPlan>.value(currentPlan);
    }
    _occluded = occluded;
    _log.debug('app occlusion changed', fields: <String, Object?>{'occluded': occluded});
    return _enqueue(_reconcileLocked);
  }

  /// Reports device pressure.
  ///
  /// Pressure is applied immediately rather than at the next visibility event:
  /// a device in trouble does not wait for the viewer to scroll.
  Future<PlaybackPoolPlan> reportPressure(ResourcePressure pressure) {
    _ensureNotDisposed();
    _log.debug(
      'device pressure reported to the pool',
      fields: <String, Object?>{
        'hasPressure': pressure.hasPressure,
        'stopPreload': pressure.shouldStopPreload,
        'releaseResources': pressure.shouldReleaseResources,
      },
    );
    _pressure = pressure;
    return _enqueue(_reconcileLocked);
  }

  /// Applies a new configuration and re-plans.
  Future<PlaybackPoolPlan> updateConfig(PlayerPoolConfig config) {
    _ensureNotDisposed();
    _config = config;
    return _enqueue(_reconcileLocked);
  }

  /// Releases every player the pool holds.
  Future<PlaybackPoolPlan> releaseAll() {
    _ensureNotDisposed();
    return _enqueue(() async {
      final released = <int>{};
      for (final assignment in _assignments.values.toList()) {
        released.add(assignment.index);
        await _releaseAssignment(assignment);
      }
      _activeIndex = null;
      _lastActiveIndex = null;
      _reportMemory();
      _log.debug('released every pooled player', fields: <String, Object?>{'released': released.length});
      return _buildPlan(const <int>{}, const <int>{}, released);
    });
  }

  /// Used by hosts that want to observe the plan without triggering it.
  PlaybackPoolPlan get currentPlan => _buildPlan(const <int>{}, const <int>{}, const <int>{});

  /// Releases the pool.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    try {
      await releaseAll();
    } on Object catch (_) {
      // A pool that cannot hand its players back is still disposed: the caller
      // has no recovery for a kernel that refuses to release, and leaving the
      // orchestrator usable would only repeat the failure.
    }
    _disposed = true;
    _memory.withdraw(_memoryKey);
  }

  // ---------------------------------------------------------------------------
  // Reconciliation
  // ---------------------------------------------------------------------------

  /// Re-plans the pool against the current visibility and configuration.
  Future<PlaybackPoolPlan> reconcile() {
    _ensureNotDisposed();
    return _enqueue(_reconcileLocked);
  }

  Future<PlaybackPoolPlan> _reconcileLocked() async {
    if (_disposed || _sources.isEmpty) {
      return _buildPlan(const <int>{}, const <int>{}, const <int>{});
    }

    final playing = <int>{};
    final warming = <int>{};
    final released = <int>{};

    final target = _resolveTargetIndex();
    final window = _warmWindow(target);
    _plannedWindow = window;

    if (target == null) {
      // Nothing qualifies: pause whatever was active and keep the warm window
      // anchored where the viewer left off, so scrolling back is still cheap.
      for (final assignment in _assignments.values) {
        if (assignment.role == PooledItemRole.active) {
          _log.debug(
            'no item qualifies: standing down the active player',
            fields: <String, Object?>{
              'index': assignment.index,
              'viewportVisible': _viewportVisible,
              'occluded': _occluded,
              'activeRatio': _ratios[assignment.index],
            },
          );
          await assignment.handle.pause();
          await assignment.handle.recycle();
          assignment.role = PooledItemRole.idle;
        }
      }
    } else {
      await _demoteFormerActive(target);
      await _ensureActive(target, playing);
    }

    await _ensureWarm(window, warming, target);
    await _releaseOutside(window, target, released);

    _activeIndex = target;
    if (target != null) {
      _lastActiveIndex = target;
    }

    _reportMemory();

    _log.debug(
      'pool reconciled',
      fields: <String, Object?>{
        'active': target,
        'playing': playing.length,
        'warming': warming.length,
        'released': released.length,
        'held': _assignments.length,
        'budget': _config.maxPlayers,
        'preloadCount': _effectivePreloadCount,
      },
    );

    return _buildPlan(playing, warming, released);
  }

  /// Demotes the previously active item to idle.
  ///
  /// Without this the old active keeps its role forever: it is neither in the
  /// warm window (so it is never reused) nor idle (so it is never released),
  /// and the pool grows by one player per item watched.
  Future<void> _demoteFormerActive(int target) async {
    for (final assignment in _assignments.values) {
      if (assignment.role != PooledItemRole.active || assignment.index == target) {
        continue;
      }
      _log.debug(
        'demoting the previously active item',
        fields: <String, Object?>{'from': assignment.index, 'to': target, 'playerId': assignment.handle.id},
      );
      await assignment.handle.pause();
      assignment
        ..role = PooledItemRole.idle
        ..since = _now;
    }
  }

  int _orderOf(int index) => _reportOrder[index] ?? -1;

  int? _resolveTargetIndex() {
    if (!_viewportVisible || _occluded) {
      return null;
    }

    int? best;
    double bestRatio = 0;
    for (final entry in _ratios.entries) {
      if (entry.key >= _sources.length) {
        continue;
      }
      // Equal ratios are broken by recency: a scroll view reports the item it
      // settled on last, and that is the one the viewer is looking at.
      final better =
          entry.value > bestRatio || (entry.value == bestRatio && best != null && _orderOf(entry.key) > _orderOf(best));
      if (better || best == null) {
        bestRatio = bestRatio > entry.value ? bestRatio : entry.value;
        best = entry.key;
      }
    }

    // A clearly visible item wins outright. This is the swipe case: the viewer
    // is looking at another item now, and no amount of hysteresis should keep
    // the previous one playing.
    if (best != null && bestRatio >= _config.playVisibilityThreshold) {
      return best;
    }

    // Nothing is clearly visible — mid-scroll, or a neighbour barely peeking
    // in. Keeping the current item while it is still reasonably on screen is
    // what stops playback from stopping and starting on every scroll frame.
    if (_activeIndex != null && (_ratios[_activeIndex] ?? 0) >= _config.pauseVisibilityThreshold) {
      return _activeIndex;
    }

    return null;
  }

  Set<int> _warmWindow(int? target) {
    final anchor = target ?? _lastActiveIndex;
    if (anchor == null) {
      return <int>{};
    }

    final count = _effectivePreloadCount;
    final window = <int>{};
    for (var offset = -count; offset <= count; offset++) {
      final index = anchor + offset;
      if (index >= 0 && index < _sources.length) {
        window.add(index);
      }
    }
    if (target != null) {
      window.add(target);
    }
    return window;
  }

  /// Preload count after pressure is taken into account.
  ///
  /// Warming is the first thing to give up under pressure: it costs a decoder
  /// for something the viewer has not asked for yet.
  int get _effectivePreloadCount {
    if (_pressure.shouldStopPreload) {
      return 0;
    }
    if (_pressure.hasPressure) {
      return (_config.preloadCount / 2).floor();
    }
    return _config.preloadCount;
  }

  Future<void> _ensureActive(int index, Set<int> playing) async {
    final existing = _findAssignment(index);
    if (existing != null) {
      final source = _sources[index];
      if (existing.openedSource != null && existing.openedSource != source) {
        // The item behind this index was replaced - a refresh, or an insertion
        // above it shifted the list. Resuming the held player would keep
        // playing the video that used to sit here.
        _log.debug(
          're-opening the active player for a replaced source',
          fields: <String, Object?>{
            'index': index,
            'playerId': existing.handle.id,
            'was': existing.openedSource?.uri,
            'now': source.uri,
          },
        );
        await existing.handle.open(source, autoPlay: true);
        existing
          ..openedSource = source
          ..role = PooledItemRole.active;
        playing.add(index);
        _refreshOpenTarget(existing);
        return;
      }

      if (existing.role != PooledItemRole.active) {
        _log.debug(
          'resuming a held item instead of opening a new player',
          fields: <String, Object?>{'index': index, 'from': existing.role.name, 'playerId': existing.handle.id},
        );
        await existing.handle.play();
        existing.role = PooledItemRole.active;
        playing.add(index);
      }
      _refreshOpenTarget(existing);
      return;
    }

    final handle = await _takeHandle(excludeIndex: index);
    _log.debug(
      'opening the active item',
      fields: <String, Object?>{'index': index, 'playerId': handle.id, 'uri': _sources[index].uri},
    );
    await handle.open(_sources[index], autoPlay: true);
    _assign(handle, index, PooledItemRole.active).openedSource = _sources[index];
    playing.add(index);
  }

  Future<void> _ensureWarm(Set<int> window, Set<int> warming, int? target) async {
    for (final index in window) {
      if (index == target) {
        continue;
      }
      final existing = _findAssignment(index);
      if (existing != null) {
        if (existing.openedSource != null && existing.openedSource != _sources[index]) {
          // Same replacement as in the active case: re-point the held player at
          // the item that is actually here now, still without playing it.
          await existing.handle.open(_sources[index], autoPlay: false);
          existing
            ..openedSource = _sources[index]
            ..openedFor = _now;
          if (existing.role != PooledItemRole.idle) {
            warming.add(index);
          }
          continue;
        }
        if (existing.role == PooledItemRole.active) {
          // It was playing and is now only warm: stop it, keep it open.
          await existing.handle.pause();
          existing.role = PooledItemRole.warming;
        } else if (existing.role == PooledItemRole.idle) {
          // Demoted from active by the previous step and now back inside the warm
          // window: it is held for this item, not idle for nothing. Reporting it
          // as idle under-counts the warm window and makes a plan read as if the
          // pool were holding a player it had already given back.
          existing.role = PooledItemRole.warming;
        }
        continue;
      }

      if (!_canWarm) {
        continue;
      }

      final handle = await _takeHandle(excludeIndex: index);
      final timeout = _config.preloadTimeout;
      try {
        await (timeout == null
            ? handle.open(_sources[index], autoPlay: false)
            : handle.open(_sources[index], autoPlay: false).timeout(timeout));
      } on TimeoutException {
        // A warm player that cannot even open is not worth holding: it is
        // costing a decoder for something the viewer has not asked for.
        _log.warning(
          'warm open timed out; the player goes back',
          fields: <String, Object?>{'index': index, 'playerId': handle.id, 'timeoutMs': timeout?.inMilliseconds},
        );
        await _host.release(handle);
        continue;
      }
      _assign(handle, index, PooledItemRole.warming)
        ..openedSource = _sources[index]
        ..openedFor = _now;
      warming.add(index);
      _log.debug('warming an item', fields: <String, Object?>{'index': index, 'playerId': handle.id});
    }
  }

  Future<void> _releaseOutside(Set<int> window, int? target, Set<int> released) async {
    final now = _now;
    final idleTimeout = _config.idleTimeout;

    for (final assignment in _assignments.values.toList()) {
      if (window.contains(assignment.index)) {
        continue;
      }
      if (assignment.role == PooledItemRole.active) {
        continue;
      }

      final idleFor = now - assignment.since;
      final expired = idleTimeout != null && idleFor >= idleTimeout;
      final pressureRelease = _pressure.shouldStopPreload;

      if ((expired || pressureRelease) && !_shouldKeepWarm) {
        released.add(assignment.index);
        _log.debug(
          'releasing an item outside the warm window',
          fields: <String, Object?>{
            'index': assignment.index,
            'playerId': assignment.handle.id,
            'role': assignment.role.name,
            'idleMs': idleFor.inMilliseconds,
            'expired': expired,
            'pressure': pressureRelease,
          },
        );
        await _releaseAssignment(assignment);
      }
    }
  }

  /// Whether another warm player is still allowed.
  ///
  /// Two bounds apply: the configured warm size (0 means unbounded) and, when
  /// set, the absolute player cap. Both are about decoders — a warm player
  /// costs one whether or not it is playing.
  bool get _canWarm {
    if (_config.maxPlayers > 0 && _assignments.length >= _config.maxPlayers) {
      return false;
    }
    final warmSize = _config.warmSize;
    if (warmSize <= 0) {
      return true;
    }
    final warmCount = _assignments.values.where((assignment) => assignment.role == PooledItemRole.warming).length;
    return warmCount < warmSize;
  }

  /// Whether idle players should be kept rather than released.
  bool get _shouldKeepWarm {
    if (!_config.keepWarm) {
      return false;
    }
    final warmSize = _config.warmSize;
    return warmSize <= 0 || _assignments.length <= warmSize;
  }

  _Assignment? _findAssignment(int index) {
    for (final assignment in _assignments.values) {
      if (assignment.index == index) {
        return assignment;
      }
    }
    return null;
  }

  Future<PoolPlayerHandle> _takeHandle({required int excludeIndex}) async {
    if (_config.reuseIdlePlayers) {
      final reusable = _findReusable(excludeIndex: excludeIndex);
      if (reusable != null) {
        // A re-point is the cheap path: the player is already open, so the item
        // it is about to carry pays no cold start.
        _log.debug(
          're-pointing an idle player',
          fields: <String, Object?>{'playerId': reusable.handle.id, 'from': reusable.index, 'to': excludeIndex},
        );
        return reusable.handle;
      }
    }
    final handle = await _host.acquire();
    _log.debug('acquired a player from the host', fields: <String, Object?>{'playerId': handle.id});
    return handle;
  }

  /// An idle player the pool may re-point at another item.
  ///
  /// Anything the current plan needs — the active item, the warm window, the
  /// item being planned — is off limits: taking one of those would turn a cheap
  /// re-point into a re-open of something the viewer is about to look at.
  _Assignment? _findReusable({required int excludeIndex}) {
    for (final assignment in _assignments.values) {
      if (assignment.index == excludeIndex) {
        continue;
      }
      if (assignment.role == PooledItemRole.active) {
        continue;
      }
      if (_plannedWindow.contains(assignment.index)) {
        continue;
      }
      return assignment;
    }
    return null;
  }

  _Assignment _assign(PoolPlayerHandle handle, int index, PooledItemRole role) {
    // The handle may already be tracked under another index (a re-point).
    _assignments.remove(handle.id);
    final assignment = _Assignment(handle: handle, index: index, role: role, since: _now);
    _assignments[handle.id] = assignment;
    return assignment;
  }

  PooledItemRole _roleOf(int index) {
    final assignment = _findAssignment(index);
    return assignment?.role ?? PooledItemRole.released;
  }

  void _refreshOpenTarget(_Assignment assignment) {
    assignment.openedFor = null;
  }

  Future<void> _releaseAssignment(_Assignment assignment) async {
    _assignments.remove(assignment.handle.id);
    if (assignment.handle.isDisposed) {
      return;
    }
    await assignment.handle.pause();
    if (_config.enableRecycle) {
      // Back to the host, which may return it from the kernel's instance pool.
      await assignment.handle.recycle();
      await _host.release(assignment.handle);
      return;
    }
    await _host.disposeHandle(assignment.handle);
  }

  /// Reports how many players the pool is holding, and in which roles.
  void _reportMemory() {
    var active = 0;
    var warming = 0;
    var idle = 0;
    for (final assignment in _assignments.values) {
      switch (assignment.role) {
        case PooledItemRole.active:
          active++;
        case PooledItemRole.warming:
          warming++;
        case PooledItemRole.idle:
          idle++;
        case PooledItemRole.released:
          break;
      }
    }

    final held = active + warming + idle;
    _memory.report(
      _memoryKey,
      items: held,
      bytes: held * MemoryEstimates.videoStream720p,
      note: '$active active, $warming warm, $idle idle',
    );
  }

  PlaybackPoolPlan _buildPlan(Set<int> playing, Set<int> warming, Set<int> released) {
    final items = <PooledItemState>[];
    for (var index = 0; index < _sources.length; index++) {
      final assignment = _findAssignment(index);
      items.add(
        PooledItemState(
          index: index,
          source: _sources[index],
          role: assignment?.role ?? PooledItemRole.released,
          playerId: assignment?.handle.id,
        ),
      );
    }
    return PlaybackPoolPlan(
      items: items,
      activeIndex: _activeIndex,
      playing: playing,
      warming: warming,
      released: released,
    );
  }

  Duration get _now => Duration(milliseconds: _clock().millisecondsSinceEpoch);

  Future<T> _enqueue<T>(Future<T> Function() operation) => _operations.execute(operation);

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PlaybackPoolOrchestrator has been disposed.');
    }
  }
}
