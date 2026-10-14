import 'package:flutter_test/flutter_test.dart';

import 'package:media_core_media_kit/src/mpv_error_gate.dart';

/// The window is a few tens of milliseconds so the suite runs quickly; only
/// the order of events relative to it matters.
const _window = Duration(milliseconds: 40);

Future<void> _pastWindow() => Future<void>.delayed(const Duration(milliseconds: 120));

final class _Recorder {
  final reported = <String>[];
  final held = <String>[];
  final dropped = <String>[];

  MpvErrorGate gate() => MpvErrorGate(
    onReport: reported.add,
    onHeld: held.add,
    onDropped: dropped.add,
    window: _window,
  );
}

void main() {
  group('classification', () {
    test('open, transport and codec failures are terminal', () {
      for (final line in [
        'Failed to open https://cdn.example.com/live/abc.flv?codec=264.',
        'tcp: Connection to tcp://cdn.example.com:443 failed: Connection refused',
        'tcp: Failed to resolve hostname cdn.example.com: nodename nor servname provided',
        'HTTP error 404 Not Found',
        'Server returned 403 Forbidden (access denied)',
        'Server returned 502 Bad Gateway',
        'Invalid data found when processing input',
        'No decoder found for this stream',
        'Unsupported codec',
      ]) {
        expect(MpvErrorGate.isTerminal(line), isTrue, reason: line);
      }
    });

    test('decoder, demuxer and unknown lines are transient', () {
      for (final line in [
        'Error while decoding frame!',
        'Error while decoding frame (hardware decoding)!',
        'Could not open codec.',
        'invalid NAL unit size',
        'Too many packets in the demuxer packet queues',
        'something mpv never said before',
      ]) {
        expect(MpvErrorGate.isTerminal(line), isFalse, reason: line);
      }
    });

    test('a reconnect is never terminal, whatever error it quotes', () {
      expect(
        MpvErrorGate.isTerminal('tcp: Will reconnect at 1024 in 0 second(s), error=Connection reset by peer.'),
        isFalse,
      );
      expect(MpvErrorGate.isTerminal('tls read returned -0x0'), isFalse);
    });

    test('words inside a URL decide nothing', () {
      // A Huya query carries `codec=264`; a path may carry "unsupported codec"
      // or "connection refused" as plain words.
      expect(
        MpvErrorGate.isTerminal('Error while reading https://h.example/unsupported%20codec/connection refused'),
        isFalse,
      );
      expect(MpvErrorGate.withoutUrls('a https://x.example/q?y=1 b'), 'a   b');
    });
  });

  group('gate', () {
    test('a terminal line is reported at once', () {
      final recorder = _Recorder();
      final gate = recorder.gate();

      gate.error('Failed to open https://a.example/live.m3u8.');

      expect(recorder.reported, ['Failed to open https://a.example/live.m3u8.']);
      expect(gate.holding, isFalse);
      gate.close();
    });

    test('a transient line with no progress after it is reported after the window', () async {
      final recorder = _Recorder();
      final gate = recorder.gate();

      gate.error('Error while decoding frame!');
      expect(recorder.reported, isEmpty);
      expect(recorder.held, ['Error while decoding frame!']);

      await _pastWindow();

      expect(recorder.reported, ['Error while decoding frame!']);
      expect(recorder.dropped, isEmpty);
      gate.close();
    });

    test('a moving position drops a held line', () async {
      final recorder = _Recorder();
      final gate = recorder.gate();

      gate.position(const Duration(seconds: 5));
      gate.error('Error while decoding frame!');
      // The same position again is not progress.
      gate.position(const Duration(seconds: 5));
      expect(gate.holding, isTrue);

      gate.position(const Duration(milliseconds: 5100));
      await _pastWindow();

      expect(recorder.reported, isEmpty);
      expect(recorder.dropped, ['Error while decoding frame!']);
      gate.close();
    });

    test('a new frame drops a held line', () async {
      final recorder = _Recorder();
      final gate = recorder.gate();

      gate.error('invalid NAL unit size');
      gate.progress();
      await _pastWindow();

      expect(recorder.reported, isEmpty);
      expect(recorder.dropped, ['invalid NAL unit size']);
      gate.close();
    });

    test('lines while one is held ride with it; a terminal one replaces it', () async {
      final recorder = _Recorder();
      final gate = recorder.gate();

      gate.error('Error while decoding frame!');
      gate.error('Error while decoding frame!');
      gate.error('Could not open codec.');
      expect(recorder.held, hasLength(1));

      gate.error('HTTP error 403 Forbidden');
      await _pastWindow();

      expect(recorder.reported, ['HTTP error 403 Forbidden']);
      gate.close();
    });

    test('the same text is reported once within the repeat window', () {
      final recorder = _Recorder();
      final gate = recorder.gate();

      gate.error('Failed to open x.');
      gate.error('Failed to open x.');
      gate.error('Failed to open y.');

      expect(recorder.reported, ['Failed to open x.', 'Failed to open y.']);
      gate.close();
    });

    test('reset forgets the held line and the previous position', () async {
      final recorder = _Recorder();
      final gate = recorder.gate();

      gate.position(const Duration(seconds: 5));
      gate.error('Error while decoding frame!');
      gate.reset();
      await _pastWindow();
      expect(recorder.reported, isEmpty);

      // The first position after a reset is a baseline, not progress.
      gate.error('Error while decoding frame!');
      gate.position(const Duration(seconds: 9));
      await _pastWindow();

      expect(recorder.reported, ['Error while decoding frame!']);
      gate.close();
    });

    test('nothing is reported after close', () async {
      final recorder = _Recorder();
      final gate = recorder.gate();

      gate.error('Error while decoding frame!');
      gate.close();
      gate.error('Failed to open x.');
      await _pastWindow();

      expect(recorder.reported, isEmpty);
    });
  });
}
