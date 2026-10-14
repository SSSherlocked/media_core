import 'package:example/demos/module_demo.dart';
import 'package:media_core_audio/media_core_audio.dart';

/// Music sources: the extension point a platform integration implements.
///
/// Everything platform-specific in a music player lives behind one interface:
/// find tracks, resolve a track to a URL, fetch a lyric. The demo implements a
/// minimal source inline — which is also the documentation for how to write a
/// real one.
class SourceDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'source';

  @override
  ModuleCategory get category => ModuleCategory.foundation;

  @override
  String get nameZh => '音源与地址解析';

  @override
  String get nameEn => 'Music sources & resolution';

  @override
  String get purposeZh =>
      'MusicSource 声明"怎么找歌、怎么拿地址、怎么拿歌词"，MusicSourceRegistry 按 track.sourceId 分发。播放地址单独建模并带 expiresAt，过期就重解析而不是重放。';

  @override
  String get purposeEn =>
      'MusicSource declares how to find, resolve and fetch lyrics; MusicSourceRegistry dispatches by track.sourceId. The playback URL is modelled separately with expiresAt, so an expired signature is re-resolved instead of replayed.';

  @override
  List<String> get pointsZh => const <String>[
    'MusicSource: search / trackDetail / qualities / resolveTrackSource / resolveLyric',
    'TrackSource 带 headers / expiresAt → 平台签名 URL 短时效也不会被重放',
    'TrackSource.toPlayerSource() 是"音乐"到"播放器"的唯一转换点',
    'LocalMusicSource 把本地文件也当成一种音源（可混排）',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'MusicSource: search / trackDetail / qualities / resolveTrackSource / resolveLyric',
    'TrackSource carries headers / expiresAt → a short-lived signed URL is never replayed',
    'TrackSource.toPlayerSource() is the only bridge from "music" to "player"',
    'LocalMusicSource treats files on disk as one more source (queues can mix)',
  ];

  @override
  String get snippet => '''
class MySource implements MusicSource {
  @override String get id => 'my_platform';

  @override
  Future<TrackSource> resolveTrackSource(MusicTrack track, {MusicQuality? quality}) async {
    final signed = await api.getPlayUrl(track.id, quality: quality?.id);
    return TrackSource(
      uri: Uri.parse(signed.url),
      headers: signed.headers,
      expiresAt: DateTime.now().add(Duration(seconds: signed.ttlSeconds)),
    );
  }
}

final registry = MusicSourceRegistry([MySource()]);
final source = await registry.resolveTrackSource(track);
final playerSource = source.toPlayerSource(trackId: track.id);
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();
    final registry = MusicSourceRegistry(<MusicSource>[_DemoSource()]);

    buffer
      ..writeln('registered sources: ${registry.ids}')
      ..writeln();

    final page = await registry.find('demo')!.search('song');

    buffer.writeln('search("song") → ${page.items.length} track(s)');

    for (final track in page.items) {
      buffer.writeln('  ${track.displayName}   (${track.sourceId}/${track.id})');
    }

    buffer.writeln();

    final track = page.items.first;
    final resolution = await registry.resolveTrackSource(track, quality: MusicQuality.k320);

    buffer
      ..writeln('resolved: $resolution')
      ..writeln('  headers: ${resolution.headers}')
      ..writeln('  expiresAt: ${resolution.expiresAt}')
      ..writeln('  expired now? ${resolution.isExpired()}')
      ..writeln();

    // The single conversion point between the music domain and the player.
    final playerSource = resolution.toPlayerSource(trackId: track.id, title: track.displayName);

    buffer
      ..writeln('→ PlayerSource')
      ..writeln('  id: ${playerSource.id.value}')
      ..writeln('  protocol: ${playerSource.protocol.name}   format: ${playerSource.format.name}')
      ..writeln('  headers: ${playerSource.headers?.values}')
      ..writeln('  metadata: ${playerSource.metadata}')
      ..writeln();

    final expired = TrackSource(
      uri: Uri.parse('https://cdn.example.com/song.mp3?sig=old'),
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    buffer
      ..writeln('an expired resolution: $expired')
      ..writeln('  isExpired() → ${expired.isExpired()}  (the controller re-resolves instead of replaying it)')
      ..writeln()
      ..writeln('a local file is just another source:')
      ..writeln('  MusicTrack.local(path: "/music/a.flac", title: "a.flac") → sourceId "${MusicTrack.localSourceId}"');

    return buffer.toString();
  }
}

/// A source that pretends to be a platform.
final class _DemoSource extends MusicSource {
  @override
  String get id => 'demo';

  @override
  String get name => 'Demo platform';

  @override
  Future<MusicSourcePage<MusicTrack>> search(String keyword, {int page = 1, int pageSize = 30}) async {
    return MusicSourcePage<MusicTrack>(
      items: <MusicTrack>[
        for (var index = 1; index <= 3; index++)
          MusicTrack(
            id: 'song_$index',
            title: 'Demo Song $index',
            artist: index.isEven ? 'Artist B' : 'Artist A',
            album: 'Demo Album',
            duration: Duration(seconds: 180 + index * 7),
            sourceId: id,
          ),
      ],
      total: 3,
    );
  }

  @override
  Future<TrackSource> resolveTrackSource(MusicTrack track, {MusicQuality? quality}) async {
    // A real integration signs the URL and reports how long it lives; the demo
    // pretends to have done exactly that.
    return TrackSource(
      uri: Uri.parse('https://cdn.example.com/${track.id}.mp3?quality=${quality?.id ?? 'auto'}'),
      headers: const <String, String>{'Referer': 'https://example.com'},
      quality: quality ?? MusicQuality.auto,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }
}
