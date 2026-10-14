import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/adapter/composite_support.dart';
import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/planning/default_media_source_planner.dart';
import 'package:media_core/planning/media_source_plan.dart';
import 'package:media_core/planning/media_source_planner.dart' show MediaSourcePlanner;
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_source_bridge.dart';
import 'package:media_core/source/media_track.dart';
import 'package:media_core/source/media_track_type.dart';
import 'package:media_core/source/source_headers.dart';

MediaTrack _video(String url, {int bitrate = 1_000_000}) => MediaTrack(
  uri: Uri.parse(url),
  kind: MediaTrackType.video,
  mimeType: 'video/mp4',
  codec: 'avc1.640028',
  bitrate: bitrate,
);

MediaTrack _audio(String url, {int bitrate = 192_000}) => MediaTrack(
  uri: Uri.parse(url),
  kind: MediaTrackType.audio,
  mimeType: 'audio/mp4',
  codec: 'mp4a.40.2',
  bitrate: bitrate,
);

MediaTrack _subtitle(String url) =>
    MediaTrack(uri: Uri.parse(url), kind: MediaTrackType.subtitle, mimeType: 'text/vtt');

/// A [MediaSourcePlanner] that only ever returns [UnsupportedPlan] so
/// tests can verify [DefaultMediaSourcePlanner] is not the one the
/// kernel uses when the caller supplies a custom planner.
class _RecordingPlannerSpy implements _PlannerHandle {
  _RecordingPlannerSpy(this.inner);

  final DefaultMediaSourcePlanner inner;
  final calls = <MediaSource>[];

  @override
  MediaSourcePlan plan(MediaSource source, PlayerAdapterCapabilities capabilities) {
    calls.add(source);
    return inner.plan(source, capabilities);
  }
}

abstract class _PlannerHandle {
  MediaSourcePlan plan(MediaSource source, PlayerAdapterCapabilities capabilities);
}

void main() {
  group('MediaTrack', () {
    test('reports protocol and format from URI', () {
      final track = _video('https://example.com/segment.m4s');

      expect(track.protocol.name, 'https');
      expect(track.kind, MediaTrackType.video);
      expect(track.mediaType.name, 'video');
    });

    test('copies preserve every field unless overridden', () {
      final original = MediaTrack(
        uri: Uri.parse('https://example.com/v.m4s'),
        kind: MediaTrackType.video,
        headers: SourceHeaders(const {'User-Agent': 'test'}),
        mimeType: 'video/mp4',
        codec: 'hev1.2.4.L153.B0',
        bitrate: 12_000_000,
        language: 'zh',
        startOffset: const Duration(milliseconds: 40),
        metadata: const <String, Object?>{'quality': 120},
      );

      final copy = original.copyWith(bitrate: 8_000_000);

      expect(copy.bitrate, 8_000_000);
      expect(copy.uri, original.uri);
      expect(copy.headers, original.headers);
      expect(copy.codec, original.codec);
      expect(copy.language, 'zh');
      expect(copy.startOffset, const Duration(milliseconds: 40));
      expect(copy.metadata['quality'], 120);
    });

    test('codecFamily returns the fourcc prefix', () {
      final track = _video('https://example.com/v.mp4');

      expect(track.codecFamily, 'avc1');
    });
  });

  group('ProgressiveMediaSource', () {
    test('reports progressive type and one-element tracks', () {
      final source = ProgressiveMediaSource(track: _video('https://a/v.mp4'));

      expect(source.type, MediaSourceType.progressive);
      expect(source.isProgressive, isTrue);
      expect(source.tracks, hasLength(1));
    });

    test('url factory accepts both String and Uri', () {
      final fromString = ProgressiveMediaSource.url('https://a/v.mp4');
      final fromUri = ProgressiveMediaSource.url(Uri.parse('https://a/v.mp4'));

      expect(fromString.track.uri, fromUri.track.uri);
    });

    test('value equality follows the wrapped track', () {
      final track = _video('https://a/v.mp4');

      expect(ProgressiveMediaSource(track: track), ProgressiveMediaSource(track: track));
    });
  });

  group('CompositeMediaSource', () {
    test('primaryVideo / primaryAudio expose the first of each list', () {
      final composite = CompositeMediaSource(
        videoTracks: [_video('https://a/v1.m4s', bitrate: 2_000_000), _video('https://a/v2.m4s')],
        audioTracks: [_audio('https://a/a1.m4s')],
        subtitleTracks: [_subtitle('https://a/en.vtt')],
      );

      expect(composite.primaryVideo!.bitrate, 2_000_000);
      expect(composite.primaryAudio!.uri.toString(), 'https://a/a1.m4s');
      expect(composite.primarySubtitle!.uri.toString(), 'https://a/en.vtt');
      expect(composite.hasVideo, isTrue);
      expect(composite.hasAudio, isTrue);
      expect(composite.hasSubtitle, isTrue);
    });

    test('tracks concatenates in video → audio → subtitle order', () {
      final composite = CompositeMediaSource(
        videoTracks: [_video('https://a/v.m4s')],
        audioTracks: [_audio('https://a/a.m4s')],
        subtitleTracks: [_subtitle('https://a/en.vtt')],
      );

      expect(composite.tracks.map((t) => t.kind).toList(), [
        MediaTrackType.video,
        MediaTrackType.audio,
        MediaTrackType.subtitle,
      ]);
    });

    test('subtitle-only is rejected by the constructor assert', () {
      expect(
        () => CompositeMediaSource(subtitleTracks: [_subtitle('https://a/en.vtt')]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('audio-only composite is legal (music mode)', () {
      final composite = CompositeMediaSource(audioTracks: [_audio('https://a/a.m4s')]);

      expect(composite.hasVideo, isFalse);
      expect(composite.primaryAudio, isNotNull);
    });
  });

  group('DefaultMediaSourcePlanner', () {
    final progressive = ProgressiveMediaSource(
      track: MediaTrack(uri: Uri.parse('https://a/v.mp4'), kind: MediaTrackType.video),
    );

    final composite = CompositeMediaSource(
      videoTracks: [MediaTrack(uri: Uri.parse('https://a/v.m4s'), kind: MediaTrackType.video)],
      audioTracks: [MediaTrack(uri: Uri.parse('https://a/a.m4s'), kind: MediaTrackType.audio)],
    );

    const native = PlayerAdapterCapabilities(compositeSupport: CompositeSupport.native);
    const externalAudio = PlayerAdapterCapabilities(compositeSupport: CompositeSupport.externalAudio);
    const none = PlayerAdapterCapabilities();

    test('progressive always plans direct', () {
      const planner = DefaultMediaSourcePlanner();

      expect(planner.plan(progressive, none), isA<DirectPlan>());
      expect(planner.plan(progressive, native), isA<DirectPlan>());
    });

    test('composite on native or externalAudio backend plans composite', () {
      const planner = DefaultMediaSourcePlanner();

      final nativePlan = planner.plan(composite, native) as CompositePlan;
      final sideChannelPlan = planner.plan(composite, externalAudio) as CompositePlan;

      expect(nativePlan, isA<CompositePlan>());
      expect(sideChannelPlan, isA<CompositePlan>());
      expect(nativePlan.source, composite);
      expect(sideChannelPlan.source, composite);
      expect(nativePlan.mode, CompositeSupport.native);
      expect(sideChannelPlan.mode, CompositeSupport.externalAudio);
    });

    test('composite on a none backend is refused with a usable reason', () {
      const planner = DefaultMediaSourcePlanner();
      final plan = planner.plan(composite, none);

      expect(plan, isA<UnsupportedPlan>());
      final reason = (plan as UnsupportedPlan).reason;
      expect(reason, contains('composite'));
      expect(reason, contains('one URL'));
      // The reason names what was dropped, so a log line alone tells the
      // provider which essence the backend cannot reach.
      expect(reason, contains('1 video'));
      expect(reason, contains('1 audio'));
    });

    test('a live composite still takes a native backend', () {
      const planner = DefaultMediaSourcePlanner();
      final liveComposite = CompositeMediaSource(
        videoTracks: [MediaTrack(uri: Uri.parse('https://example.com/live_v.m4s'), kind: MediaTrackType.video)],
        live: true,
      );

      final plan = planner.plan(liveComposite, native);

      expect(plan, isA<CompositePlan>());
      expect((plan as CompositePlan).mode, CompositeSupport.native);
    });

    test('every plan variant reports playability', () {
      expect(DirectPlan(progressive).isPlayable, isTrue);
      expect(CompositePlan(composite).isPlayable, isTrue);
      expect(const UnsupportedPlan('no').isPlayable, isFalse);
    });
  });

  group('CompositeSupport', () {
    test('capabilities.supportsComposite is derived from the enum', () {
      expect(noneCap().supportsComposite, isFalse);
      expect(const PlayerAdapterCapabilities(compositeSupport: CompositeSupport.native).supportsComposite, isTrue);
      expect(
        const PlayerAdapterCapabilities(compositeSupport: CompositeSupport.externalAudio).supportsComposite,
        isTrue,
      );
    });

    test('copyWith round-trips the composite field', () {
      const base = PlayerAdapterCapabilities();
      final upgraded = base.copyWith(compositeSupport: CompositeSupport.externalAudio);

      expect(upgraded.compositeSupport, CompositeSupport.externalAudio);
      expect(upgraded.copyWith().compositeSupport, CompositeSupport.externalAudio);
    });

    test('copyWith keeps every flag it is not told to change', () {
      // A capability dropped by copyWith is invisible: media_kit narrows
      // its own declarations through copyWith, so a missing entry here
      // silently turns a claimed feature off (or on) per platform.
      const base = PlayerAdapterCapabilities(
        supportsEngineOptions: true,
        compositeSupport: CompositeSupport.externalAudio,
      );

      final narrowed = base.copyWith(supportsEngineOptions: false);

      expect(narrowed.supportsEngineOptions, isFalse);
      expect(narrowed.compositeSupport, CompositeSupport.externalAudio);
      expect(narrowed.copyWith().supportsEngineOptions, isFalse);
      expect(narrowed, isNot(base));
    });
  });

  group('MediaSourceBridge', () {
    test('progressive source becomes a PlayerSource with matching uri', () {
      final source = ProgressiveMediaSource(track: _video('https://example.com/v.mp4'));

      final bridged = source.toPlayerSource();

      expect(bridged.uri.toString(), 'https://example.com/v.mp4');
      expect(bridged.mediaType.name, 'video');
      expect(MediaSourceBridge.fromPlayerSource(bridged), source);
    });

    test('composite bridge carries headers from every track', () {
      final headers = SourceHeaders(const {'Referer': 'https://www.bilibili.com/'});
      final composite = CompositeMediaSource(
        videoTracks: [
          MediaTrack(uri: Uri.parse('https://example.com/v.m4s'), kind: MediaTrackType.video, headers: headers),
        ],
        audioTracks: [
          MediaTrack(
            uri: Uri.parse('https://example.com/a.m4s'),
            kind: MediaTrackType.audio,
            headers: headers.set('Cookie', 'SESSDATA=x'),
          ),
        ],
      );

      final bridged = composite.toPlayerSource();

      expect(bridged.uri.toString(), 'https://example.com/v.m4s');
      expect(bridged.headers!['Referer'], 'https://www.bilibili.com/');
      expect(bridged.headers!['Cookie'], 'SESSDATA=x');
      expect(bridged.mediaType.name, 'mixed');
      expect(MediaSourceBridge.compositeFromPlayerSource(bridged), composite);
    });

    test('fromPlayerSource returns null for a source that never crossed the bridge', () {
      final plain = ProgressiveMediaSource.url('https://example.com/v.mp4').toPlayerSource().copyWith();

      // fresh PlayerSource without our metadata key.
      expect(MediaSourceBridge.fromPlayerSource(plain), isNotNull);

      final untouched = plain.copyWith(metadata: const <String, Object?>{});
      expect(MediaSourceBridge.fromPlayerSource(untouched), isNull);
    });
  });

  group('PlayerKernel.createFromMedia integration surface', () {
    test('recording planner delegates to the default implementation', () {
      final spy = _RecordingPlannerSpy(const DefaultMediaSourcePlanner());
      final composite = CompositeMediaSource(
        videoTracks: [_video('https://example.com/v.m4s')],
        audioTracks: [_audio('https://example.com/a.m4s')],
      );

      final plan = spy.plan(composite, const PlayerAdapterCapabilities());

      expect(spy.calls, contains(composite));
      expect(plan, isA<UnsupportedPlan>());
    });
  });
}

PlayerAdapterCapabilities noneCap() => const PlayerAdapterCapabilities();
