import 'dart:async';

import 'package:media_core_audio/src/lyric/lrc_parser.dart';
import 'package:media_core_audio/src/lyric/lyric_document.dart';
import 'package:media_core_audio/src/source/music_source.dart';
import 'package:media_core_audio/src/source/music_source_registry.dart';
import 'package:media_core_audio/src/track/music_track.dart';

/// Supplies raw lyric material for a track.
///
/// The default implementation asks the track's own [MusicSource]; a host that
/// keeps lyrics in a database, a sidecar folder or a third-party service
/// passes its own provider and keeps this package free of that decision.
typedef LyricProvider = Future<MusicLyricPayload?> Function(MusicTrack track);

/// Loads and caches parsed lyrics.
///
/// Caching is not an optimization here, it is a requirement: lyric endpoints
/// are slow and rate-limited, and every track change is followed immediately
/// by a lyric request. Entries are keyed by track identity and bounded by
/// [maxEntries] with least-recently-used eviction, so a long listening session
/// cannot grow memory without limit.
///
/// Parsing happens once per track — [LyricDocument] is immutable and shared
/// between the in-app view, the desktop overlay and the notification.
final class LyricLoader {
  /// Creates a loader.
  ///
  /// Without a [provider] the loader resolves through [registry].
  LyricLoader({MusicSourceRegistry? registry, LyricProvider? provider, this.maxEntries = 64})
    : _registry = registry,
      _provider = provider;

  /// Maximum number of cached documents.
  final int maxEntries;

  final MusicSourceRegistry? _registry;
  final LyricProvider? _provider;
  final LrcParser _parser = const LrcParser();

  final Map<String, LyricDocument> _cache = <String, LyricDocument>{};
  final Map<String, Completer<LyricDocument>> _inFlight = <String, Completer<LyricDocument>>{};

  /// Number of cached documents.
  int get cacheSize => _cache.length;

  /// Returns the cached document for [track] without touching the network.
  LyricDocument? peek(MusicTrack track) => _cache[_keyOf(track)];

  /// Loads the lyric for [track].
  ///
  /// [force] bypasses the cache. Concurrent calls for the same track share one
  /// request — track changes fire in bursts (queue advance, source switch,
  /// desktop overlay appearing), and each of them asking separately is how a
  /// lyric endpoint starts rate-limiting.
  ///
  /// Returns [LyricDocument.empty] when the track has no lyric; never throws
  /// for a missing lyric, because "no lyrics" is a normal state, not an error.
  Future<LyricDocument> load(MusicTrack track, {bool force = false}) {
    final key = _keyOf(track);

    if (!force) {
      final cached = _cache[key];

      if (cached != null) {
        _touch(key, cached);

        return Future<LyricDocument>.value(cached);
      }

      final pending = _inFlight[key];

      if (pending != null) {
        return pending.future;
      }
    }

    final completer = Completer<LyricDocument>();
    _inFlight[key] = completer;

    unawaited(
      _fetch(track).then(
        (document) {
          _inFlight.remove(key);

          if (!document.isEmpty) {
            _store(key, document);
          }

          if (!completer.isCompleted) {
            completer.complete(document);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _inFlight.remove(key);

          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      ),
    );

    return completer.future;
  }

  /// Warms the cache for [track]; failures are swallowed.
  ///
  /// Called for the next queue entry: the delay between "next" being pressed
  /// and the lyric endpoint answering is the single most visible gap in a
  /// music UI.
  Future<void> prefetch(MusicTrack track) async {
    if (_cache.containsKey(_keyOf(track))) {
      return;
    }

    try {
      await load(track);
    } on Object catch (_) {
      // Prefetch never surfaces an error; the on-demand load will.
    }
  }

  /// Drops one entry, or everything when [track] is null.
  void evict([MusicTrack? track]) {
    if (track == null) {
      _cache.clear();

      return;
    }

    _cache.remove(_keyOf(track));
  }

  Future<LyricDocument> _fetch(MusicTrack track) async {
    final payload = await _resolve(track);

    if (payload == null || payload.lyric.trim().isEmpty) {
      return LyricDocument.empty;
    }

    return _parser.parse(payload.lyric, translation: payload.translation, romanization: payload.romanization);
  }

  Future<MusicLyricPayload?> _resolve(MusicTrack track) {
    final provider = _provider;

    if (provider != null) {
      return provider(track);
    }

    final registry = _registry;

    if (registry == null) {
      return Future<MusicLyricPayload?>.value();
    }

    return registry.resolveLyric(track);
  }

  void _store(String key, LyricDocument document) {
    _cache[key] = document;

    while (_cache.length > maxEntries && _cache.isNotEmpty) {
      // Map preserves insertion order: the first key is the oldest until it is
      // re-inserted by a hit, which is what makes this an LRU.
      _cache.remove(_cache.keys.first);
    }
  }

  void _touch(String key, LyricDocument document) {
    _cache.remove(key);
    _cache[key] = document;
  }

  String _keyOf(MusicTrack track) => '${track.sourceId}\u0000${track.id}';
}
