import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_danmaku/media_core_danmaku.dart';

DanmakuMessage chat({String text = '666', String user = 'viewer', bool isLocal = false}) {
  return DanmakuMessage(type: DanmakuMessageType.chat, userName: user, text: text, isLocal: isLocal);
}

void main() {
  group('DanmakuRepeatedFilter', () {
    const window = Duration(seconds: 5);

    test('collapses identical text from different viewers inside the window', () {
      final filter = DanmakuRepeatedFilter();
      final now = DateTime(2026, 9, 26, 12);

      expect(
        filter.accepts(
          chat(user: 'alice'),
          enabled: true,
          window: window,
          now: now,
        ),
        isTrue,
      );
      expect(
        filter.accepts(
          chat(user: 'bob'),
          enabled: true,
          window: window,
          now: now,
        ),
        isFalse,
      );
    });

    test('accepts the text again once the window has passed', () {
      final filter = DanmakuRepeatedFilter();
      final now = DateTime(2026, 9, 26, 12);

      expect(filter.accepts(chat(), enabled: true, window: window, now: now), isTrue);
      expect(filter.accepts(chat(), enabled: true, window: window, now: now.add(const Duration(seconds: 6))), isTrue);
    });

    test('normalizes whitespace and case for comparison', () {
      final filter = DanmakuRepeatedFilter();
      final now = DateTime(2026, 9, 26, 12);

      expect(
        filter.accepts(
          chat(text: 'GO  GO'),
          enabled: true,
          window: window,
          now: now,
        ),
        isTrue,
      );
      expect(
        filter.accepts(
          chat(text: 'go go'),
          enabled: true,
          window: window,
          now: now,
        ),
        isFalse,
      );
    });

    test('treats distinct text as distinct', () {
      final filter = DanmakuRepeatedFilter();
      final now = DateTime(2026, 9, 26, 12);

      expect(filter.accepts(chat(), enabled: true, window: window, now: now), isTrue);
      expect(
        filter.accepts(
          chat(text: '777'),
          enabled: true,
          window: window,
          now: now,
        ),
        isTrue,
      );
    });

    test('never suppresses the viewer’s own echo', () {
      final filter = DanmakuRepeatedFilter();
      final now = DateTime(2026, 9, 26, 12);

      expect(filter.accepts(chat(), enabled: true, window: window, now: now), isTrue);
      expect(filter.accepts(chat(isLocal: true), enabled: true, window: window, now: now), isTrue);
      // The local message did not enter the window, so the next remote repeat
      // is still collapsed.
      expect(filter.accepts(chat(), enabled: true, window: window, now: now), isFalse);
    });

    test('leaves non-chat messages alone', () {
      final filter = DanmakuRepeatedFilter();
      final now = DateTime(2026, 9, 26, 12);
      const gift = DanmakuMessage(type: DanmakuMessageType.gift, userName: 'giver', text: 'roc');

      expect(filter.accepts(gift, enabled: true, window: window, now: now), isTrue);
      expect(filter.accepts(gift, enabled: true, window: window, now: now), isTrue);
    });

    test('disabling clears the window instead of freezing it', () {
      final filter = DanmakuRepeatedFilter();
      final now = DateTime(2026, 9, 26, 12);

      expect(filter.accepts(chat(), enabled: true, window: window, now: now), isTrue);
      expect(filter.accepts(chat(), enabled: true, window: window, now: now), isFalse);

      expect(filter.accepts(chat(), enabled: false, window: window, now: now), isTrue);
      expect(filter.size, 0);

      // Re-enabling starts a fresh window: the text seen before is visible.
      expect(filter.accepts(chat(), enabled: true, window: window, now: now), isTrue);
    });

    test('bounds remembered texts', () {
      final filter = DanmakuRepeatedFilter(maxEntries: 2);
      final now = DateTime(2026, 9, 26, 12);

      for (var index = 0; index < 10; index++) {
        expect(
          filter.accepts(
            chat(text: 'text $index'),
            enabled: true,
            window: window,
            now: now,
          ),
          isTrue,
        );
      }

      expect(filter.size, lessThanOrEqualTo(2));
    });

    test('clear forgets every text', () {
      final filter = DanmakuRepeatedFilter();
      final now = DateTime(2026, 9, 26, 12);

      expect(filter.accepts(chat(), enabled: true, window: window, now: now), isTrue);
      filter.clear();

      expect(filter.accepts(chat(), enabled: true, window: window, now: now), isTrue);
    });
  });
}
