import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core/testing/fake_player_adapter.dart';
import 'package:media_core/testing/test_player_factory.dart';
import 'package:media_core_ui/media_core_ui.dart';

PlayerSource _vod(String id) => PlayerSource(id: SourceId(id), uri: Uri.parse('https://example.com/$id.mp4'));

PlayerSource _live(String id) =>
    PlayerSource(id: SourceId(id), uri: Uri.parse('https://example.com/$id.m3u8'), type: SourceType.live);

/// A handle plus the fake driving it, opened on a source with a known duration.
final class _Rig {
  _Rig(this.handle, this.adapter);

  final PlayerHandle handle;
  final FakePlayerAdapter adapter;
}

Future<_Rig> _openRig(PlayerSource source, {bool playing = false}) async {
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
  await handle.initialize();
  await handle.open(source);
  if (playing) {
    adapter.emitPlaying();
    // The playing event rides the handle's async binding stream.
    await pumpEventQueue();
  }
  return _Rig(handle, adapter);
}

void main() {
  group('PlayerControlsStyle platform mapping', () {
    test('each desktop and mobile platform gets its conventional style', () {
      expect(PlayerControlsStyle.forPlatform(TargetPlatform.android), PlayerControlsStyle.material);
      expect(PlayerControlsStyle.forPlatform(TargetPlatform.fuchsia), PlayerControlsStyle.material);
      expect(PlayerControlsStyle.forPlatform(TargetPlatform.iOS), PlayerControlsStyle.cupertino);
      expect(PlayerControlsStyle.forPlatform(TargetPlatform.macOS), PlayerControlsStyle.macos);
      expect(PlayerControlsStyle.forPlatform(TargetPlatform.windows), PlayerControlsStyle.fluent);
      expect(PlayerControlsStyle.forPlatform(TargetPlatform.linux), PlayerControlsStyle.yaru);
    });

    test('neumorphic is never auto-selected', () {
      for (final platform in TargetPlatform.values) {
        expect(
          PlayerControlsStyle.forPlatform(platform),
          isNot(PlayerControlsStyle.neumorphic),
          reason: '$platform must not pick a stylistic statement over a convention',
        );
      }
    });

    test('isTouch follows the chrome language, not the material family', () {
      expect(PlayerControlsStyle.material.isTouch, isTrue);
      expect(PlayerControlsStyle.cupertino.isTouch, isTrue);
      expect(PlayerControlsStyle.neumorphic.isTouch, isTrue);
      expect(PlayerControlsStyle.fluent.isTouch, isFalse);
      expect(PlayerControlsStyle.macos.isTouch, isFalse);
      expect(PlayerControlsStyle.yaru.isTouch, isFalse);
    });
  });

  group('PlayerControlActions', () {
    test('none advertises no presentation surface', () {
      const actions = PlayerControlActions.none;
      expect(actions.canEnterFullscreen, isFalse);
      expect(actions.canEnterPip, isFalse);
      expect(actions.canEnterFloating, isFalse);
      expect(actions.canHandleScreenshot, isFalse);
      expect(actions.hasPresentation, isFalse);
    });

    test('installing a callback flips exactly its own capability', () {
      final actions = PlayerControlActions(enterPip: () async {});

      expect(actions.canEnterPip, isTrue);
      expect(actions.canEnterFullscreen, isFalse);
      expect(actions.hasPresentation, isTrue);
    });
  });

  group('PlayerControlsController visibility', () {
    test('auto-hide fires only while playing, exactly at the delay', () async {
      final rig = await _openRig(_vod('v'));
      addTearDown(rig.handle.dispose);

      fakeAsync((async) {
        final controller = PlayerControlsController(handle: rig.handle, hideDelay: const Duration(seconds: 3));
        addTearDown(controller.dispose);

        // Not playing: the idle clock must not run for a paused viewer.
        expect(controller.isPlaying, isFalse);
        expect(controller.controlsVisible, isTrue);
        async.elapse(const Duration(seconds: 10));
        expect(controller.controlsVisible, isTrue, reason: 'paused keeps the chrome up');

        rig.adapter.emitPlaying();
        async.flushMicrotasks();
        expect(controller.isPlaying, isTrue);

        controller.revealControls();
        async.elapse(const Duration(seconds: 2));
        expect(controller.controlsVisible, isTrue);
        async.elapse(const Duration(seconds: 2));
        expect(controller.controlsVisible, isFalse, reason: 'idle at 3s hides the chrome');
      });
    });

    test('engine ticks do not keep the chrome alive', () async {
      // Short delay so the test stays fast; the assertion is about which clock
      // the countdown follows, not about the length.
      final rig = await _openRig(_vod('v'), playing: true);
      addTearDown(rig.handle.dispose);

      final controller = PlayerControlsController(handle: rig.handle, hideDelay: const Duration(milliseconds: 100));
      addTearDown(controller.dispose);

      controller.revealControls();
      expect(controller.controlsVisible, isTrue);

      // A stream of position reports: 10 of them, spanning four idle windows.
      // If ticks extend the countdown, the chrome never fades during playback.
      for (var tick = 1; tick <= 10; tick++) {
        rig.adapter.emitPosition(Duration(milliseconds: tick * 50));
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 25));
        if (tick == 2) {
          expect(controller.controlsVisible, isTrue, reason: 'the window has not passed yet');
        }
      }

      expect(controller.controlsVisible, isFalse, reason: '250 ms of position ticks are not 250 ms of viewer activity');
    });

    test('viewer activity notifies nobody and buys exactly one window', () async {
      // The hover/tap path. `revealControls` is what a moving mouse and every
      // control press call, and on a desktop it can arrive a hundred times a
      // second while the pointer simply sits inside the video.
      final rig = await _openRig(_vod('v'));
      addTearDown(rig.handle.dispose);

      fakeAsync((async) {
        const delay = Duration(seconds: 3);
        final controller = PlayerControlsController(handle: rig.handle, hideDelay: delay);
        addTearDown(controller.dispose);

        rig.adapter.emitPlaying();
        async.flushMicrotasks();

        controller.revealControls();

        var notifications = 0;
        controller.addListener(() => notifications++);

        // Continuous activity for four seconds, in slices shorter than a window.
        for (var i = 0; i < 100; i++) {
          async.elapse(const Duration(milliseconds: 40));
          controller.revealControls();
        }

        expect(notifications, 0, reason: 'already visible: marking is not a state change');

        // The last report landed at t=4s, inside the window that started at 3s.
        // Marking that window buys one more (3s → 6s, then 6s → 9s), so the
        // chrome is still up an instant past 7.2s and gone by 10.6s. A body that
        // re-armed on every report instead would have hidden it at 7s — the
        // saving here is observable as the bought window, not as the timer count.
        async.elapse(const Duration(milliseconds: 3200));

        expect(controller.controlsVisible, isTrue, reason: 'a marked window is paid for');

        async.elapse(const Duration(seconds: 4));

        expect(controller.controlsVisible, isFalse, reason: 'activity marks a window, it does not own one');
        expect(notifications, 1, reason: 'only the fade itself notifies');
      });
    });

    test('a manual hide does not disarm future auto-hides', () async {
      final rig = await _openRig(_vod('v'), playing: true);
      addTearDown(rig.handle.dispose);

      fakeAsync((async) {
        final controller = PlayerControlsController(handle: rig.handle, hideDelay: const Duration(milliseconds: 200));
        addTearDown(controller.dispose);

        // Tapping the video hides by force, and the countdown is cancelled with
        // it. A cancelled timer left in the field reads as "a countdown is
        // already running", so the next reveal would never arm one again and the
        // chrome would sit on screen for the rest of the session.
        controller.toggleControls();
        expect(controller.controlsVisible, isFalse);

        controller.toggleControls();
        expect(controller.controlsVisible, isTrue);

        async.elapse(const Duration(milliseconds: 300));
        expect(controller.controlsVisible, isFalse, reason: 'the second reveal has to fade on its own clock');
      });
    });

    test('a tap on visible controls dismisses even when paused', () async {
      final rig = await _openRig(_vod('v'));
      addTearDown(rig.handle.dispose);

      final controller = PlayerControlsController(handle: rig.handle, autoHide: false);
      addTearDown(controller.dispose);

      expect(controller.controlsVisible, isTrue);
      controller.toggleControls(); // done looking
      expect(controller.controlsVisible, isFalse);

      controller.toggleControls(); // back from a tap
      expect(controller.controlsVisible, isTrue);
    });

    test('autoHide off keeps the chrome up indefinitely for host-owned layouts', () async {
      final rig = await _openRig(_vod('v'), playing: true);
      addTearDown(rig.handle.dispose);

      fakeAsync((async) {
        final controller = PlayerControlsController(handle: rig.handle, autoHide: false);
        addTearDown(controller.dispose);

        expect(controller.isPlaying, isTrue);
        async.elapse(const Duration(minutes: 2));
        expect(controller.controlsVisible, isTrue);
        expect(controller.autoHides, isFalse);
      });
    });

    test('setControlsVisible bypasses the idle policy in both directions', () async {
      final rig = await _openRig(_vod('v'), playing: true);
      addTearDown(rig.handle.dispose);

      fakeAsync((async) {
        final controller = PlayerControlsController(handle: rig.handle, hideDelay: const Duration(milliseconds: 50));
        addTearDown(controller.dispose);

        controller.setControlsVisible(visible: false);
        expect(controller.controlsVisible, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(controller.controlsVisible, isFalse, reason: 'hidden stays hidden until revealed');

        controller.setControlsVisible(visible: true);
        expect(controller.controlsVisible, isTrue);
      });
    });

    test('listeners fire on visibility edges only', () async {
      final rig = await _openRig(_vod('v'));
      addTearDown(rig.handle.dispose);

      fakeAsync((async) {
        final controller = PlayerControlsController(handle: rig.handle, autoHide: false);
        addTearDown(controller.dispose);

        var notifications = 0;
        controller
            ..addListener(() => notifications++)
            ..setControlsVisible(visible: true); // already visible
        expect(notifications, 0);

        controller.setControlsVisible(visible: false);
        expect(notifications, 1);

        controller.setControlsVisible(visible: false); // already hidden
        expect(notifications, 1);
      });
    });

    test('a position tick updates the readouts without rebuilding the bar', () async {
      // The engine reports position many times a second. Only the widgets that
      // show time should hear about it: if the controller notified on every
      // tick, the whole control bar would rebuild at engine rate and a feed
      // would visibly stutter on weak devices.
      final rig = await _openRig(_vod('v'), playing: true);
      addTearDown(rig.handle.dispose);

      final controller = PlayerControlsController(handle: rig.handle, autoHide: false);
      addTearDown(controller.dispose);

      var barRebuilds = 0;
      controller.addListener(() => barRebuilds++);
      var tickReadouts = 0;
      controller.playbackListenable.addListener(() => tickReadouts++);

      for (var second = 1; second <= 5; second++) {
        rig.adapter.emitPosition(Duration(seconds: second));
        await pumpEventQueue();
      }

      expect(tickReadouts, 5, reason: 'the progress bar and time labels follow the engine');
      expect(barRebuilds, 0, reason: 'position-only ticks are not a structural change');

      rig.adapter.emitPaused();
      await pumpEventQueue();
      expect(barRebuilds, 1, reason: 'pause is structural: the bar must change its icon');
    });
  });

  group('PlayerControlsController state', () {
    test('canSeek refuses live sources and accepts a seekable vod', () async {
      final rig = await _openRig(_live('room1'));
      addTearDown(rig.handle.dispose);
      final controller = PlayerControlsController(handle: rig.handle);
      addTearDown(controller.dispose);

      expect(controller.isLive, isTrue);
      expect(controller.canSeek, isFalse, reason: 'a live wall has no timeline to drag');

      await rig.handle.open(_vod('v'));
      expect(controller.isLive, isFalse);
      // The fake reports a duration on open and advertises supportsSeek.
      expect(rig.handle.playback.hasDuration, isTrue);
      expect(controller.canSeek, isTrue);
    });

    test('title falls back to the last path segment when the source has none', () async {
      final rig = await _openRig(_vod('episode7'));
      addTearDown(rig.handle.dispose);
      final controller = PlayerControlsController(handle: rig.handle);
      addTearDown(controller.dispose);

      expect(controller.title, 'episode7.mp4');

      await rig.handle.open(PlayerSource(id: SourceId('t'), uri: Uri.parse('https://example.com/a/b'), title: '给标题'));
      expect(controller.title, '给标题');
    });

    test('a disposed controller reports itself instead of throwing on getters', () async {
      final rig = await _openRig(_vod('v'));
      addTearDown(rig.handle.dispose);
      final controller = PlayerControlsController(handle: rig.handle)..dispose();

      expect(controller.isDisposed, isTrue);
    });
  });
}
