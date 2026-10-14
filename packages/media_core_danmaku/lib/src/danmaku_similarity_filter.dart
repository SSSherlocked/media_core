import 'dart:collection';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:media_core_danmaku/src/danmaku_repeated_filter.dart' show DanmakuRepeatedFilter;

/// Suppresses messages that are *almost* the same as one recently shown.
///
/// [DanmakuRepeatedFilter] only collapses exact repeats; real rooms spam with
/// small variations ("666", "6666", "666！"). This filter scores each new text
/// against the newest [maxComparisons] cached texts and treats a score at or
/// above [similarityThreshold] as a duplicate.
///
/// Three things keep the cost bounded on the UI isolate:
///
/// - the retained cache ([maxCacheSize]) and the per-packet comparison budget
///   ([maxComparisons]) are separate, so a long configured history does not
///   multiply the work done for one packet;
/// - only the newest slice of the cache is scored — iteration skips older
///   entries before any edit-distance work starts;
/// - an exact hit is answered from the map without running the algorithm, and
///   refreshes the entry's position instead of re-scoring it.
///
/// [lastComparisonCount] reports the work done for the most recent call and
/// exists for performance regression tests, not for callers.
final class DanmakuSimilarityFilter {
  /// Creates a filter that scores each new text against the newest
  /// [maxComparisons] of a [maxCacheSize]-message cache; [clock] is injectable
  /// so tests control expiry.
  DanmakuSimilarityFilter({
    int similarityThreshold = 85,
    Duration cacheDuration = const Duration(seconds: 3),
    int maxCacheSize = 100,
    int maxComparisons = 96,
    DateTime Function()? clock,
  }) : _similarityThreshold = similarityThreshold.clamp(0, 100),
       _cacheDuration = cacheDuration,
       _maxCacheSize = maxCacheSize.clamp(1, 1000),
       _maxComparisons = maxComparisons.clamp(1, 256),
       _clock = clock ?? DateTime.now;

  int _similarityThreshold;
  Duration _cacheDuration;
  int _maxCacheSize;
  final int _maxComparisons;
  final DateTime Function() _clock;

  /// Insertion-ordered so the trimmed slice is always the newest messages.
  final LinkedHashMap<String, _CachedDanmaku> _cache = LinkedHashMap<String, _CachedDanmaku>();

  int _lastComparisonCount = 0;

  /// Minimum similarity score (0..100) that counts as a duplicate.
  int get similarityThreshold => _similarityThreshold;

  /// How long a message stays in the cache.
  Duration get cacheDuration => _cacheDuration;

  /// Maximum number of retained messages.
  int get maxCacheSize => _maxCacheSize;

  /// Maximum comparisons performed for one message.
  int get maxComparisons => _maxComparisons;

  /// Comparisons performed by the most recent [shouldDisplay] call.
  int get lastComparisonCount => _lastComparisonCount;

  /// Number of currently cached messages.
  int get cacheSize => _cache.length;

  /// Applies a new configuration without dropping the retained history.
  ///
  /// Shrinking [maxCacheSize] trims immediately so the bound is never
  /// temporarily exceeded.
  void updateConfig({int? similarityThreshold, Duration? cacheDuration, int? maxCacheSize}) {
    if (similarityThreshold != null) {
      _similarityThreshold = similarityThreshold.clamp(0, 100);
    }
    if (cacheDuration != null) _cacheDuration = cacheDuration;
    if (maxCacheSize != null) {
      _maxCacheSize = maxCacheSize.clamp(1, 1000);
      _trimCache();
    }
  }

  /// Whether [text] differs enough from recent messages to be shown.
  ///
  /// Returns `false` for empty text: there is nothing to compare and nothing
  /// worth rendering.
  bool shouldDisplay(String text) {
    final normalized = _normalizeText(text);
    if (normalized.isEmpty) return false;

    final now = _clock();
    _lastComparisonCount = 0;
    _removeExpiredEntries(now);

    final cachedMessage = _cache[normalized];
    if (cachedMessage != null) {
      cachedMessage.count++;
      cachedMessage.lastSeenAt = now;
      _markAsNewest(normalized, cachedMessage);
      return false;
    }

    var skipped = (_cache.length - _maxComparisons).clamp(0, _cache.length);
    for (final entry in _cache.entries) {
      if (skipped > 0) {
        skipped--;
        continue;
      }
      final cached = entry.value;
      _lastComparisonCount++;
      if (partialRatio(cached.text, normalized) >= _similarityThreshold) {
        cached.count++;
        cached.lastSeenAt = now;
        _markAsNewest(entry.key, cached);
        return false;
      }
    }

    _cache[normalized] = _CachedDanmaku(text: normalized, lastSeenAt: now);
    _trimCache();
    return true;
  }

  /// Forgets every cached message.
  void clear() => _cache.clear();

  void _removeExpiredEntries(DateTime now) {
    _cache.removeWhere((_, cached) => now.difference(cached.lastSeenAt) > _cacheDuration);
  }

  void _trimCache() {
    while (_cache.length > _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _markAsNewest(String key, _CachedDanmaku value) {
    _cache.remove(key);
    _cache[key] = value;
  }

  /// Trims surrounding whitespace only.
  ///
  /// Emoji, punctuation and other Unicode content are preserved: they carry
  /// most of the meaning in the short texts danmaku is made of.
  String _normalizeText(String text) => text.trim();
}

final class _CachedDanmaku {
  _CachedDanmaku({required this.text, required this.lastSeenAt}) : count = 1;

  final String text;
  DateTime lastSeenAt;
  int count;
}
