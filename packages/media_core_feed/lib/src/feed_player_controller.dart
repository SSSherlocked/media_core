import 'dart:async';
import 'package:media_core/media_core.dart';
import 'package:media_core_feed/src/feed_config.dart' show FeedConfig;

/// Decision trail for the feed.
///
/// A feed is a stream of opens, most of which the viewer swipes past before they
/// finish. The lines here separate the open that produced what is on screen from
/// the ones that were abandoned mid-flight — without them, a stalled page and an
/// abandoned open look the same.
final LogModule _log = MediaCoreLog.of(LogCategory.playback);

/// Ledger of the feed's item list.
///
/// Metadata only: the media itself belongs to whichever player is playing it.
/// This is here so a report can distinguish "the feed is holding a long list"
/// from "a player is decoding".
final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.playback);

/// How a feed item is currently being played.
enum FeedItemState {
  /// The item is not attached to a player.
  idle,

  /// The item's source is opening.
  opening,

  /// The item's source is open and playing.
  playing,

  /// The item's source is open but paused (swiped away but kept warm,
  /// or paused by the user on the visible page).
  paused,

  /// Playing this item failed and nothing in the framework answered it.
  error,
}

/// Vertical feed (TikTok/Douyin-style) playback orchestration.
///
/// One [PlayerHandle] serves the whole feed. Swiping re-opens the same
/// handle on the next item's source, which reuses the attached engine and
/// avoids the adapter create/dispose churn a per-page player would cause.
///
/// ```text
/// load(items)
///   └▶ showIndex(i)   ──▶ handle.open(items[i]) ─▶ play ─▶ verify
/// showIndex(i + 1)    ──▶ same handle, next source
/// ```
///
/// Off-screen items are not kept warm by default: preloading a stream the
/// user may never stop on costs bandwidth on live feeds. `preload` records
/// the next item with the kernel's [PlayerKernel.preloadManager] so a
/// host that wants to warm it up can; pass `preloadAhead: false` to skip.
///
/// Errors on the visible item surface once on [onItemError]; the caller
/// decides whether to skip the item, show a retry button or remove it.
/// Recovery of a *playing* item (stalls, engine hiccups) is the live
/// module's job — attach a `LivePlaybackController`-style sweep on top if
/// the feed serves live streams.
final class FeedPlayerController {
  /// Creates a controller bound to [kernel].
  FeedPlayerController(this.kernel, {this.preloadAhead = true, this.pool});

  /// This instance's key in the shared account: a module can have several
  /// live instances, and a report sums their contributions rather than
  /// keeping whichever reported last.
  late final String _memoryKey = memoryContributorKey(this);

  /// The kernel providing the player and the preload bookkeeping.
  final PlayerKernel kernel;

  /// Whether the next item is queued for preload when an item becomes
  /// visible.
  ///
  /// Ignored when [pool] is installed: the pool decides what stays open, and
  /// it keeps neighbours genuinely warm (open, paused) rather than queuing an
  /// intent the host would have to act on.
  final bool preloadAhead;

  /// Pool that owns the players, or `null` to keep one shared handle.
  ///
  /// Without a pool this controller re-points a single handle at each item it
  /// shows: correct, but every swipe starts a cold open because nothing is
  /// warm. With a pool, the item a swipe reaches is already open and the swipe
  /// becomes a source swap — see [FeedConfig.recommendedPoolConfig] for the
  /// values a feed wants.
  final PlaybackPoolOrchestrator? pool;

  /// In-flight hand-off of the item list to the pool.
  Future<void>? _poolItemsSync;

  final List<PlayerSource> _items = <PlayerSource>[];

  PlayerHandle? _handle;
  PoolPlayerHandle? _pooledPlayer;

  int _index = -1;

  /// Index the attach chain last brought onto the player.
  ///
  /// The pool is told to stand the *previously attached* item down when a new
  /// one takes over; with coalescing that is not simply the index before the
  /// current request, because a fling never attached the pages it passed.
  int _attachedIndex = -1;

  /// The index the running attach chain must land on, or `null` when the chain
  /// has no newer request waiting.
  int? _attachTarget;

  /// Set while an attach chain is running; a superseded caller awaits it so a
  /// fast swipe sequence pays for one open, not one per page crossed.
  Completer<void>? _attachChain;

  bool _disposed = false;

  FeedItemState _itemState = FeedItemState.idle;

  final StreamController<int> _indexController = StreamController<int>.broadcast();
  final StreamController<FeedItemState> _stateController = StreamController<FeedItemState>.broadcast();
  final StreamController<PlayerFailure> _errorController = StreamController<PlayerFailure>.broadcast();
  final StreamController<PlayerTransportState> _transportController =
      StreamController<PlayerTransportState>.broadcast();

  // The subscription is cancelled on dispose and on every re-attach; the
  // analyzer cannot see that cancel through the local copies handed to it.
  // ignore: cancel_subscriptions
  StreamSubscription<PlayerTransportState>? _transportSubscription;

  /// The stream currently forwarded into [_transportController], for
  /// identity-only re-attachment.
  Object? _transportSource;

  /// All items of the feed.
  List<PlayerSource> get items => List<PlayerSource>.unmodifiable(_items);

  /// Index of the item currently attached to the player, `-1` before [load].
  int get currentIndex => _index;

  /// The item currently attached, if any.
  PlayerSource? get currentItem => _index >= 0 && _index < _items.length ? _items[_index] : null;

  /// State of the visible item.
  FeedItemState get itemState => _itemState;

  /// The attached kernel player, when one exists.
  ///
  /// Null while the feed is driven through a pool whose host is not the kernel
  /// — such a host pools its own players. See [pooledPlayer] for the handle
  /// that is always present in that case.
  PlayerHandle? get handle => _handle;

  /// The pooled player currently showing the visible item, when a pool is
  /// installed.
  PoolPlayerHandle? get pooledPlayer => _pooledPlayer;

  /// Emits the visible index on every [showIndex].
  Stream<int> get onIndexChanged => _indexController.stream;

  /// Emits the visible item's state.
  Stream<FeedItemState> get onItemStateChanged => _stateController.stream;

  /// Terminal failure of the visible item. One event per failed item.
  Stream<PlayerFailure> get onItemError => _errorController.stream;

  /// Loads the feed and attaches [initialIndex].
  ///
  /// Reloading re-attaches even when the visible index did not change: the
  /// item list is new, so the source behind that index may be a different
  /// video. The pool keeps matching players, so a refresh does not restart
  /// what is still the same item.
  Future<void> load(List<PlayerSource> items, {int initialIndex = 0}) {
    if (_disposed) {
      return Future<void>.value();
    }

    _items
      ..clear()
      ..addAll(items);
    _index = -1;

    _reportMemory();
    _log.debug(
      'feed loaded',
      fields: <String, Object?>{'items': items.length, 'initialIndex': initialIndex, 'throughPool': pool != null},
    );

    final activePool = pool;
    _poolItemsSync = activePool?.setItems(List<PlayerSource>.unmodifiable(_items));

    return showIndex(initialIndex.clamp(0, items.isEmpty ? 0 : items.length - 1));
  }

  /// Attaches item [index]: re-opens the shared handle on its source.
  ///
  /// Safe to call for every page the pager scrolls through — the item
  /// already visible is a no-op, and a page requested while an attach is still
  /// running **replaces** that attach instead of queueing behind it: a fling
  /// from 1 to 8 opens item 8, not eight items.
  Future<void> showIndex(int index) async {
    if (_disposed || index < 0 || index >= _items.length) {
      return;
    }
    if (index == _index && (_attachTarget == null || index == _attachTarget)) {
      return;
    }

    _index = index;
    _emitIndex(index);

    _log.debug(
      'feed page requested',
      fields: <String, Object?>{
        'to': index,
        'attached': _attachedIndex,
        'itemCount': _items.length,
        'throughPool': pool != null,
        'coalesced': _attachChain != null,
      },
    );

    // A chain is already running: hand it the new target and let that caller
    // await the same settling rather than starting a second attach.
    final running = _attachChain;
    if (running != null) {
      _attachTarget = index;
      return await running.future;
    }

    _attachTarget = index;
    final settled = Completer<void>();
    _attachChain = settled;
    try {
      while (!_disposed) {
        final target = _attachTarget;
        if (target == null) {
          break;
        }
        _attachTarget = null;
        await _attachTo(target);
      }
    } finally {
      _attachChain = null;
      if (!settled.isCompleted) settled.complete();
    }
  }

  /// Brings [index] onto the player.
  ///
  /// The single place that talks to the engine; [showIndex] decides which
  /// index is worth bringing at all.
  Future<void> _attachTo(int index) async {
    if (_disposed) {
      return;
    }

    final activePool = pool;
    if (activePool != null) {
      await _showIndexThroughPool(activePool, index);
      return;
    }

    if (_handle == null || _handle!.disposed) {
      _handle = await kernel.create();
    }
    if (_disposed || _index != index) {
      // The player was built while the viewer was still moving: the newest
      // request owns it now.
      return;
    }
    _reattachTransport();

    final handle = _handle!;
    final source = _items[index];

    _setItemState(FeedItemState.opening);

    try {
      await handle.open(source, autoPlay: true);

      if (_disposed || _index != index) {
        // The user kept swiping while this page was opening.
        _log.debug(
          'feed open finished after the viewer moved on',
          fields: <String, Object?>{'opened': index, 'current': _index},
        );
        return;
      }

      _attachedIndex = index;
      _setItemState(FeedItemState.playing);

      if (preloadAhead && index + 1 < _items.length) {
        kernel.preload(_items[index + 1]);
      }
    } on Object catch (error) {
      MediaCoreLog.error(
        LogCategory.recovery,
        'feed item failed: ${source.uri}',
        error: error,
        fields: <String, Object?>{'index': index},
      );

      if (_index == index && !_disposed) {
        _setItemState(FeedItemState.error);

        _errorController.add(
          PlayerFailure(
            code: PlayerErrorCode.noPlayableStream,
            message: 'Feed item $index failed to play: $error',
            cause: error,
          ),
        );
      }
    }
  }

  /// Shows [index] through the pool.
  ///
  /// The pool opens the source, plays the active item and keeps the neighbours
  /// open; this controller only takes the resulting handle so volume, playback
  /// state and its own bookkeeping keep working.
  Future<void> _showIndexThroughPool(PlaybackPoolOrchestrator activePool, int index) async {
    final source = _items[index];
    final previousIndex = _attachedIndex;
    _setItemState(FeedItemState.opening);

    try {
      await _poolItemsSync;
      // Checked again before any engine work: the requests that arrived while
      // this await was suspended already moved the target on, and opening a
      // page the viewer has flown past is exactly the cost coalescing exists
      // to avoid.
      if (_disposed || _index != index) {
        return;
      }
      await activePool.onVisibilityChanged(index, 1);
      if (previousIndex >= 0 && previousIndex != index) {
        await activePool.onVisibilityChanged(previousIndex, 0);
      }

      if (_disposed || _index != index) {
        // The user kept swiping while this page was opening.
        _log.debug(
          'pooled open finished after the viewer moved on',
          fields: <String, Object?>{'opened': index, 'current': _index},
        );
        return;
      }

      final pooled = activePool.handleFor(index);
      if (pooled == null) {
        throw StateError('The playback pool did not produce a player for feed item $index.');
      }

      _pooledPlayer = pooled;
      _handle = pooled is KernelPoolPlayerHandle ? pooled.handle : null;
      _reattachTransport();
      _attachedIndex = index;
      _setItemState(FeedItemState.playing);
    } on Object catch (error) {
      MediaCoreLog.error(
        LogCategory.recovery,
        'feed item failed: ${source.uri}',
        error: error,
        fields: <String, Object?>{'index': index, 'pooled': true},
      );

      if (_index == index && !_disposed) {
        _setItemState(FeedItemState.error);
        _errorController.add(
          PlayerFailure(
            code: PlayerErrorCode.noPlayableStream,
            message: 'Feed item $index failed to play: $error',
            cause: error,
          ),
        );
      }
    }
  }

  /// Swipes to the next item.
  Future<void> next() => showIndex(_index + 1);

  /// Swipes to the previous item.
  Future<void> previous() => showIndex(_index - 1);

  /// Pauses the visible item.
  Future<void> pause() async {
    _setItemState(FeedItemState.paused);

    await (_handle?.pause() ?? _pooledPlayer?.pause());
  }

  /// Resumes the visible item.
  Future<void> play() async {
    await (_handle?.play() ?? _pooledPlayer?.play());

    if (!_disposed) {
      _setItemState(FeedItemState.playing);
    }
  }

  /// Volume of the visible item's player.
  Future<void> setVolume(double volume) =>
      _handle?.setVolume(volume) ?? _pooledPlayer?.setVolume(volume) ?? Future<void>.value();

  /// Mutes the visible item's player.
  Future<void> setMute({required bool muted}) =>
      _handle?.setMute(muted: muted) ?? _pooledPlayer?.setMute(muted: muted) ?? Future<void>.value();

  /// Playback state stream of the visible item's player.
  ///
  /// A stable stream, not a snapshot of whichever handle happens to exist at
  /// the moment of the call. The old getter resolved
  /// `_handle?.playbackStream ?? _pooledPlayer?... ?? Stream.empty()` eagerly,
  /// so a page that subscribed as soon as it built the feed — before `load()`
  /// created the first player — was handed an empty stream for the life of the
  /// page, and its position/duration readouts never left zero. Re-attaching on
  /// every player change also survives an item switch, where each item gets a
  /// fresh handle.
  Stream<PlayerTransportState> get onPlaybackStateChanged => _transportController.stream;

  /// Releases the shared player and the feed.
  ///
  /// With a pool the players belong to the pool and are left alone: disposing a
  /// page must not tear down decoders another page is about to use.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _memory.withdraw(_memoryKey);

    // Nobody will settle the chain now; release the callers awaiting it.
    _attachTarget = null;
    final chain = _attachChain;
    if (chain != null && !chain.isCompleted) {
      chain.complete();
    }

    final handle = _handle;
    _handle = null;
    _pooledPlayer = null;

    final transport = _transportSubscription;
    _transportSubscription = null;
    _transportSource = null;
    if (transport != null) unawaited(transport.cancel());

    // With a pool the handle is the pool's to take back: releasing it here
    // would return a player that another page is about to be shown on.
    if (handle != null && pool == null) {
      try {
        await kernel.release(handle.id);
      } on Object catch (_) {
        // Best-effort release.
      }
    }

    await _indexController.close();
    await _stateController.close();
    await _errorController.close();
    await _transportController.close();
  }

  /// Reports the retained item list.
  void _reportMemory() {
    _memory.report(
      _memoryKey,
      items: _items.length,
      bytes: _items.length * MemoryEstimates.playbackItem,
      note: '${_items.length} feed item(s), at $_index',
    );
  }

  void _emitIndex(int index) {
    if (!_indexController.isClosed) {
      _indexController.add(index);
    }
  }

  /// Points the transport stream at the player that is now visible.
  ///
  /// Idempotent by stream identity, and a handle's `playbackStream` is a
  /// `ValueStream`, so one attachment also delivers the current value — that is
  /// what makes a duration appear without waiting for the next tick.
  void _reattachTransport() {
    if (_disposed) return;

    final stream = _handle?.playbackStream ?? _pooledPlayer?.playbackStream;
    if (identical(_transportSource, stream)) return;
    _transportSource = stream;

    final previous = _transportSubscription;
    _transportSubscription = null;
    if (previous != null) unawaited(previous.cancel());

    if (stream == null) return;

    _transportSubscription = stream.listen(
      (state) {
        if (!_transportController.isClosed) _transportController.add(state);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_transportController.isClosed) {
          _transportController.addError(error, stackTrace);
        }
      },
    );
  }

  void _setItemState(FeedItemState next) {
    if (_itemState == next) {
      return;
    }

    _itemState = next;

    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }
}
