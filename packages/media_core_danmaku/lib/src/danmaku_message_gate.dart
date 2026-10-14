import 'dart:collection';

import 'package:media_core_danmaku/src/danmaku_message.dart';

/// Rejects platform backlog and duplicate delivery while keeping memory
/// bounded.
///
/// Two mechanisms run here, and they are deliberately not the same:
///
/// - **Age**: a message older than [maxMessageAge] is dropped. A socket that
///   kept buffering while the app was backgrounded must not dump a backlog
///   into the view as if it were live chat.
/// - **Identity**: a stable platform id keeps its own long window, because an
///   id is unambiguous and a replay can be rejected without risk. Platforms
///   without ids fall back to a short fingerprint window (type + viewer +
///   text), which is long enough to catch a reconnect replay and short enough
///   that an active chat still shows genuine repetition such as "666".
///
/// Clock skew is tolerated up to [maxFutureSkew]; larger future timestamps are
/// treated as malformed rather than being allowed to poison the id cache.
final class DanmakuMessageGate {
  /// Creates a gate with the given duplicate windows, age limit and memory
  /// bound; each can be replaced later through [applyWindows].
  DanmakuMessageGate({
    Duration fallbackDuplicateWindow = const Duration(milliseconds: 2500),
    Duration stableIdWindow = const Duration(minutes: 10),
    Duration maxMessageAge = const Duration(seconds: 45),
    Duration maxFutureSkew = const Duration(minutes: 10),
    int maxEntries = 4096,
  }) : assert(maxEntries > 0, 'maxEntries must leave room for at least one fingerprint'),
       _fallbackDuplicateWindow = fallbackDuplicateWindow,
       _stableIdWindow = stableIdWindow,
       _maxMessageAge = maxMessageAge,
       _maxFutureSkew = maxFutureSkew,
       _maxEntries = maxEntries;

  Duration _fallbackDuplicateWindow;
  Duration _stableIdWindow;
  Duration _maxMessageAge;
  final Duration _maxFutureSkew;
  int _maxEntries;

  /// Duplicate window for messages without a platform id.
  Duration get fallbackDuplicateWindow => _fallbackDuplicateWindow;

  /// Duplicate window for messages with a platform id.
  Duration get stableIdWindow => _stableIdWindow;

  /// Maximum accepted message age.
  Duration get maxMessageAge => _maxMessageAge;

  /// How far ahead of local time a platform timestamp may be before the
  /// packet is treated as malformed.
  Duration get maxFutureSkew => _maxFutureSkew;

  /// Upper bound on remembered fingerprints.
  int get maxEntries => _maxEntries;

  /// Insertion-ordered so eviction can drop the oldest entry in O(1) without
  /// scanning.
  ///
  /// Because a rejected repeat leaves its entry untouched, insertion order is
  /// exactly first-arrival order — the same order [stableIdWindow] measures
  /// from — so eviction and the duplicate window agree on what "oldest" means.
  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap<String, DateTime>();

  /// Applies new windows.
  ///
  /// The retained fingerprints are dropped rather than reinterpreted: each
  /// entry records when it was seen, not which window accepted it, so keeping
  /// them under a new rule would judge old traffic by a rule that was not in
  /// force when it arrived.
  void applyWindows({
    required Duration fallbackDuplicateWindow,
    required Duration stableIdWindow,
    required Duration maxMessageAge,
    required int maxEntries,
  }) {
    _fallbackDuplicateWindow = fallbackDuplicateWindow;
    _stableIdWindow = stableIdWindow;
    _maxMessageAge = maxMessageAge;
    _maxEntries = maxEntries;
    _seen.clear();
  }

  /// Whether [message] should be passed on to the filters and the host.
  ///
  /// [now] exists for deterministic tests; production callers omit it.
  bool accepts(DanmakuMessage message, {DateTime? now}) {
    final receivedAt = now ?? DateTime.now();
    final sentAt = message.sentAt;

    if (sentAt != null) {
      final age = receivedAt.difference(sentAt);
      if (age > maxMessageAge) return false;
      if (age < -maxFutureSkew) return false;
    }

    final key = _fingerprint(message);
    final duplicateWindow = message.hasStableId ? stableIdWindow : fallbackDuplicateWindow;

    final previous = _seen[key];
    if (previous != null && receivedAt.difference(previous) <= duplicateWindow) {
      // The window is measured from the first arrival and a rejected repeat
      // does not extend it. That is deliberate: a socket flapping for an hour
      // must not be able to keep one id suppressed for an hour, and the
      // duplicate window only has to outlast a reconnect replay.
      return false;
    }

    _seen[key] = receivedAt;
    _evictExpired(receivedAt);
    return true;
  }

  /// Forgets every fingerprint.
  ///
  /// Called when the session changes identity (room switch, transport
  /// replacement): ids from the previous socket say nothing about the new one.
  void clear() => _seen.clear();

  /// Number of retained fingerprints. Exposed for tests and diagnostics.
  int get size => _seen.length;

  String _fingerprint(DanmakuMessage message) {
    final stableId = message.messageId.trim();
    if (stableId.isNotEmpty) return 'id:$stableId';

    // Without an id the best available identity is the sender plus the exact
    // text. Display names are lowercased for the comparison only.
    return 'text:${message.type.index}:'
        '${message.userId.trim().toLowerCase()}:'
        '${message.userName.trim().toLowerCase()}:'
        '${message.text.trim()}';
  }

  void _evictExpired(DateTime now) {
    // Every survivor is newer than the stable-id window, so the oldest-first
    // scan can stop at the first fresh entry.
    final oldestAllowed = now.subtract(stableIdWindow);
    while (_seen.isNotEmpty && _seen.values.first.isBefore(oldestAllowed)) {
      _seen.remove(_seen.keys.first);
    }
    while (_seen.length > maxEntries) {
      _seen.remove(_seen.keys.first);
    }
  }
}
