import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/media_core.dart';

import 'package:media_core_live/media_core_live.dart';

PlayerSource _line(String url) {
  return PlayerSource(
    id: SourceId(url),
    uri: Uri.parse(url),
    type: SourceType.live,
    protocol: SourceProtocol.fromScheme(Uri.parse(url).scheme),
    mediaType: SourceMediaType.video,
    format: SourceFormat.fromUri(Uri.parse(url)),
  );
}

void main() {
  group('LiveSourceRequest', () {
    test('the first source is the one recovery starts from', () {
      final request = LiveSourceRequest(
        sources: [_line('https://a.example/live.flv'), _line('https://b.example/live.flv')],
      );

      expect(request.primary.uri.host, 'a.example');
      expect(request.hasAlternatives, isTrue);
    });

    test('a single line has no alternative', () {
      final request = LiveSourceRequest(sources: [_line('rtmp://a.example/live')]);

      expect(request.hasAlternatives, isFalse);
    });

    test('the source list cannot be mutated behind the request', () {
      final sources = [_line('https://a.example/live.flv')];
      final request = LiveSourceRequest(sources: sources);

      sources.add(_line('https://b.example/live.flv'));

      expect(request.sources, hasLength(1));
      expect(() => request.sources.add(_line('https://c.example/live.flv')), throwsUnsupportedError);
    });

    test('engine fallback stays undecided unless the caller declares it', () {
      // Whether a single line may escalate to another engine is the caller's
      // decision, not something inferred from the source count.
      expect(LiveSourceRequest(sources: [_line('https://a.example/l.flv')]).allowEngineFallback, isNull);
      expect(
        LiveSourceRequest(sources: [_line('https://a.example/l.flv')], allowEngineFallback: false).allowEngineFallback,
        isFalse,
      );
    });

    group('fromUrls', () {
      test('every line is declared live and gets the shared headers', () {
        final request = LiveSourceRequest.fromUrls(
          ['https://a.example/live.flv', 'https://b.example/live.m3u8'],
          headers: const {'Referer': 'https://a.example/'},
        );

        expect(request.sources, hasLength(2));
        for (final source in request.sources) {
          expect(source.isLive, isTrue);
          expect(source.headers?['Referer'], 'https://a.example/');
        }
      });

      test('protocol and format come from the URL, which is a guess', () {
        // The convenience path exists because most live-site APIs hand over
        // strings; this pins what it guesses so a change is a decision.
        final request = LiveSourceRequest.fromUrls(['rtmp://a.example/live']);

        expect(request.primary.protocol, SourceProtocol.rtmp);
      });

      test('an empty header map leaves headers unset', () {
        final request = LiveSourceRequest.fromUrls(['https://a.example/live.flv']);

        expect(request.primary.headers, isNull);
      });

      test('each line gets a distinct id', () {
        final request = LiveSourceRequest.fromUrls(['https://a.example/one.flv', 'https://a.example/two.flv']);

        expect(request.sources[0].id, isNot(request.sources[1].id));
      });
    });

    test('toString reports the shape, not the credentials', () {
      final request = LiveSourceRequest(sources: [_line('https://a.example/live.flv')], title: 'room 1');

      expect(request.toString(), contains('1 source(s)'));
      expect(request.toString(), contains('room 1'));
      expect(request.toString(), isNot(contains('headers')));
    });
  });

  group('LivePoolPolicy', () {
    test('the default keeps exactly one spare line warm', () {
      const policy = LivePoolPolicy.defaults;

      expect(policy.warmStandbyEnabled, isTrue);
      expect(policy.warmStandbyCount, 1);
    });

    test('a warm standby maps onto a pool that preloads one player', () {
      final config = const LivePoolPolicy(warmStandbyCount: 2).toPoolConfig();

      expect(config.preloadCount, 2);
      expect(config.keepWarm, isTrue);
      expect(config.warmSize, 3);
      expect(config.maxActivePlayers, 1);
    });

    test('disabling the standby preloads nothing', () {
      // A live line kept warm for minutes is bandwidth for a stream nobody
      // watches, so "off" has to mean off rather than "one anyway".
      final config = const LivePoolPolicy(warmStandbyEnabled: false).toPoolConfig();

      expect(config.preloadCount, 0);
      expect(config.keepWarm, isFalse);
      expect(config.warmSize, 0);
    });

    test('the idle release window is carried through', () {
      final config = const LivePoolPolicy(releaseIdleAfter: Duration(seconds: 3)).toPoolConfig();

      expect(config.idleTimeout, const Duration(seconds: 3));
    });

    test('copyWith keeps every field it is not told to change', () {
      const policy = LivePoolPolicy(
        warmStandbyEnabled: false,
        warmStandbyCount: 3,
        releaseIdleAfter: Duration(seconds: 7),
      );

      final copied = policy.copyWith(warmStandbyCount: 1);

      expect(copied.warmStandbyEnabled, isFalse);
      expect(copied.warmStandbyCount, 1);
      expect(copied.releaseIdleAfter, const Duration(seconds: 7));
    });
  });

  group('LiveStallKind', () {
    test('every stall kind is an inference, not a backend error code', () {
      // The controller maps each kind onto a PlayerFailure; keeping the two
      // apart is what lets a watchdog add a detector without inventing an
      // error code the rest of the framework has to learn.
      expect(LiveStallKind.values, hasLength(7));
      expect(
        LiveStallKind.values,
        containsAll(<LiveStallKind>[
          LiveStallKind.sourceReadyTimeout,
          LiveStallKind.unexpectedPauseResumed,
          LiveStallKind.unexpectedPauseResumeFailed,
          LiveStallKind.unexpectedPauseTimeout,
          LiveStallKind.bufferingStallTimeout,
          LiveStallKind.videoFrameStallTimeout,
          LiveStallKind.positionStallTimeout,
        ]),
      );
    });
  });
}
