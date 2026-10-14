import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_danmaku/media_core_danmaku.dart';

DanmakuMessage chat({String text = 'hello', String id = '', String user = 'viewer', DateTime? sentAt}) {
  return DanmakuMessage(type: DanmakuMessageType.chat, userName: user, text: text, messageId: id, sentAt: sentAt);
}

void main() {
  group('DanmakuMessageGate', () {
    test('rejects a replayed packet carrying the same platform id', () {
      final gate = DanmakuMessageGate();
      final now = DateTime(2026, 9, 26, 12);

      expect(gate.accepts(chat(id: 'm1'), now: now), isTrue);
      expect(gate.accepts(chat(id: 'm1'), now: now.add(const Duration(seconds: 30))), isFalse);
    });

    test('accepts the same id once its window has passed', () {
      final gate = DanmakuMessageGate();
      final now = DateTime(2026, 9, 26, 12);

      expect(gate.accepts(chat(id: 'm1'), now: now), isTrue);
      expect(gate.accepts(chat(id: 'm1'), now: now.add(const Duration(minutes: 11))), isTrue);
    });

    test('measures the window from the first arrival, not from the last repeat', () {
      final gate = DanmakuMessageGate();
      final now = DateTime(2026, 9, 26, 12);

      expect(gate.accepts(chat(id: 'm1'), now: now), isTrue);
      expect(gate.accepts(chat(id: 'm1'), now: now.add(const Duration(minutes: 9))), isFalse);
      // A rejected repeat does not extend the window: a socket that flaps for
      // an hour cannot keep one id suppressed for an hour.
      expect(gate.accepts(chat(id: 'm1'), now: now.add(const Duration(minutes: 10, seconds: 1))), isTrue);
    });

    test('keeps genuine repetition from different viewers when no id is available', () {
      final gate = DanmakuMessageGate();
      final now = DateTime(2026, 9, 26, 12);

      expect(
        gate.accepts(
          chat(text: '666', user: 'alice'),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          chat(text: '666', user: 'bob'),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          chat(text: '666', user: 'alice'),
          now: now,
        ),
        isFalse,
      );
    });

    test('falls back to a short text window for platforms without ids', () {
      final gate = DanmakuMessageGate();
      final now = DateTime(2026, 9, 26, 12);

      expect(gate.accepts(chat(text: '666'), now: now), isTrue);
      expect(gate.accepts(chat(text: '666'), now: now.add(const Duration(seconds: 2))), isFalse);
      expect(gate.accepts(chat(text: '666'), now: now.add(const Duration(seconds: 4))), isTrue);
    });

    test('drops platform backlog older than the accepted age', () {
      final gate = DanmakuMessageGate();
      final now = DateTime(2026, 9, 26, 12);

      expect(gate.accepts(chat(sentAt: now.subtract(const Duration(seconds: 46))), now: now), isFalse);
      expect(
        gate.accepts(
          chat(text: 'fresh', sentAt: now.subtract(const Duration(seconds: 5))),
          now: now,
        ),
        isTrue,
      );
    });

    test('drops a malformed future timestamp instead of caching it', () {
      final gate = DanmakuMessageGate();
      final now = DateTime(2026, 9, 26, 12);

      expect(
        gate.accepts(
          chat(text: 'skewed', sentAt: now.add(const Duration(minutes: 20))),
          now: now,
        ),
        isFalse,
      );
      // Ordinary clock skew is still accepted.
      expect(
        gate.accepts(
          chat(text: 'skewed', sentAt: now.add(const Duration(seconds: 20))),
          now: now,
        ),
        isTrue,
      );
    });

    test('bounds retained fingerprints', () {
      final gate = DanmakuMessageGate(maxEntries: 2);
      final now = DateTime(2026, 9, 26, 12);

      for (var index = 0; index < 10; index++) {
        expect(
          gate.accepts(
            chat(id: 'm$index', text: 'text $index'),
            now: now,
          ),
          isTrue,
        );
      }

      expect(gate.size, lessThanOrEqualTo(2));
    });

    test('clear forgets every fingerprint', () {
      final gate = DanmakuMessageGate();
      final now = DateTime(2026, 9, 26, 12);

      expect(gate.accepts(chat(id: 'm1'), now: now), isTrue);
      gate.clear();

      expect(gate.accepts(chat(id: 'm1'), now: now), isTrue);
      expect(gate.size, 1);
    });

    test('applyWindows reinterprets nothing: retained fingerprints are dropped', () {
      final gate = DanmakuMessageGate();
      final now = DateTime(2026, 9, 26, 12);

      expect(gate.accepts(chat(id: 'm1'), now: now), isTrue);

      gate.applyWindows(
        fallbackDuplicateWindow: const Duration(seconds: 1),
        stableIdWindow: const Duration(seconds: 30),
        maxMessageAge: const Duration(seconds: 10),
        maxEntries: 16,
      );

      expect(gate.size, 0);
      expect(gate.accepts(chat(id: 'm1'), now: now), isTrue);
      expect(gate.stableIdWindow, const Duration(seconds: 30));
      expect(gate.maxMessageAge, const Duration(seconds: 10));
      expect(gate.maxEntries, 16);
    });

    test('rejects an empty-fingerprint packet only through its own identity', () {
      final gate = DanmakuMessageGate();
      final now = DateTime(2026, 9, 26, 12);

      // No id, no user, no text: every such packet shares one fingerprint.
      expect(gate.accepts(chat(text: ''), now: now), isTrue);
      expect(gate.accepts(chat(text: ''), now: now), isFalse);
      expect(
        gate.accepts(
          chat(text: '', user: 'other'),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
