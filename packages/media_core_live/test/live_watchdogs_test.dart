import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/media_core.dart';

import 'package:media_core_live/media_core_live.dart';

/// Every deadline is a few tens of milliseconds so a suite of timer behavior
/// runs in well under a second; the ratios between them are what matter.
const _short = Duration(milliseconds: 20);
const _long = Duration(milliseconds: 120);

final class _Recorder {
  final stalls = <LiveStallKind>[];
  final actions = <LiveWatchdogRecoveryAction>[];
}

LiveWatchdogs _watchdogs(
  _Recorder recorder, {
  Duration sourceReadyTimeout = _short,
  Duration unexpectedPauseGrace = _short,
  Duration unexpectedPauseFailureGrace = _short,
  Duration bufferingStallTimeout = _short,
  Duration videoFrameStallTimeout = _short,
  Duration positionStallTimeout = _short,
  bool enabled = true,
  PlayerAdapterCapabilities? capabilities,
}) {
  return LiveWatchdogs(
      capabilities: capabilities,
      sourceReadyTimeout: sourceReadyTimeout,
      unexpectedPauseGrace: unexpectedPauseGrace,
      unexpectedPauseFailureGrace: unexpectedPauseFailureGrace,
      bufferingStallTimeout: bufferingStallTimeout,
      videoFrameStallTimeout: videoFrameStallTimeout,
      positionStallTimeout: positionStallTimeout,
      enabled: enabled,
    )
    ..onStall = recorder.stalls.add
    ..onRecoveryRequested = recorder.actions.add;
}

Future<void> _settle() => Future<void>.delayed(_long);

void main() {
  group('source ready', () {
    test('a source that never plays is reported', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)..armSourceReady();

      await _settle();

      expect(recorder.stalls, [LiveStallKind.sourceReadyTimeout]);
      watchdogs.dispose();
    });

    test('playing before the deadline cancels the arm', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)
        ..armSourceReady()
        ..onPlayingChanged(playing: true, fromUserIntent: false);

      await _settle();

      expect(recorder.stalls, isEmpty);
      watchdogs.dispose();
    });

    test('a zero timeout disables the arm instead of firing at once', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder, sourceReadyTimeout: Duration.zero)..armSourceReady();

      await _settle();

      expect(recorder.stalls, isEmpty);
      watchdogs.dispose();
    });

    test('re-arming replaces the previous deadline rather than stacking', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)
        ..armSourceReady()
        ..armSourceReady();

      await _settle();

      expect(recorder.stalls, [LiveStallKind.sourceReadyTimeout]);
      watchdogs.dispose();
    });
  });

  group('unexpected pause', () {
    test('asks the owner to reassert playback', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..onPlayingChanged(playing: false, fromUserIntent: false);

      await _settle();

      expect(recorder.actions, [LiveWatchdogRecoveryAction.reassertPlay]);
      // The watchdog asks; it does not decide the outcome by itself.
      expect(recorder.stalls, isEmpty);
      watchdogs.dispose();
    });

    test('a pause the user asked for is not a stall', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..onPlayingChanged(playing: false, fromUserIntent: true);

      await _settle();

      expect(recorder.actions, isEmpty);
      expect(recorder.stalls, isEmpty);
      watchdogs.dispose();
    });

    test('a reassert that worked is silent', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..onPlayingChanged(playing: false, fromUserIntent: false);

      await _settle();
      expect(recorder.actions, hasLength(1));

      watchdogs
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..reportRecoveryResult(resumed: true);
      await _settle();

      expect(recorder.stalls, isEmpty);
      watchdogs.dispose();
    });

    test('a reassert that did not take escalates to a timeout', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..onPlayingChanged(playing: false, fromUserIntent: false);

      await _settle();

      watchdogs.reportRecoveryResult(resumed: false);
      await _settle();

      expect(recorder.stalls, [LiveStallKind.unexpectedPauseTimeout]);
      watchdogs.dispose();
    });

    test('no failure grace means the failure is reported at once', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder, unexpectedPauseFailureGrace: Duration.zero)
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..onPlayingChanged(playing: false, fromUserIntent: false);

      await _settle();

      watchdogs.reportRecoveryResult(resumed: false);

      expect(recorder.stalls, [LiveStallKind.unexpectedPauseResumeFailed]);
      watchdogs.dispose();
    });

    test('a recovery result with nothing pending is ignored', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)..reportRecoveryResult(resumed: false);

      await _settle();

      expect(recorder.stalls, isEmpty);
      watchdogs.dispose();
    });
  });

  group('buffering stall', () {
    test('buffering past the deadline is reported', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..onBufferingChanged(buffering: true);

      await _settle();

      expect(recorder.stalls, [LiveStallKind.bufferingStallTimeout]);
      watchdogs.dispose();
    });

    test('buffering that ends in time is not a stall', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder, bufferingStallTimeout: _long)
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..onBufferingChanged(buffering: true)
        ..onBufferingChanged(buffering: false);

      await _settle();

      expect(recorder.stalls, isEmpty);
      watchdogs.dispose();
    });
  });

  group('video frame stall', () {
    test('a playing stream with no frames is reported, when the engine '
        'declares a frame heartbeat', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(
        recorder,
        capabilities: const PlayerAdapterCapabilities(supportsVideoFrameProgress: true),
      )..onPlayingChanged(playing: true, fromUserIntent: false);

      await _settle();

      expect(recorder.stalls, contains(LiveStallKind.videoFrameStallTimeout));
      watchdogs.dispose();
    });

    test('an engine with no frame heartbeat is never judged by one', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)..onPlayingChanged(playing: true, fromUserIntent: false);

      await _settle();

      expect(recorder.stalls, isNot(contains(LiveStallKind.videoFrameStallTimeout)));
      watchdogs.dispose();
    });

    test('frames arriving keep the watchdog quiet', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(
        recorder,
        videoFrameStallTimeout: _long,
        capabilities: const PlayerAdapterCapabilities(supportsVideoFrameProgress: true),
      )..onPlayingChanged(playing: true, fromUserIntent: false);

      for (var i = 0; i < 6; i++) {
        watchdogs.onFrameProgress();
        await Future<void>.delayed(_short);
      }

      expect(recorder.stalls, isNot(contains(LiveStallKind.videoFrameStallTimeout)));
      watchdogs.dispose();
    });

    test('a hidden presentation is not judged', () async {
      final recorder = _Recorder();
      final watchdogs =
          _watchdogs(recorder, capabilities: const PlayerAdapterCapabilities(supportsVideoFrameProgress: true))
            ..setPresentationVisible(visible: false)
            ..onPlayingChanged(playing: true, fromUserIntent: false);

      await _settle();

      expect(recorder.stalls, isNot(contains(LiveStallKind.videoFrameStallTimeout)));
      watchdogs.dispose();
    });

    test('unbinding the capabilities stops judging frames', () async {
      final recorder = _Recorder();
      final watchdogs =
          _watchdogs(recorder, capabilities: const PlayerAdapterCapabilities(supportsVideoFrameProgress: true))
            ..updateCapabilities(null)
            ..onPlayingChanged(playing: true, fromUserIntent: false);

      await _settle();

      expect(watchdogs.capabilities, isNull);
      expect(recorder.stalls, isNot(contains(LiveStallKind.videoFrameStallTimeout)));
      watchdogs.dispose();
    });
  });

  group('position stall', () {
    test('a frozen position is caught on an engine with no frame heartbeat', () async {
      // The detector of last resort: every adapter reports position, so a
      // picture that freezes while the engine still claims to be playing is
      // caught here even with nothing else to catch it.
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..onPositionProgress(const Duration(seconds: 1));

      await _settle();

      expect(recorder.stalls, contains(LiveStallKind.positionStallTimeout));
      watchdogs.dispose();
    });

    test('no position sample means no judgement', () async {
      // The watchdog only arms after the engine has proved it reports
      // position at all, so it never judges an engine that does not.
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)..onPlayingChanged(playing: true, fromUserIntent: false);

      await _settle();

      expect(recorder.stalls, isNot(contains(LiveStallKind.positionStallTimeout)));
      watchdogs.dispose();
    });

    test('a position that keeps advancing is healthy', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder, positionStallTimeout: _long)
        ..onPlayingChanged(playing: true, fromUserIntent: false);

      for (var second = 1; second <= 6; second++) {
        watchdogs.onPositionProgress(Duration(seconds: second));
        await Future<void>.delayed(_short);
      }

      expect(recorder.stalls, isNot(contains(LiveStallKind.positionStallTimeout)));
      watchdogs.dispose();
    });

    test('resetting the signal stops the detector for the next source', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..onPositionProgress(Duration.zero)
        ..resetPositionSignal();

      await _settle();

      expect(recorder.stalls, isNot(contains(LiveStallKind.positionStallTimeout)));
      watchdogs.dispose();
    });
  });

  group('master switch and teardown', () {
    test('disabled watchdogs arm nothing at all', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder, enabled: false)
        ..armSourceReady()
        ..onPlayingChanged(playing: true, fromUserIntent: false)
        ..onPlayingChanged(playing: false, fromUserIntent: false)
        ..onBufferingChanged(buffering: true)
        ..onPositionProgress(Duration.zero);

      await _settle();

      expect(recorder.stalls, isEmpty);
      expect(recorder.actions, isEmpty);
      watchdogs.dispose();
    });

    test('cancelAll stops every armed deadline', () async {
      final recorder = _Recorder();
      final watchdogs = _watchdogs(recorder)
        ..armSourceReady()
        ..cancelAll();

      await _settle();

      expect(recorder.stalls, isEmpty);
      watchdogs.dispose();
    });

    test('nothing fires after dispose', () async {
      final recorder = _Recorder();

      // No variable held: nothing after teardown is allowed to speak to the
      // bundle, which is exactly what this test proves.
      _watchdogs(recorder)
        ..armSourceReady()
        ..dispose()
        ..onPlayingChanged(playing: false, fromUserIntent: false)
        ..onPositionProgress(Duration.zero);

      await _settle();

      expect(recorder.stalls, isEmpty);
      expect(recorder.actions, isEmpty);
    });
  });
}
