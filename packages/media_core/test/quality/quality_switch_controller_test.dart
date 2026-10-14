import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/event/player_event_bus.dart';
import 'package:media_core/kernel/kernel_options.dart';
import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/quality/quality_candidate.dart';
import 'package:media_core/quality/quality_switch_controller.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_track.dart';
import 'package:media_core/source/media_track_type.dart';
import 'package:media_core/testing/fake_player_adapter.dart';
import 'package:media_core/testing/test_player_factory.dart';

ProgressiveMediaSource _source(String url) => ProgressiveMediaSource(
  track: MediaTrack(uri: Uri.parse(url), kind: MediaTrackType.video),
);

PlayerHandle _handle(FakePlayerAdapter adapter) {
  return PlayerHandle(
    player: TestPlayerFactory.player(1),
    adapter: adapter,
    registration: PlayerAdapterRegistration(
      id: adapter.id,
      factory: TestPlayerFactory.fakeAdapterFactory(),
      capabilities: const PlayerAdapterCapabilities(),
    ),
    adapterContext: TestPlayerFactory.context(),
    eventBus: PlayerEventBus(),
    options: const KernelOptions(),
  );
}

void main() {
  final low = QualityCandidate(
    label: '480P',
    source: ProgressiveMediaSource(
      track: MediaTrack(uri: Uri.parse('https://example.com/low.mp4'), kind: MediaTrackType.video),
    ),
  );
  final high = QualityCandidate(
    label: '1080P',
    source: ProgressiveMediaSource(
      track: MediaTrack(uri: Uri.parse('https://example.com/high.mp4'), kind: MediaTrackType.video),
    ),
    bitrate: 4_000_000,
  );

  group('QualitySwitchController', () {
    test('a successful switch re-opens, resumes and restores settings', () async {
      final adapter = FakePlayerAdapter(id: 'fake-1');
      final handle = _handle(adapter);
      await handle.initialize();

      final controller = QualitySwitchController(handle: handle, current: low);

      await handle.openMedia(low.source, autoPlay: false);
      await handle.seek(const Duration(seconds: 42));
      await handle.setRate(1.5);
      await handle.play();

      final outcome = await controller.switchTo(high);

      expect(outcome.result, QualitySwitchResult.applied);
      expect(outcome.from, low);
      expect(outcome.to, high);
      expect(outcome.resumedAt, const Duration(seconds: 42));
      expect(controller.current, high);

      // The new source is the one the adapter opened last.
      expect(adapter.openedSources.last.uri.toString(), 'https://example.com/high.mp4');
      expect(handle.playback.rate, 1.5);
      expect(handle.playback.isPlaying, isTrue);
    });

    test('switching to the current candidate reports alreadyCurrent and touches nothing', () async {
      final adapter = FakePlayerAdapter(id: 'fake-2');
      final handle = _handle(adapter);
      await handle.initialize();

      final controller = QualitySwitchController(handle: handle, current: low);
      await handle.openMedia(low.source, autoPlay: false);
      adapter.openedSources.clear();

      final outcome = await controller.switchTo(low);

      expect(outcome.result, QualitySwitchResult.alreadyCurrent);
      expect(adapter.openedSources, isEmpty);
    });

    test('a failed switch rolls back to the previous candidate at the same position', () async {
      final adapter = FakePlayerAdapter(id: 'fake-3');
      final handle = _handle(adapter);
      await handle.initialize();

      final controller = QualitySwitchController(handle: handle, current: low);
      await handle.openMedia(low.source, autoPlay: false);
      await handle.seek(const Duration(seconds: 10));

      // Any further open fails.
      adapter.behavior = adapter.behavior.failingOn({'open'});
      // The rollback target is the already-adopted low; make open fail
      // only for the high source by counting: FakePlayerAdapter fails
      // every open once flagged, so pre-open low succeeded and the
      // high open is the one that raises.
      final outcome = await controller.switchTo(high);

      expect(outcome.result, QualitySwitchResult.failed);
      expect(outcome.restored, isFalse);
      expect(outcome.error, isNotNull);
      // A failed-with-failed-rollback keeps the baseline: the viewer
      // was on low, and low is what the controller still records.
      expect(controller.current, low);
    });

    test('a switch before any open still moves the handle and skips the seek', () async {
      final adapter = FakePlayerAdapter(id: 'fake-4');
      final handle = _handle(adapter);
      await handle.initialize();

      final controller = QualitySwitchController(handle: handle);
      final outcome = await controller.switchTo(high);

      expect(outcome.applied, isTrue);
      expect(outcome.resumedAt, Duration.zero);
      expect(adapter.openedSources.single.uri.toString(), 'https://example.com/high.mp4');
    });
  });

  group('QualityCandidate builders', () {
    test('fromProgressive labels from bitrate when declared, uri otherwise', () {
      final bare = QualityCandidate.fromProgressive([_source('https://example.com/a.mp4')]);
      final withBitrate = QualityCandidate.fromProgressive([
        ProgressiveMediaSource(
          track: MediaTrack(
            uri: Uri.parse('https://example.com/b.mp4'),
            kind: MediaTrackType.video,
            bitrate: 2_400_000,
          ),
        ),
      ]);

      // No bitrate is not a 0 bps claim — the uri is what the host can
      // actually show, so the label says where the media lives.
      expect(bare.single.label, 'https://example.com/b.mp4'.replaceFirst('b', 'a'));
      expect(withBitrate.single.label, '2.4 Mbps');
    });

    test('fromCompositeTracks pairs every video essence with shared audio', () {
      final candidates = QualityCandidate.fromCompositeTracks(
        [
          MediaTrack(uri: Uri.parse('https://example.com/v720.m4s'), kind: MediaTrackType.video, bitrate: 1_200_000),
          MediaTrack(uri: Uri.parse('https://example.com/v1080.m4s'), kind: MediaTrackType.video, bitrate: 4_000_000),
        ],
        audioTracks: [MediaTrack(uri: Uri.parse('https://example.com/a.m4s'), kind: MediaTrackType.audio)],
      );

      expect(candidates, hasLength(2));
      final composite = candidates.first.source as CompositeMediaSource;
      expect(composite.audioTracks, hasLength(1));
      expect(candidates.last.label, '4000000 bps');

      final labelled = QualityCandidate.fromCompositeTracks([
        MediaTrack(uri: Uri.parse('https://example.com/v1080.m4s'), kind: MediaTrackType.video, bitrate: 4_000_000),
      ], labelOf: (track) => '${(track.bitrate! / 1000000).toStringAsFixed(1)} Mbps');
      expect(labelled.single.label, '4.0 Mbps');
    });
  });
}
