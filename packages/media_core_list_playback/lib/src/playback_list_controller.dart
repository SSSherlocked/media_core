import 'dart:async';

import 'package:equatable/equatable.dart' show Equatable;
import 'package:media_core/media_core.dart'
    show
        LogCategory,
        LogModule,
        MediaCoreLog,
        MediaCoreMemory,
        MemoryAccount,
        MemoryEstimates,
        MemoryModule,
        PlaybackPoolOrchestrator,
        PoolPlayerHandle,
        memoryContributorKey;

import 'package:media_core_list_playback/src/playback_list_config.dart';
import 'package:media_core_list_playback/src/playback_list_item.dart';
import 'package:media_core_list_playback/src/playback_list_player.dart';
import 'package:media_core_list_playback/src/playback_progress_store.dart';

/// Decision trail for list playback.
///
/// Two behaviours are invisible when they work and confusing when they do not:
/// whether an item resumed from a remembered position or started over, and
/// whether the item was opened through the pool or by the list's own player.
/// Both are recorded on every open.
final LogModule _log = MediaCoreLog.of(LogCategory.playback);

/// Ledger of the list's items and remembered positions.
///
/// Both are metadata: the list drives a player it does not own, so what it can
/// account for is the list itself plus the progress entries it keeps for resume.
final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.playback);

/// Immutable snapshot of a playback list.
final class PlaybackListState extends Equatable {
  /// Creates a snapshot describing the open [index] of [count], the current
  /// [item], any [resumedFrom] position, whether a source is [opening], and the
  /// last [error].
  const PlaybackListState({
    this.index = 0,
    this.count = 0,
    this.item,
    this.resumedFrom,
    this.opening = false,
    this.error,
  });

  /// Index of the item currently open.
  final int index;

  /// Number of items in the list.
  final int count;

  /// Item currently open, or `null` when the list is empty.
  final PlaybackListItem? item;

  /// Position playback resumed from, when the item did not start at zero.
  ///
  /// Reported so a host can say "resumed" instead of silently jumping, which
  /// otherwise looks like a glitch to a viewer who expected the beginning.
  final Duration? resumedFrom;

  /// Whether a source is being opened.
  final bool opening;

  /// Last failure, if any.
  final Object? error;

  /// Whether the list holds no items.
  bool get isEmpty => count == 0;

  /// Whether swiping up would move to another item.
  bool get hasNext => index + 1 < count;

  /// Whether swiping down would move to another item.
  bool get hasPrevious => index > 0;

  /// Returns a copy with the given fields replaced.
  ///
  /// Null arguments keep the current value; [clearResumedFrom] and [clearError]
  /// force those fields back to `null` so a copy can drop them.
  PlaybackListState copyWith({
    int? index,
    int? count,
    PlaybackListItem? item,
    Duration? resumedFrom,
    bool? opening,
    Object? error,
    bool clearResumedFrom = false,
    bool clearError = false,
  }) {
    return PlaybackListState(
      index: index ?? this.index,
      count: count ?? this.count,
      item: item ?? this.item,
      resumedFrom: clearResumedFrom ? null : (resumedFrom ?? this.resumedFrom),
      opening: opening ?? this.opening,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [index, count, item, resumedFrom, opening, error];

  @override
  String toString() => 'PlaybackListState(${index + 1}/$count${item == null ? '' : ', ${item!.id}'})';
}

/// Plays an ordered list in one window.
///
/// Responsibilities:
///
/// - open an item, resume it where it was left, remember where it is left
/// - move to the next or previous item
/// - report which item is open and whether either direction is possible
///
/// It does not:
///
/// - render the list or its gestures (the host does)
/// - own the player (it drives a [PlaybackListPlayer])
/// - decide a list's contents
///
/// ## Why the position is saved on the way out
///
/// Progress is only useful if it is written before the current item stops being
/// current, and the moment of a switch is the last moment the old item's
/// position is still readable. [next], [previous] and [jumpTo] therefore save
/// before they open, and [savePosition] exists for the host to call when the
/// viewer leaves the list entirely (back button, app exit).
///
/// ## Why resume is bounded by a completion threshold
///
/// An item abandoned in its final seconds resumes from the start: the viewer
/// almost certainly finished it, and restoring the last five seconds reads as a
/// broken player rather than a feature.
final class PlaybackListController {
  /// Creates a controller over [items].
  ///
  /// It plays through either a dedicated [player] or a [pool] plus
  /// [poolPlayerFactory] (the assert enforces one of the two). Progress is kept
  /// in [store], defaulting to an in-memory store bounded by [config].
  PlaybackListController({
    PlaybackListPlayer? player,
    List<PlaybackListItem> items = const <PlaybackListItem>[],
    PlaybackProgressStore? store,
    this.config = PlaybackListConfig.defaults,
    this.pool,
    this.poolPlayerFactory,
  }) : assert(
         player != null || (pool != null && poolPlayerFactory != null),
         'A list needs either its own player or a pool plus a way to drive its handles',
       ),
       _player = player,
       _items = List<PlaybackListItem>.unmodifiable(items),
       _store = store ?? InMemoryPlaybackProgressStore(config: config) {
    _poolItemsSync = _syncPoolItems();
  }

  /// This instance's key in the shared account: a module can have several
  /// live instances, and a report sums their contributions rather than
  /// keeping whichever reported last.
  late final String _memoryKey = memoryContributorKey(this);

  /// Pool that warms neighbouring items, or `null` when the list drives a
  /// single player itself.
  ///
  /// With a pool the item a swipe reaches is already open, so the swipe is a
  /// source swap instead of a cold start — which is the entire reason a list
  /// stutters without one. See [PlaybackListConfig.recommendedPoolConfig].
  final PlaybackPoolOrchestrator? pool;

  /// Turns a pooled player handle into the player this list drives.
  ///
  /// Required with [pool]: the controller reads position and seeks through it,
  /// and a kernel host passes `KernelPlaybackListPlayer.new`.
  final PlaybackListPlayer Function(PoolPlayerHandle handle)? poolPlayerFactory;

  PlaybackListPlayer? _player;

  /// In-flight hand-off of the item list to the pool.
  ///
  /// The pool serializes its own operations, so a list set before an item is
  /// opened is applied first; the controller still awaits it so a caller can
  /// never observe a pool that does not know about the item it was asked to
  /// play.
  Future<void>? _poolItemsSync;

  /// The player the list is currently driving.
  PlaybackListPlayer get player {
    final current = _player;
    if (current == null) {
      throw StateError('PlaybackListController has no player bound yet.');
    }
    return current;
  }

  final PlaybackProgressStore _store;

  /// Tunables.
  final PlaybackListConfig config;

  List<PlaybackListItem> _items;
  int _index = 0;
  int? _lastOpenedIndex;
  PlaybackListState _state = const PlaybackListState();
  bool _disposed = false;

  /// The item the running open chain must land on, or null when nothing newer
  /// is waiting.
  int? _openTarget;

  /// Set while an open chain is running.
  ///
  /// A viewer who taps next three times, or drags across a dozen rows, must not
  /// pay a dozen opens: a request that arrives mid-flight retargets the chain
  /// instead of queueing behind it.
  Completer<void>? _openChain;

  final StreamController<PlaybackListState> _stateController = StreamController<PlaybackListState>.broadcast();

  /// Items in order.
  List<PlaybackListItem> get items => _items;

  /// Current snapshot.
  PlaybackListState get state => _state;

  /// Snapshot changes.
  Stream<PlaybackListState> get onStateChanged => _stateController.stream;

  /// Whether the controller has been disposed.
  bool get isDisposed => _disposed;

  /// Hands the current items to the pool, if there is one.
  Future<void> _syncPoolItems() async {
    final activePool = pool;
    if (activePool == null) {
      return;
    }
    await activePool.setItems(_items.map((item) => item.source).toList(growable: false));
  }

  /// Replaces the list contents, keeping the current item open when it is
  /// still present.
  ///
  /// A list that changes under the viewer (a room going offline, a channel
  /// list refreshed) must not silently switch what is playing, so the current
  /// item is kept by id when it survives the change and playback is left alone.
  void updateItems(List<PlaybackListItem> items) {
    _ensureNotDisposed();
    _items = List<PlaybackListItem>.unmodifiable(items);
    _poolItemsSync = _syncPoolItems();

    final currentId = _state.item?.id;
    if (currentId != null) {
      final index = _items.indexWhere((item) => item.id == currentId);
      if (index >= 0) {
        _index = index;
        _emit(_state.copyWith(index: index, count: _items.length));
        return;
      }
    }

    _emit(
      PlaybackListState(
        index: _index.clamp(0, _items.isEmpty ? 0 : _items.length - 1),
        count: _items.length,
        item: _items.isEmpty ? null : _items[_index.clamp(0, _items.length - 1)],
      ),
    );
  }

  /// Opens the item at [index], resuming it when progress was remembered.
  Future<void> open({int index = 0}) async {
    _ensureNotDisposed();
    if (_items.isEmpty) {
      _emit(const PlaybackListState());
      return;
    }
    if (index < 0 || index >= _items.length) {
      throw RangeError.index(index, _items, 'index');
    }

    _index = index;

    // A chain is already running: retarget it and wait on the same settling
    // rather than starting a second open of its own.
    final running = _openChain;
    if (running != null) {
      _openTarget = index;
      return await running.future;
    }

    _openTarget = index;
    final settled = Completer<void>();
    _openChain = settled;
    try {
      while (!_disposed) {
        final target = _openTarget;
        if (target == null) {
          break;
        }
        _openTarget = null;
        await _openAt(target);
      }
    } finally {
      _openChain = null;
      if (!settled.isCompleted) {
        settled.complete();
      }
    }
  }

  /// Brings [index] onto the player: the single place that opens, resumes and
  /// reports. [open] decides which index is worth opening at all.
  Future<void> _openAt(int index) async {
    if (_disposed) {
      return;
    }

    final item = _items[index];
    _log.debug(
      'opening a list item',
      fields: <String, Object?>{'index': index, 'count': _items.length, 'itemId': item.id, 'throughPool': pool != null},
    );
    _emit(
      _state.copyWith(
        index: index,
        count: _items.length,
        item: item,
        opening: true,
        clearError: true,
        clearResumedFrom: true,
      ),
    );

    final previousIndex = _lastOpenedIndex;
    try {
      // The viewer may have moved on while this call was queued behind the
      // pool hand-off: opening a row nobody is looking at costs a decode.
      if (_disposed || _index != index) {
        return;
      }
      await _openItem(item, index);
      if (previousIndex != null && previousIndex != index) {
        // The outgoing item is no longer visible; the pool keeps it warm or
        // releases it according to its own configuration.
        await pool?.onVisibilityChanged(previousIndex, 0);
      }
      _lastOpenedIndex = index;

      final resumedFrom = await _resume(item);
      if (_disposed || _index != index) {
        // A newer request owns the state now; clearing `opening` here would
        // flash the row the viewer just moved onto as if it had finished.
        return;
      }
      _emit(_state.copyWith(opening: false, resumedFrom: resumedFrom));
    } on Object catch (error) {
      _log.error(
        'could not open the list item',
        error: error,
        fields: <String, Object?>{'index': index, 'itemId': item.id},
      );
      if (_disposed || _index != index) {
        return;
      }
      _emit(_state.copyWith(opening: false, error: error));
    }
  }

  /// Moves to the next item. A no-op at the end of the list.
  Future<void> next() {
    _ensureNotDisposed();
    if (!_state.hasNext) {
      return Future<void>.value();
    }
    return _switchTo(_index + 1);
  }

  /// Moves to the previous item. A no-op at the start of the list.
  Future<void> previous() {
    _ensureNotDisposed();
    if (!_state.hasPrevious) {
      return Future<void>.value();
    }
    return _switchTo(_index - 1);
  }

  /// Moves to [index].
  Future<void> jumpTo(int index) {
    _ensureNotDisposed();
    if (index == _index) {
      return Future<void>.value();
    }
    return _switchTo(index);
  }

  /// Remembers the current position without changing items.
  ///
  /// Call when the viewer leaves the list, so returning later resumes here.
  Future<void> savePosition() async {
    _ensureNotDisposed();
    final item = _state.item;
    if (item == null || !config.resumeEnabled) {
      return;
    }
    await _store.save(item.id, player.position);
  }

  /// Forgets every remembered position.
  Future<void> clearProgress() {
    _ensureNotDisposed();
    return _store.clearAll();
  }

  /// Releases the controller.
  ///
  /// The player is not disposed: the list drives a player it does not own, and
  /// a host that shares one player between a list and a page must not lose it
  /// when the list is torn down.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await savePosition().catchError((Object _) {});
    _disposed = true;

    // Nobody will settle the chain now: release the callers awaiting it.
    _openTarget = null;
    final chain = _openChain;
    if (chain != null && !chain.isCompleted) {
      chain.complete();
    }

    _memory.withdraw(_memoryKey);
    await _stateController.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Opens [item] either through the pool or the list's own player.
  ///
  /// With a pool the controller does not open the source itself: the pool
  /// decides which of its players takes it, plays the active one and keeps the
  /// neighbours open, and the controller binds to whatever handle came out
  /// active so position and seek keep working.
  Future<void> _openItem(PlaybackListItem item, int index) async {
    final activePool = pool;
    if (activePool == null) {
      await player.open(item.source);
      return;
    }

    final handle = await _openThroughPool(item, index, activePool);
    _player = poolPlayerFactory!(handle);
  }

  Future<PoolPlayerHandle> _openThroughPool(
    PlaybackListItem item,
    int index,
    PlaybackPoolOrchestrator activePool,
  ) async {
    // The pool must know the item before it can be asked to play it.
    await _poolItemsSync;
    await activePool.onVisibilityChanged(index, 1);
    final handle = activePool.handleFor(index);
    if (handle == null) {
      _log.error(
        'the pool did not take the item',
        fields: <String, Object?>{'index': index, 'itemId': item.id, 'uri': item.source.uri},
      );
      throw StateError('The playback pool did not take item $index (${item.id}).');
    }
    return handle;
  }

  /// Saves the outgoing item, then opens the target.
  Future<void> _switchTo(int index) async {
    await savePosition();
    await open(index: index);
  }

  /// Seeks to the remembered position, returning it when it did.
  ///
  /// A remembered position inside the final [PlaybackListConfig.completionThreshold]
  /// is treated as "watched to the end": the entry is forgotten and playback
  /// starts over, because restoring the last few seconds reads as a broken
  /// player rather than as a feature.
  Future<Duration?> _resume(PlaybackListItem item) async {
    if (!config.resumeEnabled) {
      return null;
    }

    final saved = await _store.positionOf(item.id);
    if (saved == null || saved <= Duration.zero) {
      return null;
    }

    if (isNearCompletion(saved, player.duration)) {
      // Restoring the final seconds reads as a broken player, so the entry is
      // dropped and the item starts over.
      _log.debug(
        'remembered position counts as finished; starting from the beginning',
        fields: <String, Object?>{
          'itemId': item.id,
          'savedMs': saved.inMilliseconds,
          'durationMs': player.duration.inMilliseconds,
        },
      );
      await _store.clear(item.id);
      return null;
    }

    _log.debug(
      'resuming from the remembered position',
      fields: <String, Object?>{'itemId': item.id, 'positionMs': saved.inMilliseconds},
    );
    await player.seek(saved);
    return saved;
  }

  /// Whether [position] is close enough to the end of [duration] to count as
  /// finished. See [PlaybackListConfig.completionThreshold].
  ///
  /// An unknown duration (zero, which is what a live stream reports) never
  /// counts as finished: there is no end to be near.
  bool isNearCompletion(Duration position, Duration duration) {
    if (duration <= Duration.zero) {
      return false;
    }
    return duration - position <= config.completionThreshold;
  }

  /// Reports the retained items and remembered positions.
  void _reportMemory() {
    _memory.report(
      _memoryKey,
      items: _items.length,
      bytes: _items.length * MemoryEstimates.playbackItem,
      note: '${_items.length} item(s), position $_index',
    );
  }

  void _emit(PlaybackListState next) {
    _reportMemory();
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PlaybackListController has been disposed.');
    }
  }
}
