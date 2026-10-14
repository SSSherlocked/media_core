import 'dart:ui' show Color, FontStyle, FontWeight;

import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_danmaku/media_core_danmaku.dart';

/// Captures what the sink hands the engine, without a Flame game.
final class _FakeEngine implements BarrageEngineApi {
  final pushed = <BarrageItem>[];
  int clearCalls = 0;

  @override
  void pushMessage(BarrageItem item) => pushed.add(item);

  @override
  void clear() => clearCalls++;

  @override
  void loadTimeline(List<BarrageItem> items) => timeline = items;

  @override
  void seekTo(Duration position) => seekPositions.add(position);

  List<BarrageItem>? timeline;
  final seekPositions = <Duration>[];

  @override
  double playbackRate = 1;

  @override
  int retractWhere(bool Function(BarrageItem item) predicate) => pushed.where(predicate).length;

  @override
  void updateConfig(BarrageConfig config) {}

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  bool triggerItemAt(double x, double y, {required bool longPress}) => false;

  @override
  BarrageItem? pauseItemAt(double x, double y) => null;

  @override
  void resumeAllPaused() {}

  @override
  int get pausedCount => 0;

  @override
  int get activeCacheSize => 0;

  @override
  int get activeCount => pushed.length;

  @override
  int get rasterCacheBytes => 0;

  @override
  int get activePoolSize => 0;

  @override
  int get pendingMessageCount => 0;

  @override
  bool get rasterizationActive => false;
}

final class _RecordingHost implements DanmakuSink {
  final audience = <DanmakuAudienceUpdate>[];
  final notices = <DanmakuNotice>[];
  final superChats = <DanmakuSuperChat>[];
  final rooms = <String?>[];

  @override
  void onDanmaku(DanmakuMessage message, {bool immediate = false}) {}

  @override
  void onAudienceUpdate(DanmakuAudienceUpdate update) => audience.add(update);

  @override
  void onSuperChat(DanmakuSuperChat message) => superChats.add(message);

  @override
  void onNotice(DanmakuNotice notice) => notices.add(notice);

  @override
  void onTransportNotice(String message) {}

  @override
  void onRoomChanged(String? roomId) => rooms.add(roomId);

  @override
  void clearRendered() {}
}

DanmakuMessage _chat({
  String text = 'hello',
  String messageId = '',
  String userId = '',
  DanmakuStyle? style,
  DanmakuColor color = DanmakuColor.white,
}) {
  return DanmakuMessage(
    type: DanmakuMessageType.chat,
    userName: 'viewer',
    text: text,
    messageId: messageId,
    userId: userId,
    color: color,
    style: style,
  );
}

void main() {
  group('BarrageItemMapper', () {
    test('a plain chat line carries text, id and color only', () {
      final item = BarrageItemMapper.toItem(_chat(text: '你好', messageId: 'm1', userId: 'u1'));

      expect(item.content, '你好');
      expect(item.type, BarrageType.scroll);
      expect(item.id, 'm1');
      expect(item.userId, 'u1');
      expect(item.textColor, const Color.fromARGB(255, 255, 255, 255));
      // Unsaid presentation falls back to the engine's config rather than
      // to a second set of defaults living in this package.
      expect(item.fontSize, isNull);
      expect(item.opacity, isNull);
      expect(item.fixedDuration, isNull);
    });

    test('empty identity fields become null, not empty strings', () {
      // An empty id would make every retraction match every message.
      final item = BarrageItemMapper.toItem(_chat());

      expect(item.id, isNull);
      expect(item.userId, isNull);
      expect(item.userName, 'viewer');
    });

    test('a style becomes per-item overrides on the engine item', () {
      final item = BarrageItemMapper.toItem(
        _chat(
          style: const DanmakuStyle(
            fontSize: 28,
            baseSpeed: 160,
            fontWeight: 700,
            italic: true,
            opacity: 0.5,
            letterSpacing: 1.5,
            showStroke: true,
            strokeWidth: 2,
            strokeColor: 0xFF00FF00,
            showShadow: true,
            shadowColor: 0xFF0000FF,
            shadowBlur: 4,
            shadowOffset: 3,
            placement: DanmakuPlacement.top,
            fixedDurationMs: 6000,
          ),
        ),
      );

      expect(item.type, BarrageType.topFixed);
      expect(item.fontSize, 28);
      expect(item.baseSpeed, 160);
      expect(item.fontWeight, FontWeight.w700);
      expect(item.fontStyle, FontStyle.italic);
      expect(item.opacity, 0.5);
      expect(item.letterSpacing, 1.5);
      expect(item.showStroke, isTrue);
      expect(item.strokeWidth, 2);
      expect(item.strokeColor, const Color(0xFF00FF00));
      expect(item.showShadow, isTrue);
      expect(item.shadowColor, const Color(0xFF0000FF));
      expect(item.shadowBlur, 4);
      expect(item.fixedDuration, const Duration(seconds: 6));
    });

    test('placements map onto the engine anchor types', () {
      expect(BarrageItemMapper.barrageTypeFor(DanmakuPlacement.scroll), BarrageType.scroll);
      expect(BarrageItemMapper.barrageTypeFor(DanmakuPlacement.top), BarrageType.topFixed);
      expect(BarrageItemMapper.barrageTypeFor(DanmakuPlacement.bottom), BarrageType.bottomFixed);
    });

    test('a timeline offset is passed through, and its absence is too', () {
      final timed = BarrageItemMapper.toItem(_chat(), at: const Duration(seconds: 90));

      expect(timed.at, const Duration(seconds: 90));
      // A live message has no offset, and inventing one would schedule it
      // against a timeline nobody loaded.
      expect(BarrageItemMapper.toItem(_chat()).at, isNull);
    });

    test('numeric weights round to the nearest FontWeight', () {
      expect(BarrageItemMapper.fontWeightFor(400), FontWeight.w400);
      expect(BarrageItemMapper.fontWeightFor(480), FontWeight.w500);
      expect(BarrageItemMapper.fontWeightFor(900), FontWeight.w900);
      // Out-of-range platform values clamp instead of throwing.
      expect(BarrageItemMapper.fontWeightFor(0), FontWeight.w100);
      expect(BarrageItemMapper.fontWeightFor(5000), FontWeight.w900);
    });
  });

  group('FlameBarrageSink', () {
    late _FakeEngine engine;
    late BarrageController controller;
    late _RecordingHost host;
    late FlameBarrageSink sink;

    setUp(() {
      engine = _FakeEngine();
      controller = BarrageController()..attach(engine);
      host = _RecordingHost();
      sink = FlameBarrageSink(controller, host: host);
    });

    test('an accepted message reaches the engine as one item', () {
      sink.onDanmaku(_chat(text: 'first', messageId: 'm1'));

      expect(engine.pushed, hasLength(1));
      expect(engine.pushed.single.content, 'first');
      expect(controller.totalEmitted, 1);
    });

    test('priority is supplied by the host, not invented here', () {
      FlameBarrageSink(controller, host: host, priorityOf: (message) => message.isLocal ? 10 : 0).onDanmaku(_chat());

      expect(engine.pushed.single.priority, 0);
    });

    test('clearRendered and a room change both wipe the screen', () {
      sink.clearRendered();
      expect(engine.clearCalls, 1);

      sink.onRoomChanged('room-2');
      expect(engine.clearCalls, 2);
      expect(host.rooms, ['room-2']);
    });

    test('retraction goes through the engine by provider id', () {
      sink.onDanmaku(_chat(messageId: 'm1'));

      expect(sink.retract('m1'), isTrue);
      expect(sink.retract('missing'), isFalse);
      expect(sink.retract('  '), isFalse);
    });

    test('a superchat is not rendered as barrage text', () {
      final card = DanmakuSuperChat(
        userName: 'whale',
        text: 'for the streamer',
        price: 100,
        startTime: DateTime(2026),
        endTime: DateTime(2026).add(const Duration(minutes: 1)),
        backgroundColor: '#FFEB3B',
        backgroundBottomColor: '#F57F17',
      );

      sink.onSuperChat(card);

      expect(engine.pushed, isEmpty);
      expect(host.superChats, [card]);
    });

    test('a card handler receives the superchat instead of the host', () {
      final seen = <DanmakuSuperChat>[];
      final withHandler = FlameBarrageSink(controller, host: host, onSuperChatCard: seen.add);
      final card = DanmakuSuperChat(
        userName: 'whale',
        text: 'hi',
        price: 1,
        startTime: DateTime(2026),
        endTime: DateTime(2026),
        backgroundColor: '#000000',
        backgroundBottomColor: '#111111',
      );

      withHandler.onSuperChat(card);

      expect(seen, [card]);
      expect(host.superChats, isEmpty);
    });

    test('audience and notice callbacks are forwarded, not swallowed', () {
      const update = DanmakuAudienceUpdate(kind: DanmakuAudienceKind.concurrentViewers, value: 42);

      sink
        ..onAudienceUpdate(update)
        ..onNotice(DanmakuNotice.connected);

      expect(host.audience, [update]);
      expect(host.notices, [DanmakuNotice.connected]);
    });

    test('a paused controller does not accept new messages', () {
      // The engine, not this sink, decides what a pause means; the sink must
      // not keep its own second opinion about it.
      controller.pause();
      sink.onDanmaku(_chat());

      expect(engine.pushed, isEmpty);
    });
  });

  group('the timeline surface a VOD host drives', () {
    test('load, seek and rate all reach the engine through the controller', () {
      final engine = _FakeEngine();
      final controller = BarrageController()
        ..attach(engine)
        ..loadTimeline([
          const BarrageItem(content: 'a', at: Duration(seconds: 1)),
          const BarrageItem(content: 'b', at: Duration(seconds: 2)),
        ]);
      expect(engine.timeline, hasLength(2));

      controller.seekTo(const Duration(seconds: 30));
      expect(engine.seekPositions, [const Duration(seconds: 30)]);

      controller.playbackRate = 2.0;
      expect(controller.playbackRate, 2.0);
    });

    test('dispose clears and detaches, so a stale sink cannot push', () {
      final engine = _FakeEngine();
      final controller = BarrageController()..attach(engine);
      final staleSink = FlameBarrageSink(controller);

      controller.dispose();
      staleSink.onDanmaku(_chat());

      expect(engine.clearCalls, 1);
      expect(engine.pushed, isEmpty);
      expect(controller.engine, isNull);
    });
  });
}
