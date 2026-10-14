import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_feed/media_core_feed.dart';

final class _PoolHandle implements PoolPlayerHandle {
  _PoolHandle(this.id);

  @override
  final String id;

  String? openedSource;
  bool isPlaying = false;
  int openCount = 0;
  double volume = 1;

  /// Every source this handle was told to play, in order.
  ///
  /// A feed that attaches each page a fling passes through would list one
  /// entry per page; a coalescing feed lists only where the viewer stopped.
  final List<String> played = <String>[];

  /// Set by the host to make engine work wait, standing in for a slow open.
  Completer<void>? openGate;

  @override
  bool isDisposed = false;

  @override
  Future<void> open(PlayerSource source, {bool autoPlay = false}) async {
    final gate = openGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    openedSource = source.id.value;
    openCount++;
    isPlaying = autoPlay;
    if (autoPlay) played.add(source.id.value);
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    final source = openedSource;
    if (source != null && (played.isEmpty || played.last != source)) {
      played.add(source);
    }
  }

  @override
  Future<void> pause() async => isPlaying = false;

  @override
  Future<void> recycle() async {}

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> setMute({required bool muted}) async {}

  @override
  Stream<PlayerTransportState> get playbackStream => _transport.stream;

  final StreamController<PlayerTransportState> _transport = StreamController<PlayerTransportState>.broadcast();
}

final class _PoolHost implements PoolPlayerHost {
  final List<_PoolHandle> handles = <_PoolHandle>[];

  /// Handed to every handle created from now on: while it is set, opens wait.
  Completer<void>? gate;

  @override
  Future<PoolPlayerHandle> acquire() async {
    final handle = _PoolHandle('feed-pool${handles.length}')..openGate = gate;
    handles.add(handle);
    return handle;
  }

  @override
  Future<void> release(PoolPlayerHandle handle) async {}

  @override
  Future<void> disposeHandle(PoolPlayerHandle handle) async {}

  /// Sources the pool asked a player to play, across every handle it owns.
  List<String> get playedSources => handles.expand((handle) => handle.played).toList();
}

PlayerSource _source(String id) => PlayerSource(
  id: SourceId(id),
  uri: Uri.parse('https://example.com/$id.m3u8'),
  protocol: SourceProtocol.https,
  format: SourceFormat.mpegTs,
);

List<PlayerSource> _items(int count) => List<PlayerSource>.generate(count, (index) => _source('item$index'));

void main() {
  late _PoolHost host;
  late PlaybackPoolOrchestrator pool;
  late FeedPlayerController controller;

  setUp(() {
    host = _PoolHost();
    pool = PlaybackPoolOrchestrator(host: host, config: FeedConfig.recommendedPoolConfig);
    // A kernel with no backends: the pooled path never asks it for a player,
    // which is exactly what these tests are checking.
    controller = FeedPlayerController(PlayerKernel(), pool: pool);
  });

  tearDown(() async {
    await controller.dispose();
    await pool.dispose();
  });

  group('FeedPlayerController with a pool', () {
    test('the pool opens the visible item and warms the next one', () async {
      await controller.load(_items(4));

      expect(host.handles.first.openedSource, 'item0');
      expect(host.handles.first.isPlaying, isTrue);
      expect(host.handles.length, 2, reason: 'the next item is held open, not merely queued');
      expect(host.handles[1].openedSource, 'item1');
      expect(host.handles[1].isPlaying, isFalse);
      expect(controller.itemState, FeedItemState.playing);
    });

    test('a swipe takes the warm player instead of opening a cold one', () async {
      await controller.load(_items(4));
      final warmOpens = host.handles[1].openCount;

      await controller.next();

      expect(controller.currentIndex, 1);
      expect(host.handles[1].openCount, warmOpens, reason: 'the warm player is reused');
      expect(host.handles[1].isPlaying, isTrue);
    });

    test('swiping back also lands on a warm player', () async {
      await controller.load(_items(4), initialIndex: 2);
      final before = host.acquireCount2();

      await controller.previous();

      expect(controller.currentIndex, 1);
      expect(host.acquireCount2(), lessThanOrEqualTo(before + 1));
    });

    test('the feed exposes the pooled player for the visible item', () async {
      await controller.load(_items(4));

      expect(controller.pooledPlayer?.id, host.handles.first.id);
      expect(controller.handle, isNull, reason: 'this host does not pool kernel handles');
    });

    test('a fling across pages opens where the viewer stopped, not every page', () async {
      await controller.load(_items(10));
      final playedBefore = host.playedSources.length;

      // Every request arrives while the first attach is still suspended on
      // engine work - the shape of a flung PageView.
      final futures = <Future<void>>[for (var index = 1; index <= 6; index++) controller.showIndex(index)];
      await Future.wait(futures);

      expect(controller.currentIndex, 6);
      expect(
        controller.itemState,
        FeedItemState.playing,
        reason: 'the landed page is what reports its state, not the flown-over ones',
      );
      expect(host.playedSources.skip(playedBefore), <String>[
        'item6',
      ], reason: 'one play command for a six-page fling; the flown-over pages never touched an engine');
    });

    test('reloading at the same index attaches the new item behind it', () async {
      await controller.load(_items(4));
      expect(host.playedSources.last, 'item0');

      await controller.load(<PlayerSource>[_source('refreshed')]);

      expect(controller.currentIndex, 0);
      expect(host.playedSources.last, 'refreshed', reason: 'a refresh must re-open, not no-op on index 0');
    });

    test('volume reaches the pooled player', () async {
      await controller.load(_items(4));

      await controller.setVolume(0.3);

      expect(host.handles.first.volume, 0.3);
    });

    test('a page that subscribes before load() still receives transport state', () async {
      // The host subscribes the moment it builds the feed, which is earlier
      // than the first player existing. The old getter answered that with
      // `Stream.empty()`, so the subscription stayed empty for the life of the
      // page and the host's position/duration readouts never left zero.
      final seen = <PlayerTransportState>[];
      final subscription = controller.onPlaybackStateChanged.listen(seen.add);

      await controller.load(_items(2));
      host.handles.first._transport.add(const PlayerTransportState.initial());
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
      await subscription.cancel();
    });

    test('disposing the feed leaves the pool its players', () async {
      await controller.load(_items(4));
      final pooledHandle = controller.pooledPlayer;

      await controller.dispose();

      expect(pooledHandle!.isDisposed, isFalse, reason: 'the pool still owns that player');
    });

    test('an empty feed plans nothing', () async {
      await controller.load(const <PlayerSource>[]);

      expect(controller.currentIndex, -1);
      expect(host.handles, isEmpty);
    });
  });

  group('FeedConfig', () {
    test('recommends a bounded, reusing pool', () {
      expect(FeedConfig.recommendedPoolConfig.reuseIdlePlayers, isTrue);
      expect(FeedConfig.recommendedPoolConfig.maxActivePlayers, 1);
      expect(FeedConfig.recommendedPoolConfig.preloadCount, 1);
      expect(FeedConfig.recommendedPoolConfig.warmSize, 3);
    });
  });
}

extension on _PoolHost {
  int acquireCount2() => handles.length;
}
