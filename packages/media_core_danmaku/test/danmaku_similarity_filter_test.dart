import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_danmaku/media_core_danmaku.dart';

void main() {
  group('DanmakuSimilarityFilter', () {
    test('answers an exact repeat from the cache without scoring it', () {
      final filter = DanmakuSimilarityFilter();

      expect(filter.shouldDisplay('666'), isTrue);
      expect(filter.lastComparisonCount, 0);
      expect(filter.shouldDisplay('666'), isFalse);
      expect(filter.lastComparisonCount, 0, reason: 'an exact hit must not run edit-distance work');
    });

    test('suppresses a near-identical variation', () {
      final filter = DanmakuSimilarityFilter();

      // One character apart out of nine: scored high enough at the default
      // threshold of 85. Shorter texts need more of the string to match.
      expect(filter.shouldDisplay('主播今天真的好厉害'), isTrue);
      expect(filter.shouldDisplay('主播今天真的好历害'), isFalse);
    });

    test('keeps genuinely different messages', () {
      final filter = DanmakuSimilarityFilter();

      expect(filter.shouldDisplay('666'), isTrue);
      expect(filter.shouldDisplay('今天的比赛真精彩'), isTrue);
    });

    test('treats empty text as nothing to show', () {
      final filter = DanmakuSimilarityFilter();

      expect(filter.shouldDisplay('   '), isFalse);
      expect(filter.cacheSize, 0);
    });

    test('honours the comparison budget instead of the cache size', () {
      final filter = DanmakuSimilarityFilter(maxCacheSize: 50, maxComparisons: 2);
      // Deliberately dissimilar words: similar ones would be collapsed by the
      // filter itself and never reach the cache.
      const words = <String>[
        'alpha',
        'bravo',
        'charlie',
        'delta',
        'echo',
        'foxtrot',
        'golf',
        'hotel',
        'india',
        'juliet',
      ];

      for (final word in words) {
        expect(filter.shouldDisplay(word), isTrue);
      }

      // One more distinct message: at most the budget may be scored, never the
      // fifty retained entries.
      expect(filter.shouldDisplay('kilogram'), isTrue);
      expect(filter.lastComparisonCount, lessThanOrEqualTo(2));
      expect(filter.cacheSize, greaterThan(2));
    });

    test('forgets messages once the cache duration passes', () {
      var now = DateTime(2026, 9, 26, 12);
      final filter = DanmakuSimilarityFilter(clock: () => now);

      expect(filter.shouldDisplay('666'), isTrue);
      expect(filter.shouldDisplay('666'), isFalse);

      now = now.add(const Duration(seconds: 4));
      expect(filter.shouldDisplay('666'), isTrue);
    });

    test('trims the cache to the configured size', () {
      final filter = DanmakuSimilarityFilter(maxCacheSize: 2);

      expect(filter.shouldDisplay('toast'), isTrue);
      expect(filter.shouldDisplay('banana'), isTrue);
      expect(filter.shouldDisplay('orange'), isTrue);

      expect(filter.cacheSize, lessThanOrEqualTo(2));
    });

    test('updateConfig applies a lower threshold and trims immediately', () {
      final filter = DanmakuSimilarityFilter(maxCacheSize: 1);

      expect(filter.shouldDisplay('toast'), isTrue);
      expect(filter.shouldDisplay('banana'), isTrue);
      expect(filter.cacheSize, 1);

      filter.updateConfig(similarityThreshold: 120, cacheDuration: const Duration(seconds: 1), maxCacheSize: 500);

      expect(filter.similarityThreshold, 100, reason: 'threshold is clamped to 0..100');
      expect(filter.cacheDuration, const Duration(seconds: 1));
      expect(filter.maxCacheSize, 500);
      expect(filter.shouldDisplay('banana'), isFalse, reason: 'a threshold of 100 still matches exactly');
    });

    test('clear forgets every message', () {
      final filter = DanmakuSimilarityFilter();

      expect(filter.shouldDisplay('666'), isTrue);
      filter.clear();

      expect(filter.cacheSize, 0);
      expect(filter.shouldDisplay('666'), isTrue);
    });
  });
}
