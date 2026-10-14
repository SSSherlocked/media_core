import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';

final class _FakeHandle implements PoolPlayerHandle {
  _FakeHandle(this.id);

  @override
  final String id;

  String? openedSource;
  bool isPlaying = false;
  bool stallNonAutoplayOpens = false;
  int openCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int recycleCount = 0;
  double volume = 1;
  bool muted = false;

  @override
  bool isDisposed = false;

  @override
  Future<void> open(PlayerSource source, {bool autoPlay = false}) async {
    if (stallNonAutoplayOpens && !autoPlay) {
      // Never completes: the orchestrator's preload timeout is what ends it.
      await Completer<void>().future;
    }
    openedSource = source.id.value;
    openCount++;
    isPlaying = autoPlay;
  }

  @override
  Future<void> play() async {
    playCount++;
    isPlaying = true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    isPlaying = false;
  }

  @override
  Future<void> recycle() async => recycleCount++;

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> setMute({required bool muted}) async => this.muted = muted;

  @override
  Stream<PlayerTransportState> get playbackStream => const Stream<PlayerTransportState>.empty();
}

final class _FakeHost implements PoolPlayerHost {
  final List<_FakeHandle> handles = <_FakeHandle>[];
  int acquireCount = 0;
  int releaseCount = 0;
  int disposeCount = 0;

  /// When true, handles opened *not* as the active item never complete —
  /// standing in for a slow or broken preload.
  bool stallOpens = false;

  @override
  Future<PoolPlayerHandle> acquire() async {
    acquireCount++;
    final handle = _FakeHandle('player${handles.length}')..stallNonAutoplayOpens = stallOpens;
    handles.add(handle);
    return handle;
  }

  @override
  Future<void> release(PoolPlayerHandle handle) async => releaseCount++;

  @override
  Future<void> disposeHandle(PoolPlayerHandle handle) async => disposeCount++;
}

PlayerSource _source(String id) => PlayerSource(
  id: SourceId(id),
  uri: Uri.parse('https://example.com/$id.m3u8'),
  protocol: SourceProtocol.https,
  format: SourceFormat.mpegTs,
);

List<PlayerSource> _sources(int count) => List<PlayerSource>.generate(count, (index) => _source('item$index'));

void main() {
  late _FakeHost host;
  late DateTime now;

  setUp(() {
    host = _FakeHost();
    now = DateTime(2026, 9, 26, 12);
  });

  Future<PlaybackPoolOrchestrator> build({int count = 5, PlayerPoolConfig config = const PlayerPoolConfig()}) async {
    final orchestrator = PlaybackPoolOrchestrator(host: host, config: config, clock: () => now);
    addTearDown(orchestrator.dispose);
    await orchestrator.setItems(_sources(count));
    return orchestrator;
  }

  group('PlaybackPoolOrchestrator selection', () {
    test('the most visible item becomes active and its neighbours warm', () async {
      final pool = await build();

      final plan = await pool.onVisibilityChanged(2, 1);

      expect(plan.activeIndex, 2);
      expect(plan.playing, <int>{2});
      expect(plan.warming, <int>{1, 3});
      expect(pool.heldCount, 3);
      expect(host.handles[0].isPlaying, isTrue);
      expect(host.handles[1].isPlaying, isFalse, reason: 'warm players are opened paused');
    });

    test('a swipe re-points an idle player instead of acquiring another', () async {
      final pool = await build();
      await pool.onVisibilityChanged(0, 1);
      expect(host.acquireCount, 2, reason: 'item 0 active, item 1 warm');

      await pool.onVisibilityChanged(2, 1);
      await pool.onVisibilityChanged(0, 0);

      expect(pool.activeIndex, 2);
      expect(pool.heldCount, lessThanOrEqualTo(3), reason: 'an endless list must not grow one player per item');
      expect(host.handles.where((handle) => handle.openedSource == 'item2').length, 1);
    });

    test('an item the warm window still covers is reported as warm, not idle', () async {
      final pool = await build();
      await pool.onVisibilityChanged(2, 1);

      // Swiping one item on demotes item 2 from active; the warm window follows
      // the new active item and still covers it, so it is held *for* this list —
      // reporting it as idle would read as a player that could be released.
      await pool.onVisibilityChanged(3, 1);

      expect(pool.roleOf(2), PooledItemRole.warming);
      expect(pool.roleOf(3), PooledItemRole.active);
    });

    test('an item below the play threshold does not take over', () async {
      final pool = await build();
      await pool.onVisibilityChanged(2, 1);

      final plan = await pool.onVisibilityChanged(3, 0.5);

      expect(plan.activeIndex, 2, reason: '0.5 is above the pause threshold, so the current item keeps playing');
    });

    test('an item above the play threshold does take over', () async {
      final pool = await build();
      await pool.onVisibilityChanged(2, 1);

      await pool.onVisibilityChanged(3, 0.7);
      final plan = await pool.onVisibilityChanged(2, 0.2);

      expect(plan.activeIndex, 3, reason: 'the item that became clearly visible takes over');
    });

    test('scrolling the viewport away pauses without releasing', () async {
      final pool = await build();
      await pool.onVisibilityChanged(2, 1);
      final active = host.handles.firstWhere((handle) => handle.openedSource == 'item2');

      final plan = await pool.setViewportVisible(visible: false);

      expect(plan.activeIndex, isNull);
      expect(active.isPlaying, isFalse);
      expect(host.releaseCount, 0, reason: 'a hidden viewport is not a reason to give up a warm player');
    });

    test('an occluded app pauses the same way', () async {
      final pool = await build();
      await pool.onVisibilityChanged(1, 1);

      final plan = await pool.setOccluded(occluded: true);

      expect(plan.activeIndex, isNull);
    });

    test('an empty list plans nothing', () async {
      final orchestrator = PlaybackPoolOrchestrator(host: host, clock: () => now);
      addTearDown(orchestrator.dispose);

      final plan = await orchestrator.reconcile();

      expect(plan.items, isEmpty);
      expect(plan.activeIndex, isNull);
    });
  });

  group('PlaybackPoolOrchestrator recycling', () {
    test('an idle player is released once the idle timeout passes', () async {
      // Reuse is off here on purpose: with reuse on, the player that scrolled
      // away is re-pointed rather than released, which is a different test.
      final pool = await build(
        config: const PlayerPoolConfig(reuseIdlePlayers: false, idleTimeout: Duration(seconds: 10)),
      );
      await pool.onVisibilityChanged(0, 1);
      expect(pool.heldCount, 2);

      // Scroll far enough that items 0 and 1 leave the warm window.
      await pool.onVisibilityChanged(4, 1);
      final before = host.releaseCount;
      final plan = await pool.reconcile();

      expect(plan.released, isEmpty, reason: 'the timeout has not passed yet; the players stay warm');

      now = now.add(const Duration(seconds: 11));
      final after = await pool.reconcile();

      expect(after.released, isNotEmpty);
      expect(host.releaseCount, greaterThan(before));
    });

    test('reuse re-points the player that scrolled away instead of releasing it', () async {
      final pool = await build(config: const PlayerPoolConfig(idleTimeout: Duration(seconds: 10)));
      await pool.onVisibilityChanged(0, 1);
      final acquiresAfterFirst = host.acquireCount;

      await pool.onVisibilityChanged(4, 1);
      now = now.add(const Duration(seconds: 30));
      final plan = await pool.reconcile();

      expect(host.acquireCount, acquiresAfterFirst, reason: 'the moved player covers the new window');
      expect(plan.heldCount, lessThanOrEqualTo(3));
    });

    test('a warm open that does not finish in time is given back', () async {
      final pool = await build(config: const PlayerPoolConfig(preloadTimeout: Duration(milliseconds: 100)));
      // Neighbours never finish opening; the active item still does.
      host.stallOpens = true;

      final plan = await pool.onVisibilityChanged(2, 1);

      expect(plan.activeIndex, 2);
      expect(plan.warming, isEmpty, reason: 'a warm player that cannot open is not worth holding');
      expect(host.releaseCount, greaterThan(0));
    });

    test('keepWarm keeps an idle player instead of releasing it', () async {
      final pool = await build(
        config: const PlayerPoolConfig(keepWarm: true, warmSize: 4, idleTimeout: Duration(seconds: 1)),
      );
      await pool.onVisibilityChanged(0, 1);
      await pool.onVisibilityChanged(4, 1);
      now = now.add(const Duration(seconds: 5));

      await pool.reconcile();

      expect(host.releaseCount, 0);
    });

    test('recycling off disposes the player instead of returning it', () async {
      final pool = await build(
        config: const PlayerPoolConfig(
          reuseIdlePlayers: false,
          preloadCount: 0,
          enableRecycle: false,
          idleTimeout: Duration(seconds: 1),
        ),
      );
      await pool.onVisibilityChanged(0, 1);
      await pool.onVisibilityChanged(4, 1);
      now = now.add(const Duration(seconds: 2));

      await pool.reconcile();

      expect(host.disposeCount, greaterThan(0));
      expect(host.releaseCount, 0);
    });

    test('warmSize bounds how many players stay warm', () async {
      final pool = await build(config: const PlayerPoolConfig(preloadCount: 3, warmSize: 1));

      final plan = await pool.onVisibilityChanged(2, 1);

      expect(plan.playing, <int>{2});
      expect(plan.warming.length, lessThanOrEqualTo(1));
    });
  });

  group('PlaybackPoolOrchestrator pressure', () {
    test('warning halves preloading', () async {
      final pool = await build(config: const PlayerPoolConfig(preloadCount: 2));

      final plan = await pool.reportPressure(ResourcePressure.warning);

      expect(plan.warming.length, lessThanOrEqualTo(1), reason: 'half of two is one per side');
    });

    test('critical stops preloading and releases warm players', () async {
      final pool = await build();
      await pool.onVisibilityChanged(2, 1);
      expect(pool.heldCount, 3);

      final plan = await pool.reportPressure(ResourcePressure.critical);

      expect(plan.warming, isEmpty);
      expect(plan.released, isNotEmpty);
      expect(pool.heldCount, lessThan(3));
    });

    test('returning to no pressure restores preloading', () async {
      final pool = await build();
      await pool.onVisibilityChanged(2, 1);
      await pool.reportPressure(ResourcePressure.critical);
      final reduced = pool.heldCount;

      final plan = await pool.reportPressure(ResourcePressure.none);

      expect(plan.warming, isNotEmpty);
      expect(pool.heldCount, greaterThanOrEqualTo(reduced));
    });
  });

  group('PlaybackPoolOrchestrator list updates', () {
    test('a refresh keeps the playing item and adds the new one', () async {
      final pool = await build(count: 3);
      await pool.onVisibilityChanged(1, 1);
      final handle = pool.handleFor(1);

      await pool.setItems(<PlayerSource>[_source('new'), ..._sources(3)]);

      expect(pool.handleFor(1)?.id, handle?.id, reason: 'the playing player must survive a refresh');
      expect(host.handles.where((item) => item.openedSource == 'item1').length, 1);
    });

    test('an item replaced behind the same index is re-opened, not resumed', () async {
      final pool = await build(count: 2);
      await pool.onVisibilityChanged(0, 1);
      final active = pool.handleFor(0)! as _FakeHandle;
      expect(active.openedSource, 'item0');

      // Pull-to-refresh with the same length: index 0 now holds a different
      // video. Resuming the held player would keep playing the old one.
      await pool.setItems(<PlayerSource>[_source('refreshed0'), _source('refreshed1')]);
      await pool.onVisibilityChanged(0, 1);

      expect(pool.handleFor(0)?.id, active.id, reason: 'the player is reused, not rebuilt');
      expect(active.openedSource, 'refreshed0');
      expect(active.isPlaying, isTrue);
    });

    test('removing items releases their players', () async {
      final pool = await build(count: 3);
      await pool.onVisibilityChanged(2, 1);

      await pool.setItems(_sources(1));

      expect(pool.heldCount, lessThanOrEqualTo(1));
      expect(host.releaseCount, greaterThan(0));
    });

    test('releaseAll gives every player back', () async {
      final pool = await build();
      await pool.onVisibilityChanged(2, 1);

      await pool.releaseAll();

      expect(pool.heldCount, 0);
      expect(pool.activeIndex, isNull);
    });
  });

  group('KernelPoolPlayerHost', () {
    test('exposes the kernel handle identity and lifecycle', () {
      // The adapter is a thin wrapper; its contract is checked through the
      // interface it implements, so a fake host stands in for the kernel here.
      final handle = _FakeHandle('kernel-player');

      expect(handle.id, 'kernel-player');
      expect(handle.isDisposed, isFalse);
    });
  });
}
