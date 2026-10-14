import 'dart:collection';
import 'package:media_core_danmaku/src/danmaku_message.dart';
import 'package:media_core_danmaku/src/danmaku_message_gate.dart' show DanmakuMessageGate;

/// Collapses a short burst of identical text into its first message.
///
/// This is intentionally separate from [DanmakuMessageGate]. The gate rejects
/// replayed packets from one sender or one platform id — it answers "did this
/// already arrive?". This filter answers a different question: "is the room
/// copy-pasting the same line right now?". Ten different accounts sending the
/// same text are ten distinct deliveries that the gate must accept, and a
/// viewer who does not want to read that line ten times wants this filter.
///
/// Consequences of that split, stated explicitly:
///
/// - Only [DanmakuMessageType.chat] is affected; gifts and paid messages are
///   never collapsed.
/// - Local and system messages are never affected, so echoing the viewer's own
///   send is always visible even if the room is spamming the same words.
/// - Disabling the filter clears the window instead of freezing it, so
///   re-enabling starts a fresh window rather than suppressing text that was
///   seen before the filter was turned off.
final class DanmakuRepeatedFilter {
  /// Creates a filter remembering at most [maxEntries] texts; a window larger
  /// than that evicts the oldest text first.
  DanmakuRepeatedFilter({this.maxEntries = 1024})
    : assert(maxEntries > 0, 'maxEntries must leave room for at least one text');

  /// Upper bound on remembered texts. Bounds memory in a busy room.
  final int maxEntries;

  /// Insertion-ordered so the oldest text can be evicted in O(1).
  final LinkedHashMap<String, DateTime> _lastSeen = LinkedHashMap<String, DateTime>();

  /// Whether [message] is the first occurrence of its text inside [window].
  ///
  /// [now] exists for deterministic tests; production callers omit it.
  bool accepts(DanmakuMessage message, {required bool enabled, required Duration window, DateTime? now}) {
    if (!enabled) {
      if (_lastSeen.isNotEmpty) _lastSeen.clear();
      return true;
    }

    if (message.type != DanmakuMessageType.chat || message.isLocal) return true;

    // Whitespace is collapsed for comparison only: "666" and "6 6 6" are the
    // same spam, while the rendered text keeps whatever the platform sent.
    final normalized = message.text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    if (normalized.isEmpty) return true;

    final receivedAt = now ?? DateTime.now();
    final previous = _lastSeen.remove(normalized);
    _lastSeen[normalized] = receivedAt;
    _evict(receivedAt, window);

    return previous == null || receivedAt.difference(previous) > window;
  }

  /// Forgets every remembered text.
  void clear() => _lastSeen.clear();

  /// Number of remembered texts. Exposed for tests and diagnostics.
  int get size => _lastSeen.length;

  void _evict(DateTime now, Duration window) {
    final oldestAllowed = now.subtract(window);
    while (_lastSeen.isNotEmpty && _lastSeen.values.first.isBefore(oldestAllowed)) {
      _lastSeen.remove(_lastSeen.keys.first);
    }
    while (_lastSeen.length > maxEntries) {
      _lastSeen.remove(_lastSeen.keys.first);
    }
  }
}
