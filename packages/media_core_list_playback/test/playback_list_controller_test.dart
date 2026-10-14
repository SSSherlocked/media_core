import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart'
    show
        PlaybackPoolOrchestrator,
        PlayerSource,
        PlayerTransportState,
        PoolPlayerHandle,
        PoolPlayerHost,
        SourceFormat,
        SourceId,
        SourceProtocol;
import 'package:media_core_list_playback/media_core_list_playback.dart';

final class _FakePlayer implements PlaybackListPlayer {
  final List<String> opened = <String>[];
  final List<Duration> seeks = <Duration>[];
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(minutes: 10);
  Object? openError;

  /// Set to hold every open until the test releases it: an engine that is
  /// still loading is the situation a burst of jumps has to survive.
  Completer<void>? openGate;

  @override
  Future<void> open(PlayerSource source) async {
    final gate = openGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    opened.add(source.id.value);
    final error = openError;
    // The test seam holds an arbitrary injected failure (a StateError in
    // practice) in an Object? field, so the static type cannot prove it is
    // throwable.
    // ignore: only_throw_errors
    if (error != null) throw error;
    position = Duration.zero;
  }

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    position = value;
  }
}

PlayerSource _source(String id) => PlayerSource(
  id: SourceId(id),
  uri: Uri.parse('https://example.com/$id.m3u8'),
  protocol: SourceProtocol.https,
  format: SourceFormat.mpegTs,
);

List<PlaybackListItem> _items(int count) => List<PlaybackListItem>.generate(
  count,
  (index) => PlaybackListItem(id: 'item$index', source: _source('item$index')),
);

void main() {
  _poolTests();

  late _FakePlayer player;

  setUp(() => player = _FakePlayer());

  PlaybackListController buildController({
    int count = 3,
    PlaybackProgressStore? store,
    PlaybackListConfig config = PlaybackListConfig.defaults,
  }) {
    return PlaybackListController(player: player, items: _items(count), store: store, config: config);
  }

  group('PlaybackListController navigation', () {
    test('opens the first item', () async {
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.open();

      expect(player.opened, <String>['item0']);
      expect(controller.state.index, 0);
      expect(controller.state.item?.id, 'item0');
      expect(controller.state.hasPrevious, isFalse);
      expect(controller.state.hasNext, isTrue);
    });

    test('next and previous move one item at a time', () async {
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.open();

      await controller.next();
      expect(controller.state.item?.id, 'item1');

      await controller.previous();
      expect(controller.state.item?.id, 'item0');
      expect(player.opened, <String>['item0', 'item1', 'item0']);
    });

    test('next is a no-op on the last item', () async {
      final controller = buildController(count: 1);
      addTearDown(controller.dispose);
      await controller.open();

      await controller.next();

      expect(player.opened.length, 1);
      expect(controller.state.hasNext, isFalse);
    });

    test('previous is a no-op on the first item', () async {
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.open();

      await controller.previous();

      expect(player.opened.length, 1);
    });

    test('an empty list reports an empty state instead of throwing', () async {
      final controller = buildController(count: 0);
      addTearDown(controller.dispose);

      await controller.open();

      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.item, isNull);
      expect(player.opened, isEmpty);
    });

    test('an out-of-range index is rejected', () async {
      final controller = buildController();
      addTearDown(controller.dispose);

      await expectLater(controller.open(index: 5), throwsA(isA<RangeError>()));
    });

    test('a failing open is reported without losing the index', () async {
      final controller = buildController();
      addTearDown(controller.dispose);
      player.openError = StateError('backend refused');

      await controller.open(index: 1);

      expect(controller.state.error, isA<StateError>());
      expect(controller.state.opening, isFalse);
      expect(controller.state.index, 1);
    });

    test('a burst of jumps does not open every row it crossed', () async {
      final controller = buildController(count: 8);
      addTearDown(controller.dispose);
      await controller.open();
      player.opened.clear();

      // The viewer taps next three times while the first row is still loading.
      player.openGate = Completer<void>();
      final requests = <Future<void>>[controller.jumpTo(1), controller.jumpTo(2), controller.jumpTo(3)];
      await Future<void>.delayed(Duration.zero);
      player.openGate!.complete();
      player.openGate = null;
      await Future.wait(requests);

      expect(controller.state.index, 3);
      expect(
        player.opened,
        isNot(contains('item2')),
        reason: 'row 2 was crossed while row 1 was still loading: it must never be opened',
      );
      expect(player.opened.last, 'item3');
    });

    test('a superseded open cannot report the newer row as settled', () async {
      final controller = buildController(count: 8);
      addTearDown(controller.dispose);
      await controller.open();

      final states = <PlaybackListState>[];
      final subscription = controller.onStateChanged.listen(states.add);
      addTearDown(subscription.cancel);

      player.openGate = Completer<void>();
      // Not awaited: awaiting row 1 here waits for the gate this test only opens
      // below, which is the request being superseded, not the thing under test.
      final first = controller.jumpTo(1);
      await Future<void>.delayed(Duration.zero);
      final later = controller.jumpTo(4);
      await Future<void>.delayed(Duration.zero);
      player.openGate!.complete();
      player.openGate = null;
      await Future.wait(<Future<void>>[first, later]);
      await Future<void>.delayed(Duration.zero);

      expect(
        states.where((state) => state.item?.id == 'item1' && !state.opening),
        isEmpty,
        reason: 'row 1 finished loading after the viewer had moved on; its "settled" state belongs to nobody',
      );
      expect(states.last.item?.id, 'item4');
      expect(states.last.opening, isFalse);
    });
  });

  group('PlaybackListController progress', () {
    test('saves the outgoing position before switching', () async {
      final store = InMemoryPlaybackProgressStore();
      final controller = buildController(store: store);
      addTearDown(controller.dispose);
      await controller.open();
      player.position = const Duration(minutes: 3);

      await controller.next();

      expect(await store.positionOf('item0'), const Duration(minutes: 3));
    });

    test('resumes an item at its remembered position', () async {
      final store = InMemoryPlaybackProgressStore();
      await store.save('item1', const Duration(minutes: 2));
      final controller = buildController(store: store);
      addTearDown(controller.dispose);

      await controller.open(index: 1);

      expect(player.seeks, <Duration>[const Duration(minutes: 2)]);
      expect(controller.state.resumedFrom, const Duration(minutes: 2));
    });

    test('going back to a previous video continues where it was left', () async {
      final store = InMemoryPlaybackProgressStore();
      final controller = buildController(store: store);
      addTearDown(controller.dispose);

      await controller.open();
      player.position = const Duration(minutes: 4);
      await controller.next();

      await controller.previous();

      expect(controller.state.item?.id, 'item0');
      expect(player.seeks, <Duration>[const Duration(minutes: 4)]);
      expect(controller.state.resumedFrom, const Duration(minutes: 4));
    });

    test('a position inside the completion threshold restarts the item', () async {
      final store = InMemoryPlaybackProgressStore();
      await store.save('item1', const Duration(minutes: 9, seconds: 50));
      final controller = buildController(store: store);
      addTearDown(controller.dispose);

      await controller.open(index: 1);

      expect(player.seeks, isEmpty, reason: 'watching the last ten seconds again is worse than starting over');
      expect(controller.state.resumedFrom, isNull);
      expect(await store.positionOf('item1'), isNull, reason: 'the finished entry is forgotten');
    });

    test('an unknown duration never counts as finished', () async {
      final store = InMemoryPlaybackProgressStore();
      await store.save('item1', const Duration(hours: 2));
      player.duration = Duration.zero;
      final controller = buildController(store: store);
      addTearDown(controller.dispose);

      await controller.open(index: 1);

      expect(player.seeks, <Duration>[const Duration(hours: 2)]);
    });

    test('resume can be turned off entirely', () async {
      final store = InMemoryPlaybackProgressStore();
      await store.save('item1', const Duration(minutes: 2));
      final controller = buildController(
        store: store,
        config: PlaybackListConfig.defaults.copyWith(resumeEnabled: false),
      );
      addTearDown(controller.dispose);

      await controller.open(index: 1);

      expect(player.seeks, isEmpty);
    });

    test('savePosition remembers the current item on demand', () async {
      final store = InMemoryPlaybackProgressStore();
      final controller = buildController(store: store);
      addTearDown(controller.dispose);
      await controller.open();
      player.position = const Duration(seconds: 42);

      await controller.savePosition();

      expect(await store.positionOf('item0'), const Duration(seconds: 42));
    });

    test('clearProgress forgets every item', () async {
      final store = InMemoryPlaybackProgressStore();
      final controller = buildController(store: store);
      addTearDown(controller.dispose);
      await controller.open();
      player.position = const Duration(minutes: 1);
      await controller.savePosition();

      await controller.clearProgress();

      expect(await store.positionOf('item0'), isNull);
    });

    test('dispose remembers where the viewer left off', () async {
      final store = InMemoryPlaybackProgressStore();
      final controller = buildController(store: store);
      await controller.open();
      player.position = const Duration(minutes: 5);

      await controller.dispose();

      expect(await store.positionOf('item0'), const Duration(minutes: 5));
    });
  });

  group('InMemoryPlaybackProgressStore', () {
    test('evicts the least recently touched item beyond the bound', () async {
      final store = InMemoryPlaybackProgressStore(config: PlaybackListConfig.defaults.copyWith(maxRememberedItems: 2));

      await store.save('a', const Duration(seconds: 1));
      await store.save('b', const Duration(seconds: 2));
      // Touching 'a' keeps it alive while 'b' becomes the oldest.
      await store.positionOf('a');
      await store.save('c', const Duration(seconds: 3));

      expect(await store.positionOf('a'), const Duration(seconds: 1));
      expect(await store.positionOf('b'), isNull);
      expect(await store.positionOf('c'), const Duration(seconds: 3));
    });

    test('reading an unknown item is not an error', () async {
      final store = InMemoryPlaybackProgressStore();

      expect(await store.positionOf('missing'), isNull);
    });
  });

  group('PlaybackListController item updates', () {
    test('keeps the current item open when it survives an update', () async {
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.open(index: 1);

      controller.updateItems(<PlaybackListItem>[PlaybackListItem(id: 'extra', source: _source('extra')), ..._items(3)]);

      expect(controller.state.item?.id, 'item1');
      expect(controller.state.index, 2);
      expect(player.opened.length, 1, reason: 'refresh must not restart playback');
    });

    test('reports an empty state when the current item disappears', () async {
      final controller = buildController(count: 1);
      addTearDown(controller.dispose);
      await controller.open();

      controller.updateItems(<PlaybackListItem>[]);

      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.item, isNull);
    });
  });
}

// --- Pool integration -------------------------------------------------------
//
// A list with a pool does not open its own sources: the pool decides which
// player takes the item, plays the active one and keeps the neighbours warm.
// These tests assert the hand-off, the neighbour warmth and the resume
// bookkeeping that must survive it.

final class _PoolHandle implements PoolPlayerHandle {
  _PoolHandle(this.id);

  @override
  final String id;

  String? openedSource;
  bool isPlaying = false;
  Duration duration = const Duration(minutes: 10);
  int openCount = 0;

  @override
  bool isDisposed = false;

  @override
  Future<void> open(PlayerSource source, {bool autoPlay = false}) async {
    openedSource = source.id.value;
    openCount++;
    isPlaying = autoPlay;
  }

  @override
  Future<void> play() async => isPlaying = true;

  @override
  Future<void> pause() async => isPlaying = false;

  @override
  Future<void> recycle() async {}

  @override
  Future<void> setVolume(double value) async {}

  @override
  Future<void> setMute({required bool muted}) async {}

  @override
  Stream<PlayerTransportState> get playbackStream => const Stream<PlayerTransportState>.empty();
}

final class _PoolHost implements PoolPlayerHost {
  final List<_PoolHandle> handles = <_PoolHandle>[];

  @override
  Future<PoolPlayerHandle> acquire() async {
    final handle = _PoolHandle('pool${handles.length}');
    handles.add(handle);
    return handle;
  }

  @override
  Future<void> release(PoolPlayerHandle handle) async {}

  @override
  Future<void> disposeHandle(PoolPlayerHandle handle) async {}
}

/// PlayerIdentity bound to a pooled handle, recording what the list does through it.
final class _PooledListPlayer implements PlaybackListPlayer {
  _PooledListPlayer(this.handle);

  final PoolPlayerHandle handle;
  final List<Duration> seeks = <Duration>[];
  Duration _position = Duration.zero;

  @override
  Future<void> open(PlayerSource source) => handle.open(source, autoPlay: true);

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    _position = position;
  }

  @override
  Duration get position => _position;

  @override
  Duration get duration => const Duration(minutes: 10);
}

void _poolTests() {
  group('PlaybackListController with a pool', () {
    late _PoolHost host;
    late PlaybackPoolOrchestrator pool;
    late PlaybackListController controller;

    setUp(() {
      host = _PoolHost();
      pool = PlaybackPoolOrchestrator(host: host, config: PlaybackListConfig.recommendedPoolConfig);
    });

    tearDown(() async {
      await controller.dispose();
      await pool.dispose();
    });

    PlaybackListController build() {
      return controller = PlaybackListController(
        items: _items(4),
        pool: pool,
        poolPlayerFactory: _PooledListPlayer.new,
      );
    }

    test('the pool opens the active item and warms its neighbours', () async {
      build();

      await controller.open();

      expect(host.handles.first.openedSource, 'item0');
      expect(host.handles.first.isPlaying, isTrue);
      expect(host.handles.length, 2, reason: 'item 1 is warmed by the pool');
      expect(host.handles[1].openedSource, 'item1');
      expect(host.handles[1].isPlaying, isFalse);
    });

    test('a swipe reaches an item the pool already opened', () async {
      build();
      await controller.open();
      final warmOpens = host.handles[1].openCount;

      await controller.next();

      expect(controller.state.item?.id, 'item1');
      expect(host.handles[1].openCount, warmOpens, reason: 'the warm player is taken, not re-opened');
    });

    test('the controller drives whichever handle the pool made active', () async {
      build();
      await controller.open();
      final first = controller.player;

      await controller.next();

      expect(controller.player, isNot(same(first)));
      expect(((controller.player as _PooledListPlayer).handle as _PoolHandle).openedSource, 'item1');
    });

    test('resume still works through the pooled player', () async {
      final store = InMemoryPlaybackProgressStore();
      await store.save('item1', const Duration(minutes: 2));
      controller = PlaybackListController(
        items: _items(4),
        store: store,
        pool: pool,
        poolPlayerFactory: _PooledListPlayer.new,
      );

      await controller.open(index: 1);

      final player = controller.player as _PooledListPlayer;
      expect(player.seeks, <Duration>[const Duration(minutes: 2)]);
      expect(controller.state.resumedFrom, const Duration(minutes: 2));
    });

    test('a refresh hands the new list to the pool', () async {
      build();
      await controller.open();

      controller.updateItems(_items(2));

      expect(pool.sources.length, 2);
    });

    test('needs a factory to drive pooled handles', () {
      expect(() => PlaybackListController(items: _items(1), pool: pool), throwsA(isA<AssertionError>()));
    });
  });
}
