import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_recording_ffmpeg/media_core_recording_ffmpeg.dart';

/// The findings that came with the container, naming, manifest and segment-event
/// work. They are kept apart from the lifecycle suite because they are about the
/// argument list and the files a recording leaves, not about its process.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('media_core_recording_names');
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
  });

  FfmpegRecordingBackend backendFor(
    _RecordingExecutor executor, {
    FfmpegRecordConfig config = const FfmpegRecordConfig(filePrefix: 'room'),
  }) {
    final built = FfmpegRecordingBackend(
      executor: executor,
      config: config,
      outputDirectory: directory.path,
      probe: const _NoProbe(),
    );
    addTearDown(built.dispose);

    return built;
  }

  group('file names', () {
    test('a room title in another script keeps its name', () {
      // The rule that mattered: an ASCII-only whitelist folded every Chinese room
      // title to `_`, so a day of recordings shared one file name.
      expect(FfmpegRecordArguments.safeFilePrefix('主播 房间 8891'), '主播_房间_8891');
      expect(FfmpegRecordArguments.safeFilePrefix('Трансляция #3'), 'Трансляция_3');
    });

    test('what a filesystem or a shell would act on is still dropped', () {
      expect(FfmpegRecordArguments.safeFilePrefix('../../etc/passwd'), 'etc_passwd');
      expect(FfmpegRecordArguments.safeFilePrefix('a/b?c=d:e*f<g>h|i'), 'a_b_c_d_e_f_g_h_i');
      expect(FfmpegRecordArguments.safeFilePrefix('rm -rf /'), 'rm_-rf');
      expect(FfmpegRecordArguments.safeFilePrefix('   '), isNotEmpty, reason: 'falls back to a generated name');
    });

    test('a title that needs no cleaning is left alone', () {
      expect(FfmpegRecordArguments.safeFilePrefix('room-8891_live'), 'room-8891_live');
    });

    test('a long title is cut, not wrapped', () {
      final long = FfmpegRecordArguments.safeFilePrefix(List<String>.filled(400, '标').join());

      expect(
        long.runes.length,
        lessThanOrEqualTo(FfmpegRecordArguments.maxFilePrefixLength),
        reason: 'a segment name repeats the prefix, and a long path stops working on Windows',
      );
    });

    test('a generated prefix follows the timestamp switch', () {
      final at = DateTime(2026, 10, 13, 18, 22, 32, 915);

      expect(FfmpegRecordArguments.generatedPrefix(FfmpegRecordConfig.defaults, at), '20261013_182232_915');
      expect(
        FfmpegRecordArguments.generatedPrefix(const FfmpegRecordConfig(includeTimestampPrefix: false), at),
        'recording',
        reason: 'a host with one directory per recording does not want the time twice',
      );
      expect(
        FfmpegRecordArguments.filePrefixFor(const FfmpegRecordConfig(filePrefix: 'room 8891'), now: at),
        'room_8891',
      );
    });
  });

  group('containers', () {
    test('MPEG-TS is the default and keeps its flushed child options', () {
      final arguments = const FfmpegRecordArguments().recordArguments(
        url: 'https://e.com/a.m3u8',
        outputDirectory: '/r',
        segmentPattern: 'p_%06d.ts',
        journalPath: '/r/p.csv',
      );

      expect(arguments[arguments.indexOf('-segment_format') + 1], 'mpegts');
      expect(arguments[arguments.indexOf('-segment_format_options') + 1], contains('flush_packets=1'));
      expect(FfmpegRecordConfig.defaults.resolvedSegmentSuffix, '.clock-v1.ts');
    });

    test('fragmented MP4 asks for self-describing fragments', () {
      const config = FfmpegRecordConfig(container: FfmpegRecordContainer.mp4Fragmented);
      final arguments = const FfmpegRecordArguments(config: config).recordArguments(
        url: 'https://e.com/a.m3u8',
        outputDirectory: '/r',
        segmentPattern: 'p_%06d.mp4',
        journalPath: '/r/p.csv',
      );

      expect(arguments[arguments.indexOf('-segment_format') + 1], 'mp4');
      expect(
        arguments[arguments.indexOf('-segment_format_options') + 1],
        'movflags=frag_keyframe+empty_moov+default_base_moof',
        reason: 'without empty_moov the index is written at the end, which a killed process never reaches',
      );
      expect(arguments, isNot(contains('flush_packets=1')), reason: 'that flag belongs to TS only');
      expect(config.resolvedSegmentSuffix, '.clock-v1.mp4');
      expect(FfmpegRecordContainer.mp4Fragmented.isConcatenateByCopy, isFalse);
    });

    test('an explicit suffix still wins over the container default', () {
      const config = FfmpegRecordConfig(container: FfmpegRecordContainer.mp4Fragmented, segmentSuffix: '.fmp4');

      expect(config.resolvedSegmentSuffix, '.fmp4');
    });

    test('the backend names segments after the chosen container', () async {
      final executor = _RecordingExecutor();
      final backend = backendFor(
        executor,
        config: const FfmpegRecordConfig(filePrefix: 'room', container: FfmpegRecordContainer.mp4Fragmented),
      );

      await backend.initialize();
      await backend.start(const RecordingSource.network('https://e.com/a.m3u8'), const RecordingConfig());

      // The `%06d` stays: expanding it is FFmpeg's job, so the suffix is the part
      // this package decides.
      expect(executor.argumentLists.single.last, endsWith('_%06d.clock-v1.mp4'));
    });
  });

  group('directory layering', () {
    test('one recording gets its own directory when asked', () async {
      final executor = _RecordingExecutor();
      final backend = backendFor(
        executor,
        // The directory says when, so the file name does not have to.
        config: const FfmpegRecordConfig(
          filePrefix: '主播8891',
          subdirectoryPerRecording: true,
          includeTimestampPrefix: false,
        ),
      );

      await backend.initialize();
      await backend.start(const RecordingSource.network('https://e.com/a.m3u8'), const RecordingConfig());

      expect(backend.activeDirectory, joinFor(directory, '主播8891'));
      expect(Directory(backend.activeDirectory!).existsSync(), isTrue);
      expect(
        executor.argumentLists.single.last,
        contains('主播8891${Platform.pathSeparator}主播8891_%06d'),
        reason: 'the pattern FFmpeg is handed sits inside the per-recording directory',
      );
      expect(File(joinFor(Directory(backend.activeDirectory!), '主播8891.clock-v1.json')).existsSync(), isTrue);
    });

    test('flat output stays the default', () async {
      final backend = backendFor(_RecordingExecutor());

      await backend.initialize();
      await backend.start(const RecordingSource.network('https://e.com/a.m3u8'), const RecordingConfig());

      expect(backend.activeDirectory, directory.path);
    });
  });

  group('manifest', () {
    test('a recording writes what it is, and the file counts the attempts', () async {
      final executor = _RecordingExecutor();
      final backend = backendFor(
        executor,
        // A restart is what the attempt list exists for.
        config: const FfmpegRecordConfig(
          filePrefix: 'room',
          restartLimit: 1,
          restartBackoff: Duration.zero,
          restartBackoffMax: Duration.zero,
        ),
      );

      await backend.initialize();
      await backend.start(
        const RecordingSource.network('https://e.com/live/a.m3u8?sign=SECRET', id: 'room-8891'),
        const RecordingConfig(),
      );

      final file = File(joinFor(directory, 'room.clock-v1.json'));
      final manifest = FfmpegRecordingManifest.read(file);

      expect(manifest, isNotNull);
      expect(manifest!.prefix, 'room');
      expect(manifest.container, FfmpegRecordContainer.mpegTs);
      expect(manifest.attempts, 1);
      expect(manifest.journals.single, endsWith('room.clock-v1.csv'));
      expect(manifest.sourceLabel, 'room-8891');
      expect(file.readAsStringSync(), isNot(contains('SECRET')), reason: 'a signed URL must not land in a file');
      expect(manifest.startedAt.isAfter(DateTime.now().subtract(const Duration(minutes: 5))), isTrue);

      executor.executions.single.finish(255);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final second = FfmpegRecordingManifest.read(file);

      expect(second?.attempts, 2, reason: 'the manifest is rewritten, not appended');
      expect(second?.journals.length, 2);
      expect(second?.journals.last, endsWith('room_r1.clock-v1.csv'));
    });

    test('the manifest can be switched off', () async {
      final backend = backendFor(
        _RecordingExecutor(),
        config: const FfmpegRecordConfig(filePrefix: 'room', writeManifest: false),
      );

      await backend.initialize();
      await backend.start(const RecordingSource.network('https://e.com/a.m3u8'), const RecordingConfig());

      expect(File(joinFor(directory, 'room.clock-v1.json')).existsSync(), isFalse);
    });

    test('a half-written manifest reads as no manifest', () {
      File(joinFor(directory, 'room.clock-v1.json')).writeAsStringSync('{"schema": 1, "prefix": "roo');

      expect(FfmpegRecordingManifest.read(File(joinFor(directory, 'room.clock-v1.json'))), isNull);
    });

    test('a manifest from another schema is not read as this one', () {
      File(joinFor(directory, 'room.clock-v1.json')).writeAsStringSync('{"schema": 99, "prefix": "room"}');

      expect(FfmpegRecordingManifest.read(File(joinFor(directory, 'room.clock-v1.json'))), isNull);
    });

    test('a source without an id is labelled by host and path, never by its query', () {
      expect(
        recordingSourceLabel(const RecordingSource.network('https://live.example.com/room/a.flv?token=xyz')),
        'live.example.com/room/a.flv',
      );
    });
  });

  group('joining the segments', () {
    // A join writes one file, named by the last argument; the fake leaves that
    // file behind so the result has something real to measure.
    _RecordingExecutor remuxExecutor(int bytes) => _RecordingExecutor(
      onArguments: (arguments) {
        if (arguments.contains('concat')) {
          File(arguments.last).writeAsBytesSync(List<int>.filled(bytes, 0));
        }
      },
    );

    FfmpegRecordingManifest manifestFor(String prefix, List<String> journals) {
      return FfmpegRecordingManifest(
        prefix: prefix,
        container: FfmpegRecordContainer.mpegTs,
        segmentTime: 300,
        startedAt: DateTime(2026, 10, 13, 18, 22),
        sourceLabel: 'room-8891',
        journals: journals,
        attempts: journals.length,
      );
    }

    test('the join is a stream copy of the closed segments', () async {
      writeJournal(directory, 2);
      final executor = remuxExecutor(40 * 1024);

      final result = await FfmpegRecordingRemuxer(
        executor: executor,
        probe: const _NoProbe(),
      ).run(manifest: manifestFor('room', <String>['room.clock-v1.csv']), directory: directory.path);

      expect(result.success, isTrue);
      expect(result.skipped, isFalse);
      expect(result.bytesWritten, 40 * 1024, reason: 'the size is measured from the file, not reported by the muxer');

      final arguments = executor.argumentLists.single;

      expect(arguments[arguments.indexOf('-f') + 1], 'concat');
      expect(
        arguments[arguments.indexOf('-safe') + 1],
        '0',
        reason: 'the list names absolute paths, which the demuxer rejects by default',
      );
      expect(arguments, containsAll(<String>['-c', 'copy']), reason: 'a join must never re-encode');
      expect(
        arguments[arguments.indexOf('-map') + 1],
        '0:v:0?',
        reason: 'an audio-only room has no video track to demand',
      );
      expect(arguments.last, endsWith('room.combined.mp4'));
      expect(arguments, contains('-movflags'), reason: 'faststart, so a phone can seek before the file arrives');
    });

    test('the list names every attempt, oldest first, with usable separators', () async {
      writeJournal(directory, 2);
      writeJournal(directory, 2, prefix: 'room_r1');
      List<String>? list;
      final executor = _RecordingExecutor(
        onArguments: (arguments) {
          list = File(arguments[arguments.indexOf('-i') + 1]).readAsLinesSync();
          File(arguments.last).writeAsBytesSync(<int>[0]);
        },
      );

      final result = await FfmpegRecordingRemuxer(executor: executor, probe: const _NoProbe()).run(
        manifest: manifestFor('room', <String>['room.clock-v1.csv', 'room_r1.clock-v1.csv']),
        directory: directory.path,
      );

      expect(result.success, isTrue);
      expect(list, hasLength(4), reason: 'two segments per attempt, both attempts of one recording');
      expect(list!.first, contains('room_000000'));
      expect(list!.last, contains('room_r1_000001'));
      expect(list!.join(), isNot(contains(r'\')), reason: 'the concat parser reads a backslash as an escape');
    });

    test('the list file is not left behind', () async {
      writeJournal(directory, 1);

      await FfmpegRecordingRemuxer(
        executor: remuxExecutor(1024),
        probe: const _NoProbe(),
      ).run(manifest: manifestFor('room', <String>['room.clock-v1.csv']), directory: directory.path);

      expect(File(joinFor(directory, 'room.concat.txt')).existsSync(), isFalse);
    });

    test('an existing output is kept, not rebuilt', () async {
      writeJournal(directory, 1);
      File(joinFor(directory, 'room.combined.mp4')).writeAsBytesSync(List<int>.filled(7, 0));
      final executor = remuxExecutor(1024);

      final result = await FfmpegRecordingRemuxer(
        executor: executor,
        probe: const _NoProbe(),
      ).run(manifest: manifestFor('room', <String>['room.clock-v1.csv']), directory: directory.path);

      expect(result.success, isTrue);
      expect(result.skipped, isTrue);
      expect(executor.argumentLists, isEmpty, reason: 'a six-hour merge restarted on every launch is a battery drain');
    });

    test('a recording with no closed segment is not joined', () async {
      File(joinFor(directory, 'room.clock-v1.csv')).writeAsStringSync('');
      final executor = remuxExecutor(1024);

      final result = await FfmpegRecordingRemuxer(
        executor: executor,
        probe: const _NoProbe(),
      ).run(manifest: manifestFor('room', <String>['room.clock-v1.csv']), directory: directory.path);

      expect(result.success, isFalse);
      expect(result.error, isA<FfmpegRemuxException>());
      expect(
        executor.argumentLists,
        isEmpty,
        reason: 'the segment still open is not joinable, and inventing a file is worse',
      );
    });

    test('a process that left no output is a failure', () async {
      writeJournal(directory, 1);

      final result = await FfmpegRecordingRemuxer(
        executor: _RecordingExecutor(),
        probe: const _NoProbe(),
      ).run(manifest: manifestFor('room', <String>['room.clock-v1.csv']), directory: directory.path);

      expect(result.success, isFalse);
      expect(result.error.toString(), contains('no'));
    });

    test('the backend joins the recording it just finished', () async {
      final executor = _RecordingExecutor(
        onArguments: (arguments) {
          if (arguments.contains('concat')) {
            File(arguments.last).writeAsBytesSync(List<int>.filled(2048, 0));
          }
        },
      );
      final backend = backendFor(executor);

      await backend.initialize();
      await backend.start(const RecordingSource.network('https://e.com/a.m3u8'), const RecordingConfig());
      writeJournal(directory, 1);

      final result = await backend.combineLastRecording();

      expect(backend.lastManifest?.prefix, 'room');
      expect(result.success, isTrue);
      expect(result.outputPath, endsWith('room.combined.mp4'));
    });

    test('joining before anything was recorded says so instead of inventing a file', () async {
      final result = await backendFor(_RecordingExecutor()).combineLastRecording();

      expect(result.success, isFalse);
      expect(result.error.toString(), contains('no recording'));
    });
  });

  group('segment events', () {
    test('a segment is announced when the journal names it', () async {
      final backend = backendFor(_RecordingExecutor());

      final closed = <FfmpegJournalledSegment>[];
      backend.onSegmentClosed.listen(closed.add);

      await backend.initialize();
      await backend.start(const RecordingSource.network('https://e.com/a.m3u8'), const RecordingConfig());

      writeJournal(directory, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(closed.length, 1);
      expect(closed.single.name, 'room_000000.clock-v1.ts');
      expect(backend.segmentsClosed, 1);

      writeJournal(directory, 2);
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(closed.map((segment) => segment.index), <int>[0, 1]);
      expect(closed.last.bytes, 2 * 1024, reason: 'the size reported is the size the segment holds on disk');
    });

    test('the segment closed in the final second is announced before stop returns', () async {
      final backend = backendFor(_RecordingExecutor());

      final closed = <String>[];
      backend.onSegmentClosed.listen((segment) => closed.add(segment.name));

      await backend.initialize();
      await backend.start(const RecordingSource.network('https://e.com/a.m3u8'), const RecordingConfig());
      writeJournal(directory, 2);

      await backend.stop();

      expect(closed, <String>['room_000000.clock-v1.ts', 'room_000001.clock-v1.ts']);
    });

    test('cancel stops announcing, and nothing is announced twice', () async {
      final backend = backendFor(_RecordingExecutor());

      final closed = <String>[];
      backend.onSegmentClosed.listen((segment) => closed.add(segment.name));

      await backend.initialize();
      await backend.start(const RecordingSource.network('https://e.com/a.m3u8'), const RecordingConfig());

      writeJournal(directory, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await backend.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(closed, <String>['room_000000.clock-v1.ts']);
    });
  });
}

/// `<directory>/<name>`, in the platform's own separator.
String joinFor(Directory directory, String name) => '${directory.path}${Platform.pathSeparator}$name';

/// Writes a journal naming [count] segments, and the segments themselves at
/// 1 KiB per index — what FFmpeg leaves behind as it rolls.
void writeJournal(Directory directory, int count, {String prefix = 'room'}) {
  File(joinFor(directory, '$prefix.clock-v1.csv')).writeAsStringSync(journalText(count, prefix));

  for (var index = 0; index < count; index++) {
    File(joinFor(directory, segmentName(index, prefix))).writeAsBytesSync(List<int>.filled((index + 1) * 1024, 0));
  }
}

/// FFmpeg's list of every segment closed so far, rewritten whole each time.
String journalText(int count, [String prefix = 'room']) {
  return <String>[for (var index = 0; index < count; index++) "file,'${segmentName(index, prefix)}'"].join('\n');
}

String segmentName(int index, [String prefix = 'room']) => '${prefix}_${index.toString().padLeft(6, '0')}.clock-v1.ts';

/// A process that stays alive until the test ends it and writes no files, so a
/// test decides exactly what the journal holds at each moment.
final class _RecordingExecutor implements FfmpegExecutor {
  _RecordingExecutor({this.onArguments});

  final List<List<String>> argumentLists = <List<String>>[];
  final List<_RecordingExecution> executions = <_RecordingExecution>[];

  /// Called with every argument list, so a test can leave behind the files the
  /// process it stands in for would have written.
  final void Function(List<String> arguments)? onArguments;

  @override
  Future<void> initialize() async {}

  @override
  Future<FfmpegExecution> start({
    required List<String> arguments,
    void Function(FfmpegStatistics statistics)? onStatistics,
    void Function(String message)? onLog,
  }) async {
    argumentLists.add(arguments);
    onArguments?.call(arguments);
    // A join is a one-shot process: it reads the list, writes one file and exits,
    // so the fake ends it by itself instead of waiting for a stop.
    final execution = _RecordingExecution(autoFinish: arguments.contains('concat'));
    executions.add(execution);
    return execution;
  }

  @override
  Future<void> dispose() async {}
}

final class _RecordingExecution implements FfmpegExecution {
  _RecordingExecution({bool autoFinish = false}) {
    if (autoFinish) {
      finish(0);
    }
  }

  final Completer<int> _exit = Completer<int>();

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
  Future<void> stop() async => finish(255);

  @override
  Future<void> cancel() async => finish(255);
}

/// A probe that never reaches FFmpeg: the output checks in these tests are about
/// names and counts, and the native library is not present.
final class _NoProbe implements FfmpegProbe {
  const _NoProbe();

  @override
  Future<Duration?> durationOf(String path) async => null;
}
