import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core/testing/fake_player_adapter.dart';
import 'package:media_core/testing/test_player_factory.dart';
import 'package:media_core_audio/media_core_audio.dart';

/// A source that streams a test URL; the queue path needs one to open a player.
final class _StreamSource extends MusicSource {
  @override
  String get id => 'test';

  @override
  String get name => 'Test';

  @override
  Future<TrackSource> resolveTrackSource(MusicTrack track, {MusicQuality? quality}) async {
    return TrackSource(uri: Uri.parse('https://example.com/${track.id}.m4a'));
  }
}

final class _Rig {
  _Rig(this.player, this.kernel, this.driver, this.handler);

  final AudioPlaybackController player;
  final PlayerKernel kernel;
  final MediaSessionDriver driver;
  final MediaSessionHandler handler;

  Future<void> play() async {
    await player.setQueue(<MusicTrack>[const MusicTrack(id: 'song-1', title: '第一首', sourceId: 'test')]);

    await pumpEventQueue();
  }
}

Future<_Rig> _rig({PlayerConfig? playerConfig}) async {
  final kernel = PlayerKernel()
    ..registerBackend(
      PlayerAdapterRegistration(
        id: 'fake',
        factory: TestPlayerFactory.fakeAdapterFactory(),
        capabilities: const FakePlayerAdapterBehavior().capabilities,
      ),
    );

  final source = _StreamSource();
  final handler = MediaSessionHandler(
    onPlay: () async {},
    onPause: () async {},
    onSeek: (_) async {},
    onStop: () async {},
  );
  final driver = MediaSessionDriver(handler: handler);
  final player = AudioPlaybackController(
    kernel,
    registry: MusicSourceRegistry(<MusicSource>[source]),
    playerConfig: playerConfig,
  );

  final rig = _Rig(player, kernel, driver, handler);

  addTearDown(() async {
    await player.dispose();
    await driver.dispose();
    await kernel.dispose();
  });

  return rig;
}

/// Drives the framework's app-lifecycle signal the way the platform does.
Future<void> _backgrounded() async {
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await pumpEventQueue();
}

Future<void> _foregrounded() async {
  WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await pumpEventQueue();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the background switch is a real switch', () {
    test('a paused app pauses the player when background playback is off', () async {
      final rig = await _rig();
      final binding = MusicBackgroundBinding(rig.player, rig.driver)..attach();
      addTearDown(binding.dispose);

      await rig.play();

      expect(rig.player.state.playing, isTrue, reason: 'precondition: something is playing');

      await _backgrounded();

      expect(
        rig.player.state.playing,
        isFalse,
        reason:
            'the default policy is "no background playback", and turning it off '
            'has to actually stop the engine — this used to be a no-op because the '
            'app-wide lifecycle driver existed but nothing installed it',
      );
      expect(
        rig.handler.playbackState.value.playing,
        isFalse,
        reason: 'the surface follows what the player really does, not what it last said',
      );

      await _foregrounded();

      expect(rig.player.state.playing, isFalse, reason: 'returning must not restart audio by itself');
    });

    test('a paused app keeps playing when the host allows background playback', () async {
      // The per-player answer: the kernel pauses what is playing, and this
      // player says it is the exception.
      final rig = await _rig(playerConfig: const PlayerConfig(pauseWhenBackgrounded: false));
      final binding = MusicBackgroundBinding(rig.player, rig.driver)..attach();
      addTearDown(binding.dispose);

      await rig.play();

      await _backgrounded();

      expect(rig.player.state.playing, isTrue, reason: 'this is the podcast case');
      expect(rig.handler.playbackState.value.playing, isTrue);
    });
  });

  group('turning the binding off takes the surface with it', () {
    test('detach parks the media surface it published', () async {
      final rig = await _rig();
      final binding = MusicBackgroundBinding(rig.player, rig.driver)..attach();
      addTearDown(binding.dispose);

      await rig.play();

      expect(rig.driver.active, same(rig.player.handle));
      expect(rig.handler.mediaItem.value, isNotNull);

      binding.detach();

      // A surface left claiming playback is what keeps Android's media
      // foreground service alive — the "background playback that cannot be
      // turned off" the binding used to leave behind.
      expect(rig.driver.active, isNull);
      expect(rig.handler.mediaItem.value, isNull);
      expect(rig.handler.playbackState.value.playing, isFalse);
      expect(rig.handler.playbackState.value.processingState, AudioProcessingState.idle);

      expect(rig.player.state.playing, isTrue, reason: 'the job itself is untouched by detach');
    });

    test('detach leaves a surface it did not publish alone', () async {
      final rig = await _rig();
      final binding = MusicBackgroundBinding(rig.player, rig.driver)..attach();
      addTearDown(binding.dispose);

      await rig.play();

      // Another owner (a video player the kernel activated) took the surface.
      final other = PlayerHandle(
        player: TestPlayerFactory.player(2),
        adapter: TestPlayerFactory.fakeAdapter(),
        registration: PlayerAdapterRegistration(
          id: 'fake',
          factory: TestPlayerFactory.fakeAdapterFactory(),
          capabilities: const FakePlayerAdapterBehavior().capabilities,
        ),
        adapterContext: TestPlayerFactory.context(),
        eventBus: PlayerEventBus(),
        options: const KernelOptions(),
      );
      addTearDown(other.dispose);

      rig.driver.setActive(other);

      binding.detach();

      expect(
        rig.driver.active,
        same(other),
        reason: 'the music binding may not take another player off the system surface',
      );
    });
  });

  test('the transports come back with a re-attach', () async {
    final rig = await _rig();
    final binding = MusicBackgroundBinding(rig.player, rig.driver);
    addTearDown(binding.dispose);

    await rig.play();

    binding.attach();
    expect(rig.driver.skipToNextHandler, isNotNull);

    binding.detach();
    expect(rig.driver.skipToNextHandler, isNull);

    // Re-attaching has to restore them: detach is not teardown for this object.
    binding.attach();
    expect(rig.driver.skipToNextHandler, isNotNull);
    expect(rig.driver.active, same(rig.player.handle));
  });
}
