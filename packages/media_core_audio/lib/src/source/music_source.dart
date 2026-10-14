import 'package:flutter/foundation.dart' show immutable;
import 'package:media_core_audio/src/track/music_quality.dart';
import 'package:media_core_audio/src/track/music_track.dart';
import 'package:media_core_audio/src/track/track_source.dart';

/// One platform's music API, expressed as a source.
///
/// The shape follows the "music source" concept a host app plugin ecosystem
/// popularized: a source can *find* tracks and *resolve* them to audio and
/// lyrics, and nothing else in the framework knows how any particular
/// platform works. Implementations live in the host app (they carry
/// site-specific crypto, tokens and headers), so this package only fixes the
/// contract.
///
/// Implementations **extend** this class (`extends MusicSource`) so the
/// optional members below come for free — which is why this is an
/// `abstract class` and not an `abstract interface class`: an interface class
/// could not be extended from outside this library, and the defaults are the
/// point.
///
/// The defaults split by whether an empty answer is *true*:
///
/// - [trackDetail], [qualities], [catalogs] and [resolveLyric] answer "this
///   source has nothing more to say", which is a fact about many sources.
/// - [search] and [catalogItems] throw. A source that cannot search does not
///   have zero results — reporting an empty page would put "no matches for
///   your query" on screen for a platform that was never asked.
abstract class MusicSource {
  /// Stable identifier, referenced by [MusicTrack.sourceId].
  String get id;

  /// Display name for the host's source picker.
  String get name;

  /// Searches this platform.
  ///
  /// A source with no search has to say so: the default throws rather than
  /// returning an empty page, because an empty page is an answer about the
  /// platform's contents and this knows nothing about them.
  Future<MusicSourcePage<MusicTrack>> search(String keyword, {int page = 1, int pageSize = 30}) async {
    throw UnsupportedError('MusicSource($id) does not implement search.');
  }

  /// Re-reads a track's metadata.
  ///
  /// Called when a queue entry came from a stale cache; the default keeps the
  /// track as it is, which is correct for sources with no extra metadata.
  Future<MusicTrack> trackDetail(MusicTrack track) async => track;

  /// Tiers this track can be served in, best last.
  Future<List<MusicQuality>> qualities(MusicTrack track) async {
    return const <MusicQuality>[];
  }

  /// Resolves [track] to a playable URL.
  ///
  /// Implementations must return a *fresh* URL on every call: the caller
  /// caches resolutions against [TrackSource.expiresAt] and re-resolves when
  /// one is spent.
  Future<TrackSource> resolveTrackSource(MusicTrack track, {MusicQuality? quality});

  /// Fetches the lyric of [track], or null when the platform has none.
  ///
  /// The returned text is raw LRC — parsing, translation merging and word
  /// timing belong to the lyric module, not to a source.
  Future<MusicLyricPayload?> resolveLyric(MusicTrack track) async => null;

  /// Playlists/leaderboards this source exposes, when it has any.
  Future<List<MusicCatalog>> catalogs() async => const <MusicCatalog>[];

  /// Items of a catalog from [catalogs].
  ///
  /// Only ever called with a catalog this source advertised, so the default
  /// throws: an empty page here would mean a list the source offered and
  /// cannot fill, presented to the viewer as a catalog with nothing in it.
  Future<MusicSourcePage<MusicTrack>> catalogItems(MusicCatalog catalog, {int page = 1}) async {
    throw UnsupportedError(
      'MusicSource($id) advertised catalog ${catalog.id} but does not '
      'implement catalogItems.',
    );
  }

  @override
  String toString() => 'MusicSource($id)';
}

/// Raw lyric material returned by a source.
///
/// Lyrics arrive in three independent pieces and any of them may be missing;
/// keeping them apart means a translation table never has to be re-parsed out
/// of the original text.
final class MusicLyricPayload {
  /// Creates a lyric payload.
  const MusicLyricPayload({required this.lyric, this.translation, this.romanization, this.format = 'lrc'});

  /// Original lyric text (LRC, possibly with word-level `<mm:ss.xx>` tags).
  final String lyric;

  /// Translated lyric text, usually the same timestamps.
  final String? translation;

  /// Romanized lyric text (pinyin, romaji, …), when available.
  final String? romanization;

  /// Text format hint; `lrc` is the only one this package parses today, and
  /// anything else is surfaced as unsynchronized text.
  final String format;

  @override
  String toString() => 'MusicLyricPayload(${lyric.length} chars${translation == null ? '' : ', +translation'})';
}

/// A named list a source can serve (playlist, leaderboard, radio).
@immutable
final class MusicCatalog {
  /// Creates a catalog descriptor.
  const MusicCatalog({required this.id, required this.name, this.description, this.coverUri});

  /// Source-scoped catalog id.
  final String id;

  /// Display name.
  final String name;

  /// Optional description.
  final String? description;

  /// Optional cover.
  final Uri? coverUri;

  @override
  bool operator ==(Object other) => other is MusicCatalog && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
