import 'package:flutter_test/flutter_test.dart';

import 'package:media_core_audio/src/source/music_source.dart';
import 'package:media_core_audio/src/track/music_quality.dart';
import 'package:media_core_audio/src/track/music_track.dart';
import 'package:media_core_audio/src/track/track_source.dart';

/// A source that implements the bare minimum the contract requires.
final class _BareSource extends MusicSource {
  @override
  String get id => 'bare';

  @override
  String get name => 'Bare';

  @override
  Future<TrackSource> resolveTrackSource(MusicTrack track, {MusicQuality? quality}) {
    throw UnimplementedError('not exercised here');
  }
}

void main() {
  group('MusicSource defaults', () {
    test('a source that cannot search says so instead of returning nothing', () {
      // An empty page is a claim about the platform's contents. A source that
      // never asked the platform must not make it, or the viewer reads "no
      // matches" for a query nobody ran.
      expect(() => _BareSource().search('anything'), throwsA(isA<UnsupportedError>()));
    });

    test('a source with no catalogs answers empty, which is true', () async {
      expect(await _BareSource().catalogs(), isEmpty);
    });

    test('a catalog that was advertised but cannot be filled throws', () {
      expect(
        () => _BareSource().catalogItems(const MusicCatalog(id: 'top', name: 'Top')),
        throwsA(isA<UnsupportedError>().having((e) => e.message, 'message', allOf(contains('bare'), contains('top')))),
      );
    });

    test('no extra metadata means the track comes back as it went in', () async {
      const track = MusicTrack(id: 't1', sourceId: 'bare', title: 'Song');

      expect(await _BareSource().trackDetail(track), track);
    });

    test('no tiers and no lyric are honest answers, not failures', () async {
      const track = MusicTrack(id: 't1', sourceId: 'bare', title: 'Song');

      expect(await _BareSource().qualities(track), isEmpty);
      expect(await _BareSource().resolveLyric(track), isNull);
    });
  });
}
