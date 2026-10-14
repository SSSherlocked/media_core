import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/core/player_core_state.dart';
import 'package:media_core/core/player_lifecycle_state.dart';
import 'package:media_core/core/player_playback_state.dart';

void main() {
  group('PlayerCoreState', () {
    test('default state is idle', () {
      const state = PlayerCoreState.idle;
      expect(state.isIdle, isTrue);
      expect(state.lifecycle, PlayerLifecycleState.idle);
      expect(state.playback, PlayerPlaybackState.idle);
      expect(state.hasSource, isFalse);
    });

    test('state helpers reflect playback enum', () {
      expect(PlayerCoreState.idle.playingState().playing, isTrue);
      expect(PlayerCoreState.idle.pausedState().paused, isTrue);
      expect(PlayerCoreState.idle.bufferingState().buffering, isTrue);
      expect(PlayerCoreState.idle.seekingState().seeking, isTrue);
      expect(PlayerCoreState.idle.completedState().completed, isTrue);
      expect(PlayerCoreState.idle.stoppedState().stopped, isTrue);
    });

    test('error state marks hasError and blocks control', () {
      final state = PlayerCoreState.idle.readyState().errorState();
      expect(state.hasError, isTrue);
      expect(state.canControl, isFalse);
      expect(state.ready, isFalse);
      expect(state.isClean, isFalse);
    });

    test('disposed is terminal and clears outputs', () {
      final state = PlayerCoreState.idle.withAudioEnabled(value: true).playingState().disposedState();
      expect(state.disposed, isTrue);
      expect(state.isTerminal, isTrue);
      expect(state.hasSource, isFalse);
      expect(state.audioEnabled, isFalse);
    });

    group('transitions', () {
      test('initializing to ready', () {
        final state = PlayerCoreState.idle.initializingState();
        expect(state.lifecycle, PlayerLifecycleState.initializing);

        final ready = state.readyState();
        expect(ready.initialized, isTrue);
        expect(ready.isIdle, isFalse);
      });

      test('ready to opening to playing', () {
        final opening = PlayerCoreState.idle.initializingState().readyState().openingState();
        expect(opening.opening, isTrue);
        expect(opening.isTransitioning, isTrue);

        final playing = opening.withSource(value: true).playingState();
        expect(playing.playing, isTrue);
        expect(playing.hasSource, isTrue);
        expect(playing.isPlaybackActive, isTrue);
      });

      test('withSource false resets playback to idle', () {
        final state = PlayerCoreState.idle.playingState().withSource(value: false);
        expect(state.hasSource, isFalse);
        expect(state.playback, PlayerPlaybackState.idle);
      });

      test('clearError restores idle playback', () {
        final state = PlayerCoreState.idle.readyState().errorState().clearError();
        expect(state.hasError, isFalse);
        expect(state.playback, PlayerPlaybackState.idle);
      });

      test('reset keeps lifecycle but clears playback', () {
        final state = PlayerCoreState.idle.playingState().reset();
        expect(state.lifecycle, PlayerLifecycleState.ready);
        expect(state.playback, PlayerPlaybackState.idle);
      });
    });

    group('capability gates', () {
      test('canPlay requires source and readiness', () {
        expect(PlayerCoreState.idle.canPlay, isFalse);

        final ready = PlayerCoreState.idle.initializingState().readyState();
        expect(ready.canPlay, isFalse, reason: 'no source yet');

        final withSource = ready.withSource(value: true);
        expect(withSource.canPlay, isTrue);

        expect(withSource.playingState().canPlay, isFalse);
        expect(withSource.bufferingState().canPlay, isFalse);
      });

      test('canPause only while playing', () {
        final withSource = PlayerCoreState.idle.readyState().withSource(value: true);
        expect(withSource.canPause, isFalse);
        expect(withSource.playingState().canPause, isTrue);
      });

      test('canStop during active playback transitions', () {
        expect(PlayerCoreState.idle.canStop, isFalse);
        expect(PlayerCoreState.idle.readyState().withSource(value: true).playingState().canStop, isTrue);
        expect(PlayerCoreState.idle.readyState().openingState().canStop, isTrue);
      });
    });

    group('output modes', () {
      test('audio only / video only / both', () {
        final audioOnly = PlayerCoreState.idle.withAudioEnabled(value: true);
        expect(audioOnly.isAudioOnly, isTrue);

        final videoOnly = PlayerCoreState.idle.withVideoEnabled(value: true);
        expect(videoOnly.isVideoOnly, isTrue);

        final both = audioOnly.withVideoEnabled(value: true);
        expect(both.isAudioVideo, isTrue);
      });

      test('muted toggling', () {
        expect(PlayerCoreState.idle.withMuted(value: true).muted, isTrue);
      });
    });

    test('serialization round trip', () {
      final state = PlayerCoreState.idle.playingState().withSource(value: true).withMuted(value: true);
      final json = state.toJson();
      final restored = PlayerCoreState.fromJson(json);
      expect(restored, state);
    });
  });
}
