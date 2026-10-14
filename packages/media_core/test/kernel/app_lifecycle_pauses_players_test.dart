import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core/testing/fake_player_adapter.dart';
import 'package:media_core/testing/test_player_factory.dart';

/// A kernel that selects the fake backend for everything.
PlayerKernel _kernel({bool pauseWhenBackgrounded = true}) {
  final kernel = PlayerKernel(options: KernelOptions(pauseWhenBackgrounded: pauseWhenBackgrounded))
    ..registerBackend(
      PlayerAdapterRegistration(
        id: 'fake',
        factory: TestPlayerFactory.fakeAdapterFactory(),
        capabilities: const FakePlayerAdapterBehavior().capabilities,
      ),
    );

  addTearDown(kernel.dispose);

  return kernel;
}

Future<PlayerHandle> _playing(
  PlayerKernel kernel, {
  required String id,
  bool play = true,
  PlayerConfig config = PlayerConfig.defaults,
}) async {
  final handle = await kernel.create(
    config: config,
    source: PlayerSource(
      id: SourceId(id),
      uri: Uri.parse('https://example.com/$id.mp4'),
      mediaType: SourceMediaType.video,
    ),
  );

  if (play) {
    await handle.play();
  }

  await pumpEventQueue();

  return handle;
}

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

  group('the app going to the background reaches the video players', () {
    test('every playing handle of the kernel stops', () async {
      final kernel = _kernel();

      final a = await _playing(kernel, id: 'a');
      final b = await _playing(kernel, id: 'b');

      expect(a.playback.isPlaying, isTrue);
      expect(b.playback.isPlaying, isTrue);

      await _backgrounded();

      expect(
        a.playback.isPlaying,
        isFalse,
        reason:
            'this is the gap the user reported: a video kept decoding with the '
            'app in the background, because the framework had a lifecycle driver '
            'class and nothing had ever installed it',
      );
      expect(b.playback.isPlaying, isFalse, reason: 'a wall or a warm window is several players');

      await _foregrounded();

      expect(a.playback.isPlaying, isFalse, reason: 'coming back must not press play for the viewer');
      expect(b.playback.isPlaying, isFalse);
    });

    test('a handle that asked to keep playing is left alone', () async {
      final kernel = _kernel();

      final narration = await _playing(
        kernel,
        id: 'narration',
        config: const PlayerConfig(pauseWhenBackgrounded: false),
      );
      final video = await _playing(kernel, id: 'video');

      await _backgrounded();

      expect(narration.playback.isPlaying, isTrue, reason: 'the per-player exception is honoured');
      expect(video.playback.isPlaying, isFalse);
    });

    test('an idle handle is not disturbed by the sweep', () async {
      final kernel = _kernel();

      final paused = await _playing(kernel, id: 'paused', play: false);
      final playing = await _playing(kernel, id: 'playing');

      await _backgrounded();

      expect(paused.playback.isPlaying, isFalse);
      expect(playing.playback.isPlaying, isFalse);
      // The idle player's engine was never told to pause: `deactivate` on a
      // handle that is not playing only records the lifecycle, it does not send
      // a command nobody asked for.
      expect((paused.adapter as FakePlayerAdapter).calls.where((call) => call == 'pause'), isEmpty);
      expect((playing.adapter as FakePlayerAdapter).calls, contains('pause'));
    });

    test('a kernel configured off observes nothing', () async {
      final kernel = _kernel(pauseWhenBackgrounded: false);

      final handle = await _playing(kernel, id: 'background-audio');

      await _backgrounded();

      expect(handle.playback.isPlaying, isTrue, reason: 'the app said background playback is allowed');

      await _foregrounded();

      expect(handle.playback.isPlaying, isTrue);
    });

    test('releasing a handle takes it out of the sweep', () async {
      final kernel = _kernel();

      final kept = await _playing(kernel, id: 'kept');
      final released = await _playing(kernel, id: 'released');

      await kernel.release(released.id);
      await pumpEventQueue();

      await _backgrounded();

      expect(kept.playback.isPlaying, isFalse);
      expect(released.disposed, isTrue);
    });
  });

  test('the fake adapter still reports what the engine was told', () async {
    // A guard on the rig itself: if the fake ever stops answering `play`, the
    // assertions above would pass for the wrong reason.
    final adapter = FakePlayerAdapter();

    await adapter.initialize(TestPlayerFactory.context());
    await adapter.open(PlayerSource(id: SourceId('x'), uri: Uri.parse('https://example.com/x.mp4')));
    await adapter.play();

    expect(adapter.calls, contains('play'), reason: 'the fake does answer the engine calls the sweep relies on');
    expect(adapter.events, isNotNull);
  });
}
