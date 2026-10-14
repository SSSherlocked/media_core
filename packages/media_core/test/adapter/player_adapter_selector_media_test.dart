import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/adapter/composite_support.dart';
import 'package:media_core/adapter/player_adapter.dart';
import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/adapter/player_adapter_factory.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/adapter/player_adapter_selector.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_track.dart';
import 'package:media_core/source/media_track_type.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/source/source_format.dart';
import 'package:media_core/source/source_protocol.dart';

const _httpProtocols = <String>{'http', 'https', 'hls', 'dash'};
const _mp4Formats = <String>{'mp4', 'm4s', 'mpd', 'm3u8'};

PlayerAdapterRegistration _reg(String id, {required PlayerAdapterCapabilities capabilities, int priority = 0}) {
  return PlayerAdapterRegistration(id: id, capabilities: capabilities, factory: _NullFactory(), priority: priority);
}

PlayerAdapterCapabilities _caps({
  CompositeSupport composite = CompositeSupport.none,
  bool audioOnly = false,
  bool live = false,
}) => PlayerAdapterCapabilities(
  supportedProtocols: _httpProtocols,
  supportedFormats: _mp4Formats,
  compositeSupport: composite,
  supportsAudioOnly: audioOnly,
  supportsLive: live,
);

MediaTrack _videoTrack(String url) =>
    MediaTrack(uri: Uri.parse(url), kind: MediaTrackType.video, mimeType: 'video/mp4');

MediaTrack _audioTrack(String url) =>
    MediaTrack(uri: Uri.parse(url), kind: MediaTrackType.audio, mimeType: 'audio/mp4');

void main() {
  _liveScoringTests();

  group('PlayerAdapterSelector.selectMedia', () {
    test('composite source prefers native backend over externalAudio', () {
      final registry = PlayerAdapterRegistry()
        ..register(_reg('mpv', capabilities: _caps(composite: CompositeSupport.externalAudio)))
        ..register(_reg('media3', capabilities: _caps(composite: CompositeSupport.native)));
      final selector = PlayerAdapterSelector(registry);

      final composite = CompositeMediaSource(
        videoTracks: [_videoTrack('https://example.com/v.m4s')],
        audioTracks: [_audioTrack('https://example.com/a.m4s')],
      );

      expect(selector.selectMedia(composite)!.id, 'media3');
    });

    test('composite source falls to externalAudio when no native is present', () {
      final registry = PlayerAdapterRegistry()
        ..register(_reg('mpv', capabilities: _caps(composite: CompositeSupport.externalAudio)))
        ..register(_reg('ijk', capabilities: _caps()));
      final selector = PlayerAdapterSelector(registry);

      final composite = CompositeMediaSource(videoTracks: [_videoTrack('https://example.com/v.m4s')]);

      expect(selector.selectMedia(composite)!.id, 'mpv');
    });

    test('composite source still returns a none backend when it is all that exists', () {
      // A registry without any composite-capable entry must still hand
      // back the single-URL backend so the planner is the one that
      // refuses, with a reason. Returning null would hide that failure
      // at the wrong layer.
      final registry = PlayerAdapterRegistry()..register(_reg('fijk', capabilities: _caps()));
      final selector = PlayerAdapterSelector(registry);

      final composite = CompositeMediaSource(videoTracks: [_videoTrack('https://example.com/v.m4s')]);

      expect(selector.selectMedia(composite)!.id, 'fijk');
    });

    test('preferred backend wins over composite scoring', () {
      final registry = PlayerAdapterRegistry()
        ..register(_reg('mpv', capabilities: _caps(composite: CompositeSupport.externalAudio)))
        ..register(_reg('media3', capabilities: _caps(composite: CompositeSupport.native)));
      final selector = PlayerAdapterSelector(registry);

      final composite = CompositeMediaSource(
        videoTracks: [_videoTrack('https://example.com/v.m4s')],
        audioTracks: [_audioTrack('https://example.com/a.m4s')],
      );

      expect(selector.selectMedia(composite, preferredId: 'mpv')!.id, 'mpv');
    });

    test('progressive source is unaffected by composite bonuses', () {
      final registry = PlayerAdapterRegistry()
        ..register(_reg('simple', capabilities: _caps(), priority: 100))
        ..register(_reg('media3', capabilities: _caps(composite: CompositeSupport.native)));
      final selector = PlayerAdapterSelector(registry);

      final progressive = ProgressiveMediaSource(track: _videoTrack('https://example.com/v.mp4'));

      // The high-priority simple backend still wins because composite
      // support is not scored for progressive sources.
      expect(selector.selectMedia(progressive)!.id, 'simple');
    });

    test('progressive audio-only source gets a small supportsAudioOnly bonus', () {
      final registry = PlayerAdapterRegistry()
        ..register(_reg('plain', capabilities: _caps()))
        ..register(_reg('mpv', capabilities: _caps(audioOnly: true)));
      final selector = PlayerAdapterSelector(registry);

      final progressiveAudio = ProgressiveMediaSource(
        track: MediaTrack(uri: Uri.parse('https://example.com/song.mp4'), kind: MediaTrackType.audio),
      );

      expect(
        selector.scoreMedia(_lookup(registry, 'mpv'), progressiveAudio),
        greaterThan(selector.scoreMedia(_lookup(registry, 'plain'), progressiveAudio)),
      );
    });
  });

  group('PlayerAdapterSelector.mediaCandidatesFor', () {
    test('sorts composite-capable backends ahead of none backends', () {
      final registry = PlayerAdapterRegistry()
        ..register(_reg('fijk', capabilities: _caps()))
        ..register(_reg('media3', capabilities: _caps(composite: CompositeSupport.native)))
        ..register(_reg('mpv', capabilities: _caps(composite: CompositeSupport.externalAudio)));
      final selector = PlayerAdapterSelector(registry);

      final composite = CompositeMediaSource(
        videoTracks: [_videoTrack('https://example.com/v.m4s')],
        audioTracks: [_audioTrack('https://example.com/a.m4s')],
      );

      final ids = selector.mediaCandidatesFor(composite).map((r) => r.id).toList();

      expect(ids, ['media3', 'mpv', 'fijk']);
    });
  });

  group('PlayerAdapterSelector.compositeMatches', () {
    test('returns true for a progressive source regardless of backend support', () {
      final selector = PlayerAdapterSelector(PlayerAdapterRegistry());
      final progressive = ProgressiveMediaSource(track: _videoTrack('https://example.com/v.mp4'));

      expect(selector.compositeMatches(_caps(), progressive), isTrue);
      expect(selector.compositeMatches(_caps(composite: CompositeSupport.native), progressive), isTrue);
    });

    test('mirrors supportsComposite for a composite source', () {
      final selector = PlayerAdapterSelector(PlayerAdapterRegistry());
      final composite = CompositeMediaSource(videoTracks: [_videoTrack('https://example.com/v.m4s')]);

      expect(selector.compositeMatches(_caps(), composite), isFalse);
      expect(selector.compositeMatches(_caps(composite: CompositeSupport.externalAudio), composite), isTrue);
    });
  });

  group('PlayerAdapterSelector.mediaScoreTable', () {
    test('exposes compositeSupport and compositeMatch per candidate', () {
      final registry = PlayerAdapterRegistry()
        ..register(_reg('media3', capabilities: _caps(composite: CompositeSupport.native)))
        ..register(_reg('fijk', capabilities: _caps()));
      final selector = PlayerAdapterSelector(registry);

      final composite = CompositeMediaSource(
        videoTracks: [_videoTrack('https://example.com/v.m4s')],
        audioTracks: [_audioTrack('https://example.com/a.m4s')],
      );

      final table = selector.mediaScoreTable(composite);

      expect(table.map((row) => row['id']), containsAll(['media3', 'fijk']));
      final media3 = table.firstWhere((row) => row['id'] == 'media3');
      expect(media3['compositeSupport'], 'native');
      expect(media3['compositeMatch'], isTrue);
    });
  });

  group('PlayerAdapterSelector.requireMedia', () {
    test('throws StateError when the registry is empty', () {
      final selector = PlayerAdapterSelector(PlayerAdapterRegistry());
      final progressive = ProgressiveMediaSource(track: _videoTrack('https://example.com/v.mp4'));

      expect(() => selector.requireMedia(progressive), throwsA(isA<StateError>()));
    });

    test('disabled backends are never selected', () {
      final registry = PlayerAdapterRegistry()
        ..register(
          PlayerAdapterRegistration(
            id: 'off',
            capabilities: _caps(composite: CompositeSupport.native),
            factory: _NullFactory(),
            enabled: false,
          ),
        )
        ..register(_reg('on', capabilities: _caps(composite: CompositeSupport.externalAudio)));
      final selector = PlayerAdapterSelector(registry);

      final composite = CompositeMediaSource(videoTracks: [_videoTrack('https://example.com/v.m4s')]);

      expect(selector.requireMedia(composite).id, 'on');
    });
  });

  group('PlayerAdapterSelector.selectMedia vs PlayerSource parity', () {
    test('progressive selection through media matches selection through the flat path', () {
      final registry = PlayerAdapterRegistry()
        ..register(_reg('one', capabilities: _caps(), priority: 10))
        ..register(_reg('two', capabilities: _caps(), priority: 20));
      final selector = PlayerAdapterSelector(registry);

      final uri = Uri.parse('https://example.com/v.mp4');
      final flat = PlayerSource(id: SourceId('s'), uri: uri, protocol: SourceProtocol.https, format: SourceFormat.mp4);
      final media = ProgressiveMediaSource(track: _videoTrack(uri.toString()));

      expect(selector.require(flat).id, selector.requireMedia(media).id);
    });
  });
}

PlayerAdapterRegistration _lookup(PlayerAdapterRegistry registry, String id) => registry.get(id)!;

/// Placeholder factory that would never be invoked by selector tests.
class _NullFactory implements PlayerAdapterFactory {
  @override
  PlayerAdapter create(String id) => throw UnsupportedError('Factory must not be invoked by selection tests.');

  @override
  bool supports(String id) => true;
}

// Appended group: live scoring. Lives in this file because the fake
// registrations and helpers are already here.
void _liveScoringTests() {
  group('scoreMedia live bonus', () {
    test('a live source favors a supportsLive backend', () {
      final registry = PlayerAdapterRegistry()
        ..register(_reg('vod-only', capabilities: _caps()))
        ..register(_reg('live-ok', capabilities: _caps(live: true)));
      final selector = PlayerAdapterSelector(registry);

      final live = ProgressiveMediaSource.url(Uri.parse('https://example.com/stream.m3u8'), live: true);

      expect(selector.selectMedia(live)!.id, 'live-ok');
      expect(
        selector.scoreMedia(_lookup(registry, 'live-ok'), live),
        greaterThan(selector.scoreMedia(_lookup(registry, 'vod-only'), live)),
      );
    });

    test('a non-live source leaves the bonus out', () {
      final registry = PlayerAdapterRegistry()
        ..register(_reg('vod-only', capabilities: _caps()))
        ..register(_reg('live-ok', capabilities: _caps(live: true)));
      final selector = PlayerAdapterSelector(registry);

      final vod = ProgressiveMediaSource.url(Uri.parse('https://example.com/movie.mp4'));

      expect(
        selector.scoreMedia(_lookup(registry, 'live-ok'), vod),
        selector.scoreMedia(_lookup(registry, 'vod-only'), vod),
      );
    });

    test('a live composite still prefers composite support over live support', () {
      // A live composite on a single-URL backend is refused outright, so
      // a backend that merely holds live open but takes one input is
      // worse than one that takes two: the composite bonus must outrank
      // the live one.
      final registry = PlayerAdapterRegistry()
        ..register(_reg('live-single', capabilities: _caps(live: true)))
        ..register(_reg('media3', capabilities: _caps(composite: CompositeSupport.native)));
      final selector = PlayerAdapterSelector(registry);

      final liveComposite = CompositeMediaSource(
        videoTracks: [_videoTrack('https://example.com/live.m4s')],
        live: true,
      );

      expect(selector.selectMedia(liveComposite)!.id, 'media3');
    });
  });
}
