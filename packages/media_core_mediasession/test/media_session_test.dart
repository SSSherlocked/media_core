import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core/testing/fake_player_adapter.dart';
import 'package:media_core/testing/test_player_factory.dart';
import 'package:media_core_mediasession/media_core_mediasession.dart';

void main() {
  group('MediaSessionConfig', () {
    test('every default icon is an Android `type/name` resource string', () {
      const config = MediaSessionConfig();
      final icons = <String>[
        config.playIcon,
        config.pauseIcon,
        config.stopIcon,
        config.previousIcon,
        config.nextIcon,
        config.rewindIcon,
        config.fastForwardIcon,
      ];
      for (final icon in icons) {
        // audio_service's getResourceId splits on '/' and indexes [1]; a bare
        // name crashes setState on every publish, so the defaults must be
        // full resource strings.
        expect(icon, contains('/'), reason: '$icon must be type/name');
      }
    });

    test('the video variant keeps seek controls and widens the compact row', () {
      const music = MediaSessionConfig();
      const video = MediaSessionConfig.video();

      expect(video.showSeekButtons, isTrue);
      expect(video.seekStep, const Duration(seconds: 10));
      // The queue-less layout has one more visible control than music's pair.
      expect(video.androidCompactActionIndices, const <int>[0, 1, 2]);
      expect(music.androidCompactActionIndices, const <int>[0, 1]);
      expect(video.androidNotificationChannelId, isNot(music.androidNotificationChannelId));
    });

    test('duck factor is a real multiplier default', () {
      const config = MediaSessionConfig();
      expect(config.duckFactor, greaterThan(0));
      expect(config.duckFactor, lessThan(1));
    });
  });

  group('MediaSessionItem', () {
    test('copyWith replaces only the named fields', () {
      const item = MediaSessionItem(id: 'm1', title: 'A', album: 'B', artist: 'C', duration: Duration(minutes: 1));
      final next = item.copyWith(title: 'A2', artUri: Uri.parse('https://host/art.png'));

      expect(next.id, 'm1');
      expect(next.title, 'A2');
      expect(next.album, 'B');
      expect(next.artist, 'C');
      expect(next.duration, const Duration(minutes: 1));
      expect(next.artUri, Uri.parse('https://host/art.png'));
    });

    test('toMediaItem carries every field across', () {
      const item = MediaSessionItem(id: 'm2', title: 'T', album: 'AL', artist: 'AR', duration: Duration(seconds: 5));
      final media = item.toMediaItem();

      expect(media.id, 'm2');
      expect(media.title, 'T');
      expect(media.album, 'AL');
      expect(media.artist, 'AR');
      expect(media.duration, const Duration(seconds: 5));
      expect(media.artUri, isNull);
    });
  });

  group('MediaSessionHandler', () {
    MediaSessionHandler handler({
      Future<void> Function()? onNext,
      Future<void> Function()? onPrevious,
      Future<void> Function(int index)? onSkipToQueueItem,
      Future<void> Function(double rate)? onSetSpeed,
    }) {
      return MediaSessionHandler(
        onPlay: () async {},
        onPause: () async {},
        onSeek: (_) async {},
        onStop: () async {},
        onNext: onNext,
        onPrevious: onPrevious,
        onSkipToQueueItem: onSkipToQueueItem,
        onSetSpeed: onSetSpeed,
      );
    }

    test('transport commands route to the supplied callbacks', () async {
      final log = <String>[];
      final h = MediaSessionHandler(
        onPlay: () async => log.add('play'),
        onPause: () async => log.add('pause'),
        onSeek: (p) async => log.add('seek:${p.inSeconds}'),
        onStop: () async => log.add('stop'),
      );

      await h.play();
      await h.pause();
      await h.seek(const Duration(seconds: 33));

      expect(log, <String>['play', 'pause', 'seek:33']);
    });

    test('skip capabilities follow the installed handlers', () {
      expect(handler().canSkipToNext, isFalse);
      expect(handler().canSkipToPrevious, isFalse);
      expect(handler(onNext: () async {}).canSkipToNext, isTrue);
      expect(handler(onPrevious: () async {}).canSkipToPrevious, isTrue);
    });

    test('an installed skip handler receives the command', () async {
      final log = <String>[];
      final h = handler(
        onNext: () async => log.add('next'),
        onPrevious: () async => log.add('previous'),
        onSkipToQueueItem: (i) async => log.add('jump:$i'),
        onSetSpeed: (r) async => log.add('speed:$r'),
      );

      await h.skipToNext();
      await h.skipToPrevious();
      await h.skipToQueueItem(2);
      await h.setSpeed(1.5);

      expect(log, <String>['next', 'previous', 'jump:2', 'speed:1.5']);
    });

    test('publishState mirrors the snapshot into the platform state', () async {
      final h = handler()
        ..publishState(
          const MediaSessionState(
            playing: true,
            position: Duration(seconds: 4),
            duration: Duration(minutes: 1),
            speed: 1,
          ),
          controls: const <MediaControl>[MediaControl.play],
        );
      await pumpEventQueue();

      final state = h.playbackState.value;
      expect(state.playing, isTrue);
      expect(state.updatePosition, const Duration(seconds: 4));
      expect(state.bufferedPosition, const Duration(minutes: 1));
      expect(state.speed, 1.0);
      expect(state.controls, contains(MediaControl.play));
    });

    test('publishIdle parks the surface without removing it', () async {
      final h = handler()..publishIdle();
      await pumpEventQueue();

      expect(h.playbackState.value.processingState, AudioProcessingState.idle);
      expect(h.playbackState.value.playing, isFalse);
    });

    test('publishQueue sets the list and optionally the current item', () async {
      final h = handler();
      const a = MediaSessionItem(id: 'a', title: 'A');
      const b = MediaSessionItem(id: 'b', title: 'B');

      h.publishQueue(const <MediaSessionItem>[a, b]);
      await pumpEventQueue();
      expect(h.queue.value.map((e) => e.id), <String>['a', 'b']);
      expect(h.mediaItem.value, isNull); // no index claimed: nothing becomes current

      h.publishQueue(const <MediaSessionItem>[a, b], index: 1);
      await pumpEventQueue();
      expect(h.mediaItem.value?.id, 'b');

      h.clearMediaItem();
      await pumpEventQueue();
      expect(h.mediaItem.value, isNull);
    });
  });

  group('the task the viewer swiped away', () {
    ({MediaSessionHandler handler, List<String> log}) swipedAway({required bool stopOnTaskRemoved}) {
      final log = <String>[];
      final handler = MediaSessionHandler(
        onPlay: () async {},
        onPause: () async {},
        onSeek: (_) async {},
        onStop: () async => log.add('stop'),
        stopOnTaskRemoved: stopOnTaskRemoved,
      );

      return (handler: handler, log: log);
    }

    test('asking for a stop on removal gets one', () async {
      final run = swipedAway(stopOnTaskRemoved: true);
      await run.handler.onTaskRemoved();

      expect(run.log, <String>['stop']);
    });

    test('by default the audio outlives the recents entry', () async {
      final run = swipedAway(stopOnTaskRemoved: false);
      await run.handler.onTaskRemoved();

      expect(run.log, isEmpty, reason: 'a music app keeps playing from the notification');
    });

    test('the handler holds the flag the constructor was given', () {
      expect(swipedAway(stopOnTaskRemoved: true).handler.stopOnTaskRemoved, isTrue);
      expect(swipedAway(stopOnTaskRemoved: false).handler.stopOnTaskRemoved, isFalse);
    });
  });

  group('MediaSessionDriver publish cadence', () {
    Future<({MediaSessionHandler handler, FakePlayerAdapter adapter, PlayerHandle handle})> rig() async {
      final adapter = FakePlayerAdapter();
      final handle = PlayerHandle(
        player: TestPlayerFactory.player(1),
        adapter: adapter,
        registration: PlayerAdapterRegistration(
          id: 'fake',
          factory: TestPlayerFactory.fakeAdapterFactory(),
          capabilities: const FakePlayerAdapterBehavior().capabilities,
        ),
        adapterContext: TestPlayerFactory.context(),
        eventBus: PlayerEventBus(),
        options: const KernelOptions(),
      );
      final handler = MediaSessionHandler(
        onPlay: () async {},
        onPause: () async {},
        onSeek: (_) async {},
        onStop: () async {},
      );
      final driver = MediaSessionDriver(handler: handler);
      addTearDown(driver.dispose);

      await handle.initialize();
      await handle.open(
        PlayerSource(
          id: SourceId('song'),
          uri: Uri.parse('https://example.com/song.m4a'),
          protocol: SourceProtocol.https,
          format: SourceFormat.mp4,
          title: 'Song',
        ),
      );
      driver.setActive(handle);
      await pumpEventQueue();
      return (handler: handler, adapter: adapter, handle: handle);
    }

    test('position-only ticks reach the notification once a second at most', () async {
      final started = await rig();
      final published = <PlaybackState>[];
      final subscription = started.handler.playbackState.listen(published.add);
      addTearDown(subscription.cancel);
      // The state stream is a behaviour subject: subscribing replays the value
      // already published. Drop that replay, then measure from a known clock.
      await pumpEventQueue();
      final baseline = published.single.updatePosition;
      published.clear();

      for (final ms in <int>[200, 400, 600, 800]) {
        started.adapter.emitPosition(baseline + Duration(milliseconds: ms));
        await pumpEventQueue();
      }
      expect(published, isEmpty, reason: 'sub-second drift redraws nothing the lock screen would show');

      started.adapter.emitPosition(baseline + const Duration(milliseconds: 1100));
      await pumpEventQueue();
      expect(published, hasLength(1), reason: 'a second of media time is worth a publish');

      // A seek backwards is a different timeline, not a step along this one.
      published.clear();
      started.adapter.emitPosition(Duration.zero);
      await pumpEventQueue();
      expect(published, hasLength(1));
    });

    test('a structural change is never held back by the position window', () async {
      final started = await rig();
      final published = <PlaybackState>[];
      final subscription = started.handler.playbackState.listen(published.add);
      addTearDown(subscription.cancel);
      // The handle was opened without autoplay, so pause is only structural
      // once something is actually playing.
      started.adapter.emitPlaying();
      await pumpEventQueue();
      published.clear();

      started.adapter.emitPaused();
      await pumpEventQueue();

      expect(published, hasLength(1));
      expect(published.last.playing, isFalse);
      expect(
        published.last.controls.map((control) => control.action.name),
        contains('play'),
        reason: 'the pause button has to appear the moment playback stops',
      );
    });
  });

  group('MediaSessionHandler.compactIndicesFor', () {
    test('derives from the control list instead of a parallel constant', () {
      expect(MediaSessionHandler.compactIndicesFor(const <MediaControl>[]), isEmpty);
      expect(MediaSessionHandler.compactIndicesFor(const <MediaControl>[MediaControl.play]), const <int>[0]);
      expect(
        MediaSessionHandler.compactIndicesFor(const <MediaControl>[
          MediaControl.play,
          MediaControl.pause,
          MediaControl.stop,
        ]),
        const <int>[0, 1], // more than two controls: only the first two stay compact
      );
    });
  });
}
