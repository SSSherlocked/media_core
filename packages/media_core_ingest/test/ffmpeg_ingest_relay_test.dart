import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_ingest/media_core_ingest.dart';

final class _FakeProcess implements IngestFfmpegProcess {
  final Completer<int> _exit = Completer<int>();
  bool stopped = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_exit.isCompleted) _exit.complete(0);
  }

  void exitNow(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }
}

void main() {
  group('ffmpeg ingest arguments', () {
    test('a copy remux publishes a rolling local playlist', () {
      final arguments = FfmpegIngestRelay.buildIngestArguments(
        source: Uri.parse('https://example.com/live.flv'),
        outputDirectory: r'C:\tmp\ingest',
      );

      expect(arguments, containsAllInOrder(<String>['-i', 'https://example.com/live.flv']));
      expect(arguments, containsAllInOrder(<String>['-c', 'copy']));
      expect(arguments, containsAllInOrder(<String>['-f', 'hls']));
      expect(arguments, containsAllInOrder(<String>['-hls_list_size', '4']));
      expect(arguments, contains('delete_segments+append_list+omit_endlist'));
      expect(arguments.last, endsWith(FfmpegIngestRelay.ingestPlaylistName));
      expect(arguments, isNot(contains('-headers')));
    });

    test('headers are one CRLF-delimited field list', () {
      final arguments = FfmpegIngestRelay.buildIngestArguments(
        source: Uri.parse('https://example.com/live.m3u8'),
        outputDirectory: '/tmp/ingest',
        headers: const <String, String>{'Referer': 'https://twitcasting.tv/', 'Origin': 'https://twitcasting.tv'},
      );

      final index = arguments.indexOf('-headers');
      expect(index, greaterThanOrEqualTo(0));
      expect(arguments[index + 1], contains('Referer: https://twitcasting.tv/\r\n'));
      expect(arguments[index + 1], contains('Origin: https://twitcasting.tv\r\n'));
    });

    test('a transcode declares the codecs instead of copying', () {
      final arguments = FfmpegIngestRelay.buildIngestArguments(
        source: Uri.parse('https://example.com/live.flv'),
        outputDirectory: '/tmp/ingest',
        copyStreams: false,
        videoCodec: 'libx264',
      );

      expect(arguments, isNot(contains('copy')));
      expect(arguments, containsAllInOrder(<String>['-c:v', 'libx264']));
      expect(arguments, containsAllInOrder(<String>['-c:a', 'aac']));
    });
  });

  group('ffmpeg ingest relay', () {
    late _FakeProcess process;

    setUp(() => process = _FakeProcess());

    test('a process that never publishes a playlist fails the start', () async {
      await expectLater(
        FfmpegIngestRelay.start(
          source: Uri.parse('https://example.com/live.flv'),
          startFfmpeg: (_) async => process,
          startupTimeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(process.stopped, isTrue, reason: 'a failed start must not leak the process');
    });

    test('a process that exits before publishing reports its code', () async {
      final started = FfmpegIngestRelay.start(
        source: Uri.parse('https://example.com/live.flv'),
        startFfmpeg: (_) async => process,
        startupTimeout: const Duration(seconds: 5),
      );
      scheduleMicrotask(() => process.exitNow(1));

      await expectLater(started, throwsA(isA<FormatException>()));
    });
  });
}
