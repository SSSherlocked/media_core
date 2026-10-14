import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_native/media_core_native.dart' show BackgroundExecutionLease, BackgroundNotification;
import 'package:media_core_recording_ffmpeg/media_core_recording_ffmpeg.dart';
import 'package:media_core_recording_ffmpeg/src/output_path.dart';

final class _FakeExecution implements FfmpegExecution {
  _FakeExecution(this.arguments);

  final List<String> arguments;
  final Completer<int> _exit = Completer<int>();
  bool stopCalled = false;

  /// What the process reports when it is ended on request: 255 for a kill, and
  /// something else for a process that had already failed before the stop.
  int stopExitCode = 255;
  bool cancelCalled = false;

  @override
  bool get isRunning => !_exit.isCompleted;

  @override
  Future<int> get exitCode => _exit.future;

  void finish(int code) {
    if (!_exit.isCompleted) {
      _exit.complete(code);
    }
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
    finish(stopExitCode);
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
    finish(255);
  }
}

final class _FakeExecutor implements FfmpegExecutor {
  final List<_FakeExecution> executions = <_FakeExecution>[];
  void Function(FfmpegStatistics statistics)? lastStatistics;

  /// Called with every argument list, so a test can leave the output a real
  /// FFmpeg would have left: a journal plus the segment files it names.
  void Function(List<String> arguments)? onStart;

  int initializeCount = 0;
  int disposeCount = 0;
  bool initialized = false;

  @override
  Future<void> initialize() async {
    initializeCount++;
    initialized = true;
  }

  @override
  Future<FfmpegExecution> start({
    required List<String> arguments,
    void Function(FfmpegStatistics statistics)? onStatistics,
    void Function(String message)? onLog,
  }) async {
    lastStatistics = onStatistics;
    final execution = _FakeExecution(arguments);
    executions.add(execution);
    onStart?.call(arguments);
    return execution;
  }

  @override
  Future<void> dispose() async => disposeCount++;
}

/// Answers with a fixed duration for a file that exists, and nothing for one
/// that does not — which is how FFprobe behaves on a truncated segment.
final class _FakeProbe implements FfmpegProbe {
  _FakeProbe({this.canRead = true});

  /// Whether FFprobe would answer at all.
  final bool canRead;

  @override
  Future<Duration?> durationOf(String path) async {
    if (!canRead || !File(path).existsSync()) {
      return null;
    }

    return const Duration(seconds: 30);
  }
}

/// A held session that records what the notification line said.
final class _FakeLease implements BackgroundExecutionLease {
  final List<String?> texts = <String?>[];

  @override
  int get id => 7;

  @override
  bool get isActive => true;

  @override
  Future<void> update(BackgroundNotification notification) async => texts.add(notification.text);

  @override
  Future<void> release() async {}
}

/// A temporary directory that is removed when the test ends.
Directory _tempDirectory() {
  final directory = Directory.systemTemp.createTempSync('media_core_recording_test');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

RecordingSource _source() => const RecordingSource.network('https://example.com/live.m3u8', id: 'room-1');

/// Writes the output a real FFmpeg run would have left for [arguments].
///
/// The journal is what the check reads, so it is written from the argument list
/// rather than from a path the test guessed: a change to how the pattern or the
/// journal is named must not silently change what the fake produces.
void _writeOutput(
  List<String> arguments, {
  int segments = 2,
  int bytes = 8192,
  bool dropLastSegment = false,
  bool trailingPartialLine = false,
}) {
  final journalPath = arguments[arguments.indexOf('-segment_list') + 1];
  final pattern = arguments.last;
  final directory = outputDirectoryOf(journalPath);
  final names = <String>[];

  for (final index in List<int>.generate(segments, (i) => i)) {
    final name = pattern.replaceAll('%06d', index.toString().padLeft(6, '0'));
    names.add(name);

    if (dropLastSegment && index == segments - 1) {
      continue;
    }

    File(joinOutputPath(directory, name)).writeAsBytesSync(List<int>.filled(bytes, 0));
  }

  final lines = names.map((name) => "file,'$name'").join('\n');
  File(journalPath).writeAsStringSync('$lines\n${trailingPartialLine ? "file,'parti" : ''}');
}

/// Lets the exit watcher's async report land.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

/// Waits for the backend's own state to go terminal.
///
/// An unasked-for end runs through the exit watcher, the give-up decision and the
/// output verification before it reports, and a fixed sleep would be a guess about
/// all three.
Future<void> _waitUntilTerminal(FfmpegRecordingBackend backend) async {
  for (var attempt = 0; attempt < 200 && !backend.state.status.isTerminal; attempt++) {
    await _settle();
  }
}

/// The reporter the tests install to see what a finished recording says.
final class _CapturingReporter implements MediaJobReporter {
  final List<MediaJobOutcome> seen = <MediaJobOutcome>[];

  @override
  void report(MediaJobOutcome outcome) => seen.add(outcome);
}

void main() {
  group('FfmpegRecordArguments', () {
    const builder = FfmpegRecordArguments();

    test('builds a segmented MPEG-TS capture of the source', () {
      final arguments = builder.recordArguments(
        url: 'https://example.com/live.m3u8',
        outputDirectory: '/recordings',
        segmentPattern: 'room_%06d.clock-v1.ts',
        journalPath: '/recordings/room.clock-v1.csv',
      );

      expect(arguments, contains('-i'));
      expect(arguments[arguments.indexOf('-i') + 1], 'https://example.com/live.m3u8');
      expect(arguments, contains('segment'));
      expect(arguments, contains('mpegts'));
      expect(arguments, contains('copy'), reason: 'recording must not transcode');
      // Segment list and naming.
      expect(arguments, contains('/recordings/room.clock-v1.csv'));
      expect(arguments, contains('/recordings/room_%06d.clock-v1.ts'));
      // The journal is CSV so segments can be joined later.
      expect(arguments[arguments.indexOf('-segment_list_type') + 1], 'csv');
      // Never overwrite an existing recording.
      expect(arguments.first, '-n');
    });

    test('maps first streams, tolerating absence', () {
      final preferred = builder.recordArguments(
        url: 'https://example.com/live.m3u8',
        outputDirectory: '/r',
        segmentPattern: 'p_%06d.ts',
        journalPath: '/r/p.csv',
      );
      final all = const FfmpegRecordArguments(config: FfmpegRecordConfig(preferBestStream: false)).recordArguments(
        url: 'https://example.com/live.m3u8',
        outputDirectory: '/r',
        segmentPattern: 'p_%06d.ts',
        journalPath: '/r/p.csv',
      );

      expect(preferred, contains('0:v:0?'));
      expect(preferred, contains('0:a:0?'));
      expect(all, contains('0:v?'));
      expect(all, contains('0:a?'));
    });

    test('arms reconnect for HTTP and only for HTTP', () {
      final http = builder.inputProtocolOptions('https://example.com/live.m3u8');
      final rtsp = builder.inputProtocolOptions('rtsp://example.com/live');
      final udp = builder.inputProtocolOptions('udp://239.0.0.1:1234');

      expect(http, contains('-reconnect'));
      expect(http, contains('-reconnect_on_http_error'));
      expect(http[http.indexOf('-reconnect_on_http_error') + 1], '5xx', reason: 'only server failures are retried');
      expect(rtsp, contains('-rtsp_transport'));
      expect(rtsp, isNot(contains('-reconnect')), reason: 'a live RTSP input has nothing to resume');
      expect(udp, contains('-overrun_nonfatal'));
    });

    test('clamps the segment time and queue size', () {
      final arguments = const FfmpegRecordArguments(config: FfmpegRecordConfig(segmentTime: 1, threadQueueSize: 1))
          .recordArguments(
            url: 'https://e.com/a.m3u8',
            outputDirectory: '/r',
            segmentPattern: 'p.ts',
            journalPath: '/r/p.csv',
          );

      expect(arguments[arguments.indexOf('-segment_time') + 1], '10');
      expect(arguments[arguments.indexOf('-thread_queue_size') + 1], '64');
    });

    test('adds discontinuity handling only for network inputs', () {
      final network = builder.recordArguments(
        url: 'https://e.com/a.m3u8',
        outputDirectory: '/r',
        segmentPattern: 'p.ts',
        journalPath: '/r/p.csv',
      );
      final local = builder.recordArguments(
        url: 'file:///tmp/a.ts',
        outputDirectory: '/r',
        segmentPattern: 'p.ts',
        journalPath: '/r/p.csv',
      );

      expect(network, contains('-dts_delta_threshold'));
      expect(local, isNot(contains('-dts_delta_threshold')));
    });

    test('separates the user agent from the header block', () {
      final arguments = builder.recordArguments(
        url: 'https://e.com/a.m3u8',
        outputDirectory: '/r',
        segmentPattern: 'p_%06d.ts',
        journalPath: '/r/p.csv',
        headers: <String, String>{'User-Agent': 'PureLive/1.0', 'Referer': 'https://e.com/'},
      );

      expect(arguments[arguments.indexOf('-user_agent') + 1], 'PureLive/1.0');
      final headerBlock = arguments[arguments.indexOf('-headers') + 1];
      expect(headerBlock, contains('referer: https://e.com/'));
      expect(headerBlock, isNot(contains('user-agent')), reason: 'the agent has its own option');
      expect(headerBlock, endsWith('\r\n'));
    });

    test('a hostile header is refused, not rewritten or dropped', () {
      // The rule belongs to the framework (HttpHeaderSanitizer): send it exactly
      // as given or fail. A rewritten value is one the site never issued, and
      // a dropped one is usually the credential — which surfaces later as an
      // unexplained 403 instead of as the caller's bug.
      expect(
        () => FfmpegRecordArguments.normalizeHeaders(<String, String>{'X-Bad\nInjected': 'value'}),
        throwsA(isA<HttpHeaderError>()),
      );
      expect(
        () => FfmpegRecordArguments.normalizeHeaders(<String, String>{'X-Inject': 'a\r\nX-Evil: 1'}),
        throwsA(isA<HttpHeaderError>()),
      );
      expect(
        () => FfmpegRecordArguments.normalizeHeaders(<String, String>{'X-Empty': '   '}),
        throwsA(isA<HttpHeaderError>()),
      );
    });

    test('clean headers pass through with lower-cased names', () {
      final normalized = FfmpegRecordArguments.normalizeHeaders(<String, String>{
        'X-Ok': 'value',
        'Referer': 'https://e.example/',
      });

      expect(normalized.keys, containsAll(<String>['x-ok', 'referer']));
      expect(FfmpegRecordArguments.buildHeader(normalized), contains('x-ok: value\r\n'));
    });

    test('keeps a hostile file prefix inside the output directory', () {
      expect(FfmpegRecordArguments.safeFilePrefix('../../etc/passwd'), 'etc_passwd');
      expect(FfmpegRecordArguments.safeFilePrefix('my room: live!'), 'my_room_live');
      expect(FfmpegRecordArguments.safeFilePrefix('///'), isNotEmpty, reason: 'falls back to a timestamp');
    });

    test('builds the audio relay for a single track', () {
      final arguments = builder.audioRelayArguments(url: 'https://e.com/a.m3u8', port: 8099);

      expect(arguments, contains('-vn'));
      expect(arguments[arguments.indexOf('-c:a') + 1], 'copy');
      expect(arguments, contains('http://127.0.0.1:8099/live.ts'));
    });

    test('formats arguments for logs without changing the list', () {
      final formatted = FfmpegRecordArguments.formatArguments(<String>['-i', 'a b.mp4']);

      expect(formatted, '-i "a b.mp4"');
    });
  });

  group('output paths', () {
    test('a directory keeps its own separator style', () {
      expect(joinOutputPath(r'C:\recordings', 'room_000000.ts'), r'C:\recordings\room_000000.ts');
      expect(joinOutputPath('/recordings', 'room_000000.ts'), '/recordings/room_000000.ts');
      expect(outputDirectoryOf(r'C:\recordings\room.clock-v1.csv'), r'C:\recordings');
      expect(outputDirectoryOf('/recordings/room.clock-v1.csv'), '/recordings');
    });

    test('a directory that already ends in a separator is not doubled', () {
      expect(joinOutputPath('/recordings/', 'a.ts'), '/recordings/a.ts');
      expect(joinOutputPath(r'C:\recordings\', 'a.ts'), r'C:\recordings\a.ts');
    });
  });

  group('FfmpegSegmentJournal', () {
    late Directory directory;
    late File journal;

    setUp(() {
      directory = _tempDirectory();
      journal = File(joinOutputPath(directory.path, 'room.clock-v1.csv'));
    });

    test('reads the segments FFmpeg listed, in order', () {
      File(joinOutputPath(directory.path, 'big.ts')).writeAsBytesSync(List<int>.filled(5000, 0));
      File(joinOutputPath(directory.path, 'small.ts')).writeAsBytesSync(List<int>.filled(11, 0));
      journal.writeAsStringSync("file,'big.ts'\nfile,'small.ts'\n");

      final read = FfmpegSegmentJournal.fromFile(journal);

      expect(read.length, 2);
      expect(read.entries.map((entry) => entry.name), <String>['big.ts', 'small.ts']);
      expect(read.first!.bytes, 5000);
      expect(read.last!.name, 'small.ts');
      expect(read.totalBytes, 5011);
      expect(read.unreadableLines, 0);
    });

    test('a name with a comma inside it survives quoting', () {
      File(joinOutputPath(directory.path, 'a,b.ts')).writeAsBytesSync(List<int>.filled(64, 0));
      journal.writeAsStringSync("file,'a,b.ts'\n");

      expect(FfmpegSegmentJournal.fromFile(journal).entries.single.name, 'a,b.ts');
    });

    test('a half-written last line is counted, not fatal', () {
      File(joinOutputPath(directory.path, 'a.ts')).writeAsBytesSync(List<int>.filled(64, 0));
      journal.writeAsStringSync("file,'a.ts'\nfile,'par");

      final read = FfmpegSegmentJournal.fromFile(journal);

      expect(read.length, 1);
      expect(read.unreadableLines, 1);
    });

    test('a listed segment that is gone reads as zero bytes', () {
      journal.writeAsStringSync("file,'gone.ts'\n");

      final read = FfmpegSegmentJournal.fromFile(journal);

      expect(read.entries.single.isPresent, isFalse);
      expect(read.totalBytes, 0);
    });

    test('a missing journal is an empty journal', () {
      expect(FfmpegSegmentJournal.fromFile(File(joinOutputPath(directory.path, 'none.csv'))).isEmpty, isTrue);
    });
  });

  group('FfmpegRecordingCheck', () {
    late Directory directory;
    late File journal;

    setUp(() {
      directory = _tempDirectory();
      journal = File(joinOutputPath(directory.path, 'room.clock-v1.csv'));
    });

    Future<FfmpegRecordingCheck> check({FfmpegProbe? probe}) => FfmpegRecordingCheck.evaluate(
      journal: FfmpegSegmentJournal.fromFile(journal),
      claimedDuration: const Duration(minutes: 10),
      probe: probe,
    );

    test('output that is all there is complete', () async {
      _writeOutput(<String>['-segment_list', journal.path, '${directory.path}${Platform.pathSeparator}room_%06d.ts']);

      final result = await check(probe: _FakeProbe());

      expect(result.verdict, FfmpegRecordingVerdict.complete);
      expect(result.isUsable, isTrue);
      expect(result.reason, isNull);
      expect(result.bytesOnDisk, 2 * 8192);
    });

    test('a journal with nothing in it is missing output, and says why', () async {
      journal.writeAsStringSync('');

      final result = await check();

      expect(result.verdict, FfmpegRecordingVerdict.missing);
      expect(result.isUsable, isFalse);
      expect(result.reason, contains('closed no segment'));
    });

    test('an input that delivered nothing is told apart from a short stream', () async {
      journal.writeAsStringSync('');

      final result = await FfmpegRecordingCheck.evaluate(journal: FfmpegSegmentJournal.fromFile(journal));

      expect(result.reason, contains('the input delivered nothing'));
    });

    test('a segment the journal lists but the disk lacks makes the recording suspicious', () async {
      _writeOutput(
        <String>['-segment_list', journal.path, '${directory.path}${Platform.pathSeparator}room_%06d.ts'],
        segments: 3,
        dropLastSegment: true,
      );

      final result = await check(probe: _FakeProbe());

      expect(result.verdict, FfmpegRecordingVerdict.suspicious);
      expect(result.isUsable, isTrue, reason: 'the other segments are still a recording');
      expect(result.missingSegments, 1);
      expect(result.reason, contains('not on disk'));
    });

    test('a segment too small to decode is a stub, not output', () async {
      final pattern = '${directory.path}${Platform.pathSeparator}room_%06d.ts';
      _writeOutput(<String>['-segment_list', journal.path, pattern], bytes: 64);

      final result = await check(probe: _FakeProbe());

      expect(result.stubSegments, 2);
      expect(result.verdict, FfmpegRecordingVerdict.suspicious);
    });

    test('every segment missing is no recording even though the journal has names', () async {
      _writeOutput(<String>[
        '-segment_list',
        journal.path,
        '${directory.path}${Platform.pathSeparator}room_%06d.ts',
      ], dropLastSegment: true);
      File(joinOutputPath(directory.path, 'room_000000.ts')).deleteSync();

      final result = await check();

      expect(result.verdict, FfmpegRecordingVerdict.missing);
    });

    test('a probe that cannot open a segment makes the verdict suspicious', () async {
      _writeOutput(<String>['-segment_list', journal.path, '${directory.path}${Platform.pathSeparator}room_%06d.ts']);

      final result = await check(probe: _FakeProbe(canRead: false));

      expect(result.verdict, FfmpegRecordingVerdict.suspicious);
      expect(result.unreadableSegments, greaterThan(0));
      expect(result.reason, contains('FFprobe could not open'));
    });

    test('without a probe the check is a filesystem statement, not a decode', () async {
      _writeOutput(<String>['-segment_list', journal.path, '${directory.path}${Platform.pathSeparator}room_%06d.ts']);

      expect((await check()).verdict, FfmpegRecordingVerdict.complete);
    });
  });

  group('FfmpegRecordingBackend', () {
    late _FakeExecutor executor;
    late Directory directory;
    late FfmpegRecordingBackend backend;

    setUp(() {
      executor = _FakeExecutor()..onStart = _writeOutput;
      directory = _tempDirectory();
      backend = FfmpegRecordingBackend(
        executor: executor,
        // restartLimit 0 keeps this group about one process: an end nobody asked
        // for is terminal here, and the re-opening has its own group.
        config: const FfmpegRecordConfig(filePrefix: 'room', restartLimit: 0),
        outputDirectory: directory.path,
        probe: _FakeProbe(),
      );
    });

    tearDown(() => backend.dispose());

    group('tells the notification layer how it ended', () {
      late _CapturingReporter reporter;

      setUp(() {
        reporter = _CapturingReporter();
        MediaJobReporting.reporter = reporter;
      });

      tearDown(MediaJobReporting.reset);

      test('a stopped recording reports the verdict it returned, not the exit code', () async {
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());
        executor.lastStatistics!(const FfmpegStatistics(timeMs: 6500, sizeBytes: 2048));

        final result = await backend.stop();

        expect(reporter.seen, hasLength(1));
        expect(reporter.seen.single.kind, MediaJobKind.recording);
        expect(reporter.seen.single.label, 'room');
        expect(
          reporter.seen.single.success,
          result.success,
          reason: 'the line the viewer reads and the result the host got answer the same question',
        );
        expect(reporter.seen.single.elapsed, result.duration);
      });

      test('a stream that ended on its own is announced once, and a later stop does not repeat it', () async {
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        // Nobody asked for this end, and restartLimit is 0: the give-up is the
        // recording's own terminal verdict.
        executor.executions.single.finish(255);
        await _waitUntilTerminal(backend);

        expect(reporter.seen, hasLength(1));
        expect(reporter.seen.single.success, isFalse);

        await backend.stop();

        expect(reporter.seen, hasLength(1), reason: 'one recording is one line, however it was ended');
      });

      test('nobody listening does not change what stop returns', () async {
        MediaJobReporting.reset();
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        final result = await backend.stop();

        expect(result.success, isTrue);
      });
    });

    test('starts a recording and reports progress from statistics', () async {
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());

      expect(executor.initialized, isTrue);
      expect(backend.state.status, RecordingStatus.recording);

      executor.lastStatistics!(const FfmpegStatistics(timeMs: 4200, sizeBytes: 1024 * 512));

      expect(backend.state.duration, const Duration(milliseconds: 4200));
      expect(backend.state.bytesWritten, 1024 * 512);
    });

    test('writes into the configured directory and creates it', () async {
      final nested = Directory('${directory.path}${Platform.pathSeparator}new${Platform.pathSeparator}room');
      await backend.initialize();

      await backend.start(_source(), RecordingConfig(outputPath: nested.path));

      expect(nested.existsSync(), isTrue);
      expect(
        executor.executions.single.arguments.any((argument) => argument.startsWith(nested.path)),
        isTrue,
        reason: 'the segment pattern and journal are written under the configured directory',
      );
    });

    test('refuses a second concurrent recording', () async {
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());

      await expectLater(backend.start(_source(), const RecordingConfig()), throwsA(isA<StateError>()));
    });

    test('refuses a local file source', () async {
      await backend.initialize();

      await expectLater(
        backend.start(const RecordingSource.file('/tmp/a.ts'), const RecordingConfig()),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('refuses to start without a directory', () async {
      final homeless = FfmpegRecordingBackend(executor: executor);
      addTearDown(homeless.dispose);
      await homeless.initialize();

      await expectLater(homeless.start(_source(), const RecordingConfig()), throwsA(isA<StateError>()));
    });

    test('a source that restarts its timeline does not freeze the notification', () async {
      final lease = _FakeLease();
      final protected = FfmpegRecordingBackend(
        executor: executor,
        config: const FfmpegRecordConfig(filePrefix: 'room'),
        outputDirectory: directory.path,
        keepAliveStarter: ({required notification, wakeLock = false}) async => lease,
        probe: _FakeProbe(),
      );
      addTearDown(protected.dispose);

      await protected.initialize();
      await protected.start(_source(), const RecordingConfig());

      executor.lastStatistics!(const FfmpegStatistics(timeMs: 5000, sizeBytes: 1024));
      executor.lastStatistics!(const FfmpegStatistics(timeMs: 12000, sizeBytes: 2048));
      final before = lease.texts.length;
      expect(before, greaterThanOrEqualTo(2), reason: 'the line moves once per second of media');

      // The live source dropped and re-opened: its clock is behind the last
      // reported point. Without the jump check the arithmetic reads "not due
      // yet" for the rest of the recording, and the line stops moving.
      executor.lastStatistics!(const FfmpegStatistics(timeMs: 2000, sizeBytes: 4096));
      executor.lastStatistics!(const FfmpegStatistics(timeMs: 4000, sizeBytes: 8192));

      expect(
        lease.texts.length,
        greaterThan(before),
        reason: 'a restarted timeline must re-open the update window, not wait it out',
      );
      expect(lease.texts.last, contains('00:00:04'));
    });

    test('a user stop is a successful recording', () async {
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());
      executor.lastStatistics!(const FfmpegStatistics(timeMs: 9000, sizeBytes: 2048));

      final result = await backend.stop();

      expect(executor.executions.single.stopCalled, isTrue);
      expect(result.success, isTrue, reason: 'the viewer ended it on purpose and the segments are there');
      expect(result.duration, const Duration(milliseconds: 9000));
      expect(result.outputPath, backend.activeDirectory);
      expect(backend.lastCheck?.verdict, FfmpegRecordingVerdict.complete);
      expect(backend.state.status, RecordingStatus.completed);
    });

    test('the reported size is the files on disk, not the muxer counter', () async {
      // The status line's `size=` is the muxer's own byte counter, which for a
      // segmented capture describes the child file being written — a recording
      // reported at that figure is reported at a fraction of itself.
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());
      executor.lastStatistics!(const FfmpegStatistics(timeMs: 9000, sizeBytes: 2048));

      final result = await backend.stop();

      expect(result.bytesWritten, 2 * 8192, reason: 'two segments of 8192 B were left on disk');
    });

    test('a stop that wrote nothing is not reported as a success', () async {
      // The recording the user pressed stop on had no output behind it: a
      // process that was killed looks exactly like one that captured something,
      // and only the directory knows.
      executor.onStart = null;
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());
      executor.lastStatistics!(const FfmpegStatistics(timeMs: 5000));

      final result = await backend.stop();

      expect(result.success, isFalse);
      expect(result.error, isA<FfmpegRecordingFailure>());
      expect(backend.lastCheck?.verdict, FfmpegRecordingVerdict.missing);
      expect(backend.state.status, RecordingStatus.error);
    });

    test('a partial recording is still a recording, with the hole named', () async {
      executor.onStart = (arguments) => _writeOutput(arguments, segments: 3, dropLastSegment: true);
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());

      final result = await backend.stop();

      expect(result.success, isTrue);
      expect(backend.lastCheck?.verdict, FfmpegRecordingVerdict.suspicious);
      expect(backend.lastCheck?.missingSegments, 1);
      expect(result.error, isNull, reason: 'usable output is not an error');
    });

    test('a process that had already failed is an error even when stopped by hand', () async {
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());
      // The input died first, so ending the process reports a failure code
      // rather than the 255 a kill produces - and usable segments behind it do
      // not make the recording whole.
      executor.executions.single.stopExitCode = 1;

      final result = await backend.stop();

      expect(result.success, isFalse);
      expect(result.error.toString(), contains('1'));
      expect(backend.state.status, RecordingStatus.error);
    });

    test('cancel is not a successful recording', () async {
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());

      await backend.cancel();

      expect(executor.executions.single.cancelCalled, isTrue);
      expect(backend.state.status, RecordingStatus.cancelled);
      expect(backend.state.status.isTerminal, isTrue, reason: 'cancelled is a terminal state');
      expect(backend.state.isCompleted, isFalse, reason: 'but it is not a completed recording');
    });

    test('a process that ends on its own reports success for code 0', () async {
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());

      executor.executions.single.finish(0);
      await _settle();

      expect(backend.state.status, RecordingStatus.completed);
      expect(backend.state.error, isNull);
      expect(backend.lastCheck?.segments, 2);
    });

    test('a clean exit with nothing written is not a completed recording', () async {
      executor.onStart = null;
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());

      executor.executions.single.finish(0);
      await _settle();

      expect(backend.state.status, RecordingStatus.error);
      expect(backend.state.error, isA<FfmpegRecordingFailure>());
    });

    test('a process that dies reports an error with the code', () async {
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());

      executor.executions.single.finish(255);
      await _settle();

      expect(backend.state.status, RecordingStatus.error);
      expect(backend.state.error.toString(), contains('255'));
    });

    test('an error from the previous attempt does not survive a new start', () async {
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());
      executor.executions.single.finish(1);
      await _settle();
      expect(backend.state.hasError, isTrue);

      await backend.start(_source(), const RecordingConfig());

      expect(backend.state.status, RecordingStatus.recording);
      expect(backend.state.error, isNull);
      expect(backend.lastCheck, isNull, reason: "the previous verdict is not the next recording's");
    });

    test('verification can be switched off', () async {
      final unchecked = FfmpegRecordingBackend(
        executor: executor,
        config: const FfmpegRecordConfig(filePrefix: 'room', verifyOutput: false),
        outputDirectory: directory.path,
      );
      addTearDown(unchecked.dispose);
      await unchecked.initialize();
      await unchecked.start(_source(), const RecordingConfig());

      final result = await unchecked.stop();

      expect(result.success, isTrue, reason: 'without a check the exit code is all there is');
      expect(unchecked.lastCheck, isNull);
    });

    test('playability is only asked of the first and last segment', () async {
      final probing = _CountingProbe();
      final probed = FfmpegRecordingBackend(
        executor: _FakeExecutor()..onStart = (arguments) => _writeOutput(arguments, segments: 6),
        config: const FfmpegRecordConfig(filePrefix: 'room'),
        outputDirectory: directory.path,
        probe: probing,
      );
      addTearDown(probed.dispose);
      await probed.initialize();
      await probed.start(_source(), const RecordingConfig());

      await probed.stop();

      expect(probing.paths.length, 2, reason: 'a day-long recording must not cost one FFprobe call per segment');
    });

    test('a probe that cannot reach FFprobe degrades to the filesystem check', () async {
      final unready = FfmpegRecordingBackend(
        executor: executor,
        config: const FfmpegRecordConfig(filePrefix: 'room'),
        outputDirectory: directory.path,
        probe: _FakeProbe(canRead: false),
      );
      addTearDown(unready.dispose);
      await unready.initialize();
      await unready.start(_source(), const RecordingConfig());

      final result = await unready.stop();

      expect(result.success, isTrue, reason: 'the files are all there; only the decode claim is missing');
      expect(unready.lastCheck?.verdict, FfmpegRecordingVerdict.suspicious);
    });

    test('reports state transitions to listeners', () async {
      await backend.initialize();
      final seen = <RecordingStatus>[];
      backend.onStateChanged.listen((state) => seen.add(state.status));

      await backend.start(_source(), const RecordingConfig());
      await backend.stop();
      await Future<void>.delayed(Duration.zero);

      expect(
        seen,
        containsAllInOrder(<RecordingStatus>[
          RecordingStatus.starting,
          RecordingStatus.recording,
          RecordingStatus.stopping,
          RecordingStatus.completed,
        ]),
      );
    });

    test('dispose ends a running recording', () async {
      await backend.initialize();
      await backend.start(_source(), const RecordingConfig());

      await backend.dispose();

      expect(executor.executions.single.cancelCalled, isTrue);
      expect(executor.disposeCount, 1);
    });
    group('re-opening a dropped source', () {
      // Backoff is zero so a test does not wait on the delay it is there for.
      const recovering = FfmpegRecordConfig(
        filePrefix: 'room',
        restartBackoff: Duration.zero,
        restartBackoffMax: Duration.zero,
      );

      FfmpegRecordingBackend live(
        _FakeExecutor runner, {
        FfmpegRecordConfig? config,
        UrlRefresher? urlRefresher,
        DiskSpaceProbe? diskSpace,
      }) {
        final built = FfmpegRecordingBackend(
          executor: runner,
          config: config ?? recovering,
          outputDirectory: directory.path,
          probe: _FakeProbe(),
          urlRefresher: urlRefresher,
          diskSpace: diskSpace,
        );
        addTearDown(built.dispose);

        return built;
      }

      test('a source that ends on its own is started again', () async {
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(runner);
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        runner.executions.first.finish(255);
        await _settle();

        expect(runner.executions.length, 2, reason: 'a dropped stream is the source failing, not the recording');
        expect(backend.state.status, RecordingStatus.recording);
        expect(backend.attempts, 2);
      });

      test('each attempt writes its own segments and its own journal', () async {
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(runner);
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        runner.executions.first.finish(255);
        await _settle();

        final first = runner.executions.first.arguments;
        final second = runner.executions.last.arguments;

        expect(first.last, contains('room_'));
        expect(second.last, contains('room_r1_'), reason: 'the re-opened stream must not overwrite the first files');
        expect(
          second[second.indexOf('-segment_list') + 1],
          isNot(first[first.indexOf('-segment_list') + 1]),
          reason: 'FFmpeg rewrites its whole list, so two attempts cannot share one journal',
        );
      });

      test('the recording is the sum of its attempts', () async {
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(runner);
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        // Each process counts its own timeline from zero, so the last attempt's
        // clock is not the recording's.
        runner.lastStatistics!(const FfmpegStatistics(timeMs: 5000, sizeBytes: 64));
        runner.executions.first.finish(255);
        await _settle();
        runner.lastStatistics!(const FfmpegStatistics(timeMs: 4000, sizeBytes: 64));

        final result = await backend.stop();

        expect(result.duration, const Duration(seconds: 9));
        expect(result.bytesWritten, 4 * 8192);
        expect(backend.lastCheck?.segments, 4);
        expect(backend.lastCheck?.verdict, FfmpegRecordingVerdict.complete);
      });

      test('a run that got going does not count against the limit', () async {
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(
          runner,
          config: recovering.copyWith(restartLimit: 1, healthyAfter: const Duration(seconds: 2)),
        );
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        runner.lastStatistics!(const FfmpegStatistics(timeMs: 3000, sizeBytes: 64));
        runner.executions.first.finish(255);
        await _settle();
        // The second attempt dies immediately, but the first reached
        // healthyAfter, so the count was reset and this is attempt three of a
        // working recording rather than the end of one.
        runner.executions.last.finish(255);
        await _settle();

        expect(runner.executions.length, 3);
        expect(backend.state.status, RecordingStatus.recording);
      });

      test('quick failures give up and name the attempts', () async {
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(runner, config: recovering.copyWith(restartLimit: 2));
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        for (var attempt = 0; attempt < 5; attempt++) {
          runner.executions.last.finish(255);
          await _settle();
        }

        expect(runner.executions.length, 3, reason: 'the first run plus two re-openings');
        expect(backend.state.status, RecordingStatus.error);
        expect(backend.state.error, isA<FfmpegRecordingGaveUpException>());
        expect(backend.state.error.toString(), contains('3 attempt'));
        expect(backend.state.duration, Duration.zero, reason: 'no attempt ever reported media time');
      });

      test('the host is asked for a fresh address before each re-opening', () async {
        var refreshes = 0;
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(
          runner,
          urlRefresher: (source) async {
            refreshes++;

            return 'https://example.com/live/fresh.flv';
          },
        );
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        runner.executions.first.finish(255);
        await _settle();

        expect(refreshes, 1);
        final arguments = runner.executions.last.arguments;
        expect(arguments[arguments.indexOf('-i') + 1], 'https://example.com/live/fresh.flv');
      });

      test('a source the host cannot refresh ends the recording', () async {
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(runner, urlRefresher: (source) async => null);
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        runner.executions.first.finish(255);
        await _settle();

        expect(
          runner.executions.length,
          1,
          reason: 're-opening an address that will not work is a retry that cannot succeed',
        );
        expect(backend.state.error, isA<FfmpegRecordingGaveUpException>());
        expect(backend.state.error.toString(), contains('could not be refreshed'));
      });

      test('a disk that fills up stops the recovery instead of looping', () async {
        var probes = 0;
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(
          runner,
          diskSpace: (directory) async {
            probes++;

            // Room enough when the recording started, none left by the drop.
            return probes == 1 ? 1 << 30 : 1024;
          },
        );
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        runner.executions.first.finish(255);
        await _settle();

        expect(runner.executions.length, 1);
        expect(backend.state.error.toString(), contains('DiskFull'));
        expect(backend.state.error.toString(), contains('segment(s)'));
      });

      test('a volume with no room is refused before the first segment', () async {
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(runner, diskSpace: (directory) async => 1024);
        await backend.initialize();

        await expectLater(
          backend.start(_source(), const RecordingConfig()),
          throwsA(isA<FfmpegRecordingDiskFullException>()),
        );
        expect(runner.executions, isEmpty);
      });

      test('a stop while waiting to re-open keeps what was written', () async {
        final runner = _FakeExecutor()..onStart = _writeOutput;
        // A delay a test can be sure to land inside - and the ceiling has to be
        // raised with it, because the ceiling is what `backoff` clamps to.
        final backend = live(
          runner,
          config: recovering.copyWith(
            restartBackoff: const Duration(seconds: 30),
            restartBackoffMax: const Duration(seconds: 30),
          ),
        );
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        runner.executions.first.finish(255);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final result = await backend.stop();

        expect(result.success, isTrue, reason: 'the segments already on disk are the recording the user stopped');
        expect(result.bytesWritten, 2 * 8192);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(runner.executions.length, 1, reason: 'a wait the user ended must not start a process again');
      });

      test('the watchdog ends an input that stops advancing', () async {
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(runner, config: recovering.copyWith(stallTimeout: const Duration(milliseconds: 300)));
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        // Nothing arrives: no statistics at all, so neither media time nor bytes
        // ever advance, and FFmpeg's own read timeout has nothing to time out on.
        // Half a window past the trip, and short of the next one: the point is the
        // replacement, not how many replacements a long wait would produce.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        expect(runner.executions.length, 2, reason: 'a stalled input is replaced, not waited on');
        expect(runner.executions.first.cancelCalled, isTrue);
      });

      test('statistics that repeat the last figures do not feed the watchdog', () async {
        final runner = _FakeExecutor()..onStart = _writeOutput;
        final backend = live(runner, config: recovering.copyWith(stallTimeout: const Duration(milliseconds: 300)));
        await backend.initialize();
        await backend.start(_source(), const RecordingConfig());

        // The input is idle but still reporting the same figures every 100 ms.
        // A timer reset by reports rather than by progress would never fire,
        // which is the difference this loop is here to keep honest.
        for (var tick = 0; tick < 8; tick++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          runner.lastStatistics!(const FfmpegStatistics(timeMs: 1000, sizeBytes: 4096));
        }

        expect(
          runner.executions.length,
          greaterThanOrEqualTo(2),
          reason: 'a report that repeats the last figures is not progress',
        );
        expect(runner.executions.first.cancelCalled, isTrue);
      });
    });
  });
}

/// A probe that counts what it was asked about.
final class _CountingProbe implements FfmpegProbe {
  final List<String> paths = <String>[];

  @override
  Future<Duration?> durationOf(String path) async {
    paths.add(path);

    return const Duration(seconds: 30);
  }
}
