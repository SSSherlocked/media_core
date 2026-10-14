import 'dart:collection';

import 'package:media_core_list_playback/src/playback_list_config.dart';

/// Remembers where each item was left.
///
/// The contract is deliberately small and asynchronous: a host that wants
/// progress to survive a restart implements it over shared preferences or a
/// database, while the in-memory implementation below is what an ephemeral
/// queue needs.
///
/// Implementations must never throw for a missing entry — an unknown item
/// simply has no remembered position.
abstract interface class PlaybackProgressStore {
  /// Remembered position for [itemId], or `null` when none is worth resuming.
  Future<Duration?> positionOf(String itemId);

  /// Stores [position] for [itemId].
  Future<void> save(String itemId, Duration position);

  /// Forgets [itemId].
  Future<void> clear(String itemId);

  /// Forgets everything.
  Future<void> clearAll();
}

/// In-memory [PlaybackProgressStore] with a bounded, least-recently-used map.
///
/// Suitable for a session-scoped list. Entries are trimmed to
/// [PlaybackListConfig.maxRememberedItems], and reads count as use: a viewer
/// who returns to an old item keeps it alive while one-off items age out.
final class InMemoryPlaybackProgressStore implements PlaybackProgressStore {
  /// Creates a store bounded by [config]'s `maxRememberedItems`.
  InMemoryPlaybackProgressStore({this.config = PlaybackListConfig.defaults});

  /// Configuration supplying the bound.
  final PlaybackListConfig config;

  /// Insertion-ordered so the oldest entry can be evicted in O(1).
  final LinkedHashMap<String, Duration> _positions = LinkedHashMap<String, Duration>();

  /// Number of remembered items.
  int get length => _positions.length;

  @override
  Future<Duration?> positionOf(String itemId) async {
    final position = _positions.remove(itemId);
    if (position == null) {
      return null;
    }
    _positions[itemId] = position;
    return position;
  }

  @override
  Future<void> save(String itemId, Duration position) async {
    _positions.remove(itemId);
    _positions[itemId] = position;
    while (_positions.length > config.maxRememberedItems) {
      _positions.remove(_positions.keys.first);
    }
  }

  @override
  Future<void> clear(String itemId) async => _positions.remove(itemId);

  @override
  Future<void> clearAll() async => _positions.clear();
}
