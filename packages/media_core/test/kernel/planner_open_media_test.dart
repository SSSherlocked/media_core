import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/adapter/composite_support.dart';
import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/event/player_event_bus.dart';
import 'package:media_core/kernel/kernel_options.dart';
import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/kernel/player_kernel.dart';
import 'package:media_core/planning/media_source_plan.dart';
import 'package:media_core/planning/media_source_planner.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_source_bridge.dart';
import 'package:media_core/source/media_track.dart';
import 'package:media_core/source/media_track_type.dart';
import 'package:media_core/testing/fake_player_adapter.dart';
import 'package:media_core/testing/test_player_factory.dart';

PlayerAdapterRegistration _reg(String id, {required PlayerAdapterCapabilities capabilities, int priority = 0}) =>
    PlayerAdapterRegistration(
      id: id,
      capabilities: capabilities,
      factory: TestPlayerFactory.fakeAdapterFactory(),
      priority: priority,
    );

MediaTrack _videoTrack(String url) => MediaTrack(uri: Uri.parse(url), kind: MediaTrackType.video);

MediaTrack _audioTrack(String url) => MediaTrack(uri: Uri.parse(url), kind: MediaTrackType.audio);

void main() {
  group('PlayerKernel.planFor', () {
    test('returns a DirectPlan when progressive is fed to any backend', () {
      final kernel = PlayerKernel()..registerBackend(_reg('fake', capabilities: const PlayerAdapterCapabilities()));

      final outcome = kernel.planFor(ProgressiveMediaSource(track: _videoTrack('https://example.com/v.mp4')));

      expect(outcome.registration.id, 'fake');
      expect(outcome.plan, isA<DirectPlan>());
    });

    test('prefers the composite-capable backend and reports the mode', () {
      final kernel = PlayerKernel()
        ..registerBackend(_reg('plain', capabilities: const PlayerAdapterCapabilities()))
        ..registerBackend(
          _reg('media3', capabilities: const PlayerAdapterCapabilities(compositeSupport: CompositeSupport.native)),
        );

      final outcome = kernel.planFor(
        CompositeMediaSource(
          videoTracks: [_videoTrack('https://example.com/v.m4s')],
          audioTracks: [_audioTrack('https://example.com/a.m4s')],
        ),
      );

      expect(outcome.registration.id, 'media3');
      expect(outcome.plan, isA<CompositePlan>());
      expect((outcome.plan as CompositePlan).mode, CompositeSupport.native);
    });

    test('honours preferredBackend even when its capabilities differ from the best match', () {
      final kernel = PlayerKernel()
        ..registerBackend(
          _reg('media3', capabilities: const PlayerAdapterCapabilities(compositeSupport: CompositeSupport.native)),
        )
        ..registerBackend(_reg('fijk', capabilities: const PlayerAdapterCapabilities()));

      final outcome = kernel.planFor(
        CompositeMediaSource(videoTracks: [_videoTrack('https://example.com/v.m4s')]),
        preferredBackend: 'fijk',
      );

      expect(outcome.registration.id, 'fijk');
      expect(outcome.plan, isA<UnsupportedPlan>());
    });

    test('never throws on UnsupportedPlan; a caller decides what to do', () {
      final kernel = PlayerKernel()..registerBackend(_reg('fijk', capabilities: const PlayerAdapterCapabilities()));

      final outcome = kernel.planFor(CompositeMediaSource(videoTracks: [_videoTrack('https://example.com/v.m4s')]));

      expect(outcome.plan, isA<UnsupportedPlan>());
    });
  });

  group('PlayerHandle.openMedia', () {
    test('progressive source bridges to open() without a plan failure', () async {
      final adapter = FakePlayerAdapter(id: 'fake-1');
      final handle = _handle(adapter);

      await handle.initialize();

      await handle.openMedia(ProgressiveMediaSource(track: _videoTrack('https://example.com/v.mp4')), autoPlay: false);

      expect(adapter.openedSources, hasLength(1));
      final opened = adapter.openedSources.single;
      expect(opened.uri.toString(), 'https://example.com/v.mp4');
      expect(MediaSourceBridge.fromPlayerSource(opened), isA<ProgressiveMediaSource>());
    });

    test('composite source is preserved in the opened PlayerSource metadata', () async {
      final adapter = FakePlayerAdapter(id: 'fake-native');
      final handle = _handle(
        adapter,
        capabilities: const PlayerAdapterCapabilities(compositeSupport: CompositeSupport.native),
      );

      await handle.initialize();

      final composite = CompositeMediaSource(
        videoTracks: [_videoTrack('https://example.com/v.m4s')],
        audioTracks: [_audioTrack('https://example.com/a.m4s')],
      );

      await handle.openMedia(composite, autoPlay: false);

      final opened = adapter.openedSources.single;
      expect(MediaSourceBridge.compositeFromPlayerSource(opened), composite);
    });

    test('composite on a none backend throws UnsupportedError', () async {
      final handle = _handle(FakePlayerAdapter(id: 'fijk-like'));

      await handle.initialize();

      expect(
        () => handle.openMedia(
          CompositeMediaSource(
            videoTracks: [_videoTrack('https://example.com/v.m4s')],
            audioTracks: [_audioTrack('https://example.com/a.m4s')],
          ),
        ),
        throwsA(isA<UnsupportedError>().having((e) => e.message, 'message', contains('composite'))),
      );
    });

    test('custom planner is consulted instead of the default', () async {
      final stubPlanner = _StubPlanner(const UnsupportedPlan('stubbed'));
      final handle = _handle(FakePlayerAdapter(id: 'stub'), planner: stubPlanner);

      await handle.initialize();

      await expectLater(
        handle.openMedia(ProgressiveMediaSource(track: _videoTrack('https://example.com/v.mp4'))),
        throwsA(isA<UnsupportedError>()),
      );
      expect(stubPlanner.calls, hasLength(1));
    });
  });

  group('PlayerHandle.timeline', () {
    test('exposes the aligned presentation timeline of the open media', () async {
      final adapter = FakePlayerAdapter(id: 'mpv-like');
      final handle = _handle(
        adapter,
        capabilities: const PlayerAdapterCapabilities(compositeSupport: CompositeSupport.externalAudio),
      );
      await handle.initialize();

      await handle.openMedia(
        CompositeMediaSource(
          videoTracks: [
            MediaTrack(
              uri: Uri.parse('https://example.com/v.m4s'),
              kind: MediaTrackType.video,
              startOffset: const Duration(milliseconds: 40),
            ),
          ],
          audioTracks: [_audioTrack('https://example.com/a.m4s')],
        ),
        autoPlay: false,
      );

      final timeline = handle.timeline;
      expect(timeline, isNotNull);
      // The audio track anchors the clock; the video trails by 40 ms.
      expect(timeline!.primary!.track.kind, MediaTrackType.video);
      expect(timeline.primary!.offset, const Duration(milliseconds: 40));
      final audio = timeline.tracks.firstWhere((t) => t.track.kind == MediaTrackType.audio);
      expect(audio.offset, Duration.zero);
    });

    test('is null for a plain PlayerSource that never crossed the bridge', () async {
      final handle = _handle(FakePlayerAdapter(id: 'plain'));
      expect(handle.timeline, isNull);
    });
  });
}

PlayerHandle _handle(
  FakePlayerAdapter adapter, {
  PlayerAdapterCapabilities capabilities = const PlayerAdapterCapabilities(),
  MediaSourcePlanner? planner,
}) {
  return PlayerHandle(
    player: TestPlayerFactory.player(1),
    adapter: adapter,
    registration: PlayerAdapterRegistration(
      id: adapter.id,
      factory: TestPlayerFactory.fakeAdapterFactory(),
      capabilities: capabilities,
    ),
    adapterContext: TestPlayerFactory.context(),
    eventBus: PlayerEventBus(),
    options: const KernelOptions(),
    planner: planner,
  );
}

class _StubPlanner implements MediaSourcePlanner {
  _StubPlanner(this._result);
  final MediaSourcePlan _result;
  final calls = <MediaSource>[];

  @override
  MediaSourcePlan plan(MediaSource source, PlayerAdapterCapabilities capabilities) {
    calls.add(source);
    return _result;
  }
}
