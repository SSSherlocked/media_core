import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/event/player_event_bus.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/kernel/kernel_options.dart';
import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/testing/fake_player_adapter.dart';
import 'package:media_core/testing/test_player_factory.dart';

/// A handle over one fake engine.
///
/// Both sides of the assertions live on the fake: `calls` shows what reached
/// the engine, and the gate holds a call there until the test says so.
({PlayerHandle handle, FakePlayerAdapter fake}) _setup() {
  final fake = FakePlayerAdapter(id: 'fake-1');
  final handle = PlayerHandle(
    player: TestPlayerFactory.player(1),
    adapter: fake,
    registration: PlayerAdapterRegistration(
      id: 'fake',
      factory: TestPlayerFactory.fakeAdapterFactory(),
      capabilities: const FakePlayerAdapterBehavior().capabilities,
    ),
    adapterContext: TestPlayerFactory.context(),
    eventBus: PlayerEventBus(),
    options: const KernelOptions(),
  );

  return (handle: handle, fake: fake);
}

Future<PlayerSource> _opened(({PlayerHandle handle, FakePlayerAdapter fake}) rig) async {
  await rig.handle.initialize();

  final source = PlayerSource(id: SourceId('s1'), uri: Uri.parse('https://example.com/a.flv'));

  await rig.handle.open(source);

  return source;
}

void main() {
  group('an audio-property request never supersedes another operation', () {
    test('a volume set during an in-flight play still plays', () async {
      final rig = _setup();
      addTearDown(rig.handle.dispose);

      await _opened(rig);

      // The engine answers `play` slowly, which is the window a real device
      // gives the viewer to touch the slider. The volume set queues behind it,
      // so nothing is awaited until the gate is open.
      final playGate = Completer<void>();
      rig.fake.gate = (call) => call == 'play' ? playGate.future : Future<void>.value();

      final playing = rig.handle.play();
      final volume = rig.handle.setVolume(0.4);

      playGate.complete();
      await Future.wait<void>(<Future<void>>[playing, volume]);

      // Volume used to grab the single cancellation slot from the running
      // play, so the play never reached the engine at all.
      expect(rig.fake.calls, contains('play'), reason: 'the engine has to see the play it was given');
      expect(rig.handle.playback.isPlaying, isTrue);
      expect(rig.fake.volumes, contains(0.4));
    });

    test('a rate change during an in-flight seek still completes the seek', () async {
      final rig = _setup();
      addTearDown(rig.handle.dispose);

      await _opened(rig);

      final seekGate = Completer<void>();
      rig.fake.gate = (call) => call == 'seek' ? seekGate.future : Future<void>.value();

      final seeking = rig.handle.seek(const Duration(seconds: 40));
      final rate = rig.handle.setRate(1.5);

      seekGate.complete();
      await Future.wait<void>(<Future<void>>[seeking, rate]);

      expect(rig.fake.calls, contains('seek'));
      expect(rig.fake.seeks, contains(const Duration(seconds: 40)));
      expect(rig.handle.playback.rate, 1.5);
    });
  });

  group('a drag is answered with the position the viewer stopped on', () {
    test('six volume steps reach the engine once, as the last value', () async {
      final rig = _setup();
      addTearDown(rig.handle.dispose);

      await _opened(rig);

      // A Slider fires onChanged per frame of the drag; only the final value
      // is a thing the viewer asked for.
      final steps = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6].map(rig.handle.setVolume).toList();

      await Future.wait(steps);

      expect(rig.fake.volumes, <double>[0.6], reason: 'one engine round trip for the whole drag');
      expect(rig.handle.playback.volume, 0.6);
    });

    test('six rate steps reach the engine once, as the last value', () async {
      final rig = _setup();
      addTearDown(rig.handle.dispose);

      await _opened(rig);

      final steps = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map(rig.handle.setRate).toList();

      await Future.wait(steps);

      expect(rig.fake.rates, <double>[2]);
      expect(rig.handle.playback.rate, 2.0);
    });

    test('a step awaited before the next is not treated as a drag', () async {
      final rig = _setup();
      addTearDown(rig.handle.dispose);

      await _opened(rig);

      // Keyboard volume keys land one step at a time, and each has to apply.
      await rig.handle.setVolume(0.2);
      await rig.handle.setVolume(0.4);
      await rig.handle.setVolume(0.6);

      expect(rig.fake.volumes, <double>[0.2, 0.4, 0.6]);
    });
  });
}
