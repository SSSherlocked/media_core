import 'dart:async';

import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_danmaku/media_core_danmaku.dart';

DanmakuMessage chat(String text, {DanmakuStyle? style}) {
  return DanmakuMessage(type: DanmakuMessageType.chat, userName: 'viewer', text: text, style: style);
}

final class _RecordingSink implements DanmakuSink {
  final List<String> messages = <String>[];
  final List<String> notices = <String>[];
  int clearCount = 0;

  @override
  void onDanmaku(DanmakuMessage message, {bool immediate = false}) => messages.add(message.text);

  @override
  void onAudienceUpdate(DanmakuAudienceUpdate update) {}

  @override
  void onSuperChat(DanmakuSuperChat message) {}

  @override
  void onNotice(DanmakuNotice notice) => notices.add(notice.name);

  @override
  void onTransportNotice(String message) {}

  @override
  void onRoomChanged(String? roomId) {}

  @override
  void clearRendered() => clearCount++;
}

void main() {
  group('DanmakuOverlaySession queue', () {
    test('refuses messages until the surface is visible', () async {
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);

      expect(overlay.isActive, isFalse);
      expect(overlay.enqueue(chat('hello')), isFalse);
      expect(overlay.length, 0);

      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);

      expect(overlay.isActive, isTrue);
      expect(overlay.enqueue(chat('hello')), isTrue);
      expect(overlay.length, 1);
    });

    test('empties itself when the surface goes away', () async {
      final visibility = StreamController<bool>.broadcast();
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);
      addTearDown(visibility.close);
      overlay.bindVisibility(visibility.stream);

      visibility.add(true);
      await Future<void>.delayed(Duration.zero);
      overlay
        ..enqueue(chat('one'))
        ..enqueue(chat('two'));
      expect(overlay.length, 2);

      visibility.add(false);
      await Future<void>.delayed(Duration.zero);

      expect(overlay.length, 0, reason: 'a hidden window must not replay a backlog when it returns');
      expect(overlay.isActive, isFalse);
    });

    test('keeps the queue when clearOnHide is off', () async {
      final visibility = StreamController<bool>.broadcast();
      final overlay = DanmakuOverlaySession(clearOnHide: false);
      addTearDown(overlay.dispose);
      addTearDown(visibility.close);
      overlay.bindVisibility(visibility.stream);

      visibility.add(true);
      await Future<void>.delayed(Duration.zero);
      overlay.enqueue(chat('kept'));

      visibility.add(false);
      await Future<void>.delayed(Duration.zero);

      expect(overlay.length, 1);
      expect(overlay.isActive, isFalse, reason: 'still refusing new messages while hidden');
    });

    test('the queue bound is the engine own maxVisibleCount', () async {
      final overlay = DanmakuOverlaySession(config: const BarrageConfig(maxVisibleCount: 2));
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);

      overlay
        ..enqueue(chat('first'))
        ..enqueue(chat('second'))
        ..enqueue(chat('third'));

      expect(overlay.items.map((item) => item.message.text).toList(), <String>['second', 'third']);
    });

    test('a disabled overlay refuses and holds nothing', () async {
      final overlay = DanmakuOverlaySession(enabled: false);
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);

      expect(overlay.enqueue(chat('hello')), isFalse);
      expect(overlay.isActive, isFalse);
    });

    test('disabling an active overlay empties it', () async {
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);
      overlay
        ..enqueue(chat('hello'))
        ..setEnabled(enabled: false);

      expect(overlay.length, 0);
      expect(overlay.isEnabled, isFalse);
      expect(overlay.enqueue(chat('after')), isFalse);
    });

    test('shrinking the bound trims immediately', () async {
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);
      for (var index = 0; index < 5; index++) {
        overlay.enqueue(chat('message $index'));
      }

      overlay.updateConfig(const BarrageConfig(maxVisibleCount: 2));

      expect(overlay.length, 2);
    });

    test('empty text is refused', () async {
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);

      expect(overlay.enqueue(chat('   ')), isFalse);
    });
  });

  group('DanmakuOverlaySession lifecycle', () {
    test('reports active-state changes once per transition', () async {
      final visibility = StreamController<bool>.broadcast();
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);
      addTearDown(visibility.close);
      final reported = <bool>[];
      overlay.onActiveChanged.listen(reported.add);
      overlay.bindVisibility(visibility.stream);

      visibility
        ..add(true)
        ..add(true);
      await Future<void>.delayed(Duration.zero);
      visibility.add(false);
      await Future<void>.delayed(Duration.zero);

      expect(reported, <bool>[true, false]);
    });

    test('unbindVisibility hides the surface', () async {
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);
      overlay
        ..enqueue(chat('hello'))
        ..unbindVisibility();

      expect(overlay.isSurfaceVisible, isFalse);
      expect(overlay.length, 0);
    });

    test('rebinding replaces the previous subscription', () async {
      final first = StreamController<bool>.broadcast();
      final second = StreamController<bool>.broadcast();
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);
      addTearDown(first.close);
      addTearDown(second.close);

      overlay.bindVisibility(first.stream);
      first.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(overlay.isSurfaceVisible, isTrue);

      overlay.bindVisibility(second.stream);
      first.add(false);
      await Future<void>.delayed(Duration.zero);

      expect(overlay.isSurfaceVisible, isTrue, reason: 'the replaced stream must not move the surface state');
    });

    test('a disposed overlay refuses further calls', () async {
      final overlay = DanmakuOverlaySession();
      await overlay.dispose();

      expect(() => overlay.enqueue(chat('hello')), throwsA(isA<StateError>()));
    });
  });

  group('DanmakuOverlaySession presentation', () {
    test('the font size is the config one, and the message may override it', () async {
      final overlay = DanmakuOverlaySession(config: const BarrageConfig(fontSize: 14));
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);

      overlay
        ..enqueue(chat('plain'))
        ..enqueue(chat('styled', style: const DanmakuStyle(fontSize: 22, baseSpeed: 60, fontWeight: 400)));

      expect(overlay.items[0].fontSize, 14);
      expect(overlay.items[1].fontSize, 22);
    });

    test('a small surface is expressed as a smaller config, not a scale rule', () {
      // One vocabulary: the same knob the engine reads decides the size here,
      // so a host cannot end up with two surfaces drawing at sizes neither
      // config ever mentioned.
      final main = DanmakuOverlaySession(config: const BarrageConfig(fontSize: 24));
      final small = DanmakuOverlaySession(config: const BarrageConfig(fontSize: 12));
      addTearDown(main.dispose);
      addTearDown(small.dispose);

      expect(main.config.fontSize, 24);
      expect(small.config.fontSize, 12);
    });

    test('opacity combines the message own with the config one', () async {
      final overlay = DanmakuOverlaySession(config: const BarrageConfig(opacity: 0.5));
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);

      overlay.enqueue(chat('x', style: const DanmakuStyle(fontSize: 14, baseSpeed: 60, fontWeight: 400, opacity: 0.8)));

      expect(overlay.items.single.opacity, closeTo(0.4, 0.0001));
    });

    test('a fixed-placement message keeps its own duration', () async {
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);

      overlay.enqueue(
        chat(
          'pinned',
          style: const DanmakuStyle(
            fontSize: 14,
            baseSpeed: 60,
            fontWeight: 400,
            placement: DanmakuPlacement.top,
            fixedDurationMs: 8000,
          ),
        ),
      );

      expect(overlay.items.single.lifetime, const Duration(milliseconds: 8000));
    });

    test('a scrolling message lives as long as it takes to cross the surface', () async {
      final overlay = DanmakuOverlaySession(config: const BarrageConfig(baseSpeed: 100));
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);

      overlay.enqueue(chat('x'), surfaceWidth: 400);

      // 400 logical pixels at 100 px/s: the same relationship the engine uses,
      // rather than a magic dwell time divided by a multiplier.
      expect(overlay.items.single.lifetime, const Duration(seconds: 4));
      expect(overlay.items.single.speed, 100);
    });

    test('a slower base speed lengthens the lifetime', () async {
      final fast = DanmakuOverlaySession(config: const BarrageConfig(baseSpeed: 200));
      final slow = DanmakuOverlaySession(config: const BarrageConfig(baseSpeed: 50));
      addTearDown(fast.dispose);
      addTearDown(slow.dispose);
      fast.bindVisibility(Stream<bool>.value(true));
      slow.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);

      fast.enqueue(chat('x'), surfaceWidth: 400);
      slow.enqueue(chat('x'), surfaceWidth: 400);

      expect(slow.items.single.lifetime, greaterThan(fast.items.single.lifetime));
    });

    test('without a surface width the engine dwell time stands in', () async {
      final overlay = DanmakuOverlaySession(config: const BarrageConfig(fixedDuration: Duration(seconds: 7)));
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);

      overlay.enqueue(chat('x'));

      expect(overlay.items.single.lifetime, const Duration(seconds: 7));
    });

    test('evicts items whose lifetime has passed', () async {
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);
      final start = DateTime(2026, 9, 26, 12);
      overlay.enqueue(chat('one'), now: start);

      expect(overlay.evictExpired(now: start.add(const Duration(seconds: 1))), isEmpty);
      expect(overlay.length, 1);

      final expired = overlay.evictExpired(now: start.add(const Duration(minutes: 1)));

      expect(expired.single.message.text, 'one');
      expect(overlay.length, 0);
    });

    test('the display area follows the configured fraction', () {
      final overlay = DanmakuOverlaySession(config: const BarrageConfig(area: 0.5));
      addTearDown(overlay.dispose);

      expect(overlay.displayAreaFor(400), 200);
    });
  });

  group('DanmakuFanOutSink', () {
    test('feeds both surfaces with one accepted message', () async {
      final primary = _RecordingSink();
      final overlay = DanmakuOverlaySession(config: const BarrageConfig(fontSize: 12));
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);
      DanmakuFanOutSink(primary: primary, overlay: overlay, surfaceWidth: () => 320).onDanmaku(chat('hello'));

      expect(primary.messages, <String>['hello']);
      expect(overlay.items.single.message.text, 'hello');
      expect(overlay.items.single.fontSize, 12);
      expect(
        overlay.items.single.lifetime,
        isNot(const Duration(seconds: 4)),
        reason: 'the fan-out surface width decides how long it scrolls',
      );
    });

    test('forwards everything the overlay does not own', () {
      final primary = _RecordingSink();
      DanmakuFanOutSink(primary: primary)
        ..onNotice(DanmakuNotice.connected)
        ..onRoomChanged('room-1');

      expect(primary.notices, <String>['connected']);
    });

    test('clearing drops both surfaces', () async {
      final primary = _RecordingSink();
      final overlay = DanmakuOverlaySession();
      addTearDown(overlay.dispose);
      overlay.bindVisibility(Stream<bool>.value(true));
      await Future<void>.delayed(Duration.zero);
      DanmakuFanOutSink(primary: primary, overlay: overlay)
        ..onDanmaku(chat('hello'))
        ..clearRendered();

      expect(primary.clearCount, 1);
      expect(overlay.length, 0);
    });

    test('works without an overlay installed', () {
      final primary = _RecordingSink();
      DanmakuFanOutSink(primary: primary).onDanmaku(chat('hello'));

      expect(primary.messages, <String>['hello']);
    });
  });
}
