import 'dart:io';

import 'package:media_core/media_core.dart';
import 'package:media_core_recording_ffmpeg/src/ffmpeg_executor.dart';
import 'package:media_core_recording_ffmpeg/src/ffmpeg_probe.dart';
import 'package:media_core_recording_ffmpeg/src/output_path.dart';
import 'package:media_core_recording_ffmpeg/src/recording_manifest.dart';
import 'package:media_core_recording_ffmpeg/src/recording_verification.dart';

/// The log module this file reports decisions through.
final LogModule _log = MediaCoreLog.of(LogCategory.recording);

/// What a remuxed file is written as.
///
/// Recording deliberately stays in a crash-safe container (see
/// `FfmpegRecordContainer`), which is not what a user wants to open or share.
/// This is the point where that trade is paid back.
enum FfmpegRemuxTarget {
  /// MP4 with `faststart`, so a phone player starts drawing a frame before the
  /// whole file has been read.
  mp4,

  /// Matroska: the container that accepts the widest set of codec combinations,
  /// for a recording whose streams a browser would refuse.
  matroska,

  /// MPEG-TS, for joining the segments of one recording into a single
  /// broadcast-style stream without any repacking.
  mpegTs,
}

/// The container's file-name extension and the options it needs on the way out.
extension FfmpegRemuxTargetFormat on FfmpegRemuxTarget {
  /// Extension of the produced file, without the dot.
  String get extension => switch (this) {
    FfmpegRemuxTarget.mp4 => 'mp4',
    FfmpegRemuxTarget.matroska => 'mkv',
    FfmpegRemuxTarget.mpegTs => 'ts',
  };

  /// Output options this container needs beyond a stream copy.
  List<String> get outputArguments => switch (this) {
    // `faststart` moves the index to the front. Without it, a player on a phone
    // downloads the whole file before it can seek, which is exactly what a
    // recording someone wants to scrub through must not do.
    FfmpegRemuxTarget.mp4 => <String>['-movflags', '+faststart'],
    FfmpegRemuxTarget.matroska => const <String>[],
    FfmpegRemuxTarget.mpegTs => const <String>[],
  };
}

/// What a remux run produced.
final class FfmpegRemuxResult {
  /// Creates the result of one run.
  const FfmpegRemuxResult({
    required this.success,
    required this.outputPath,
    required this.bytesWritten,
    required this.duration,
    required this.skipped,
    this.error,
  });

  /// A run that produced a usable file.
  const FfmpegRemuxResult.completed({
    required String outputPath,
    required int bytesWritten,
    Duration duration = Duration.zero,
  }) : this(success: true, outputPath: outputPath, bytesWritten: bytesWritten, duration: duration, skipped: false);

  /// A run that found the output already there and left it alone.
  const FfmpegRemuxResult.alreadyThere({
    required String outputPath,
    required int bytesWritten,
    Duration duration = Duration.zero,
  }) : this(success: true, outputPath: outputPath, bytesWritten: bytesWritten, duration: duration, skipped: true);

  /// A run that did not produce a usable file.
  const FfmpegRemuxResult.failed({required String outputPath, required Object error})
    : this(
        success: false,
        outputPath: outputPath,
        bytesWritten: 0,
        duration: Duration.zero,
        skipped: false,
        error: error,
      );

  /// Whether the file at [outputPath] is the recording.
  final bool success;

  /// Where the joined file was written.
  final String outputPath;

  /// Bytes the output holds, measured from the disk.
  final int bytesWritten;

  /// Duration FFprobe reported for the output, or [Duration.zero] when no probe
  /// was available to ask.
  final Duration duration;

  /// Whether the work was skipped because a complete output already existed.
  ///
  /// A remux of a six-hour recording is the thing most likely to be interrupted
  /// by the app being closed, and re-doing it is the difference between a user
  /// finding their file on the next start and finding nothing.
  final bool skipped;

  /// Why the run failed, when it did.
  final Object? error;

  @override
  String toString() =>
      'FfmpegRemuxResult(success: $success, skipped: $skipped, $outputPath, ${bytesWritten}B'
      '${duration == Duration.zero ? '' : ', ${duration.inSeconds}s'}${error == null ? '' : ', $error'})';
}

/// Joins a recording's segments into one file.
///
/// A recording is segmented on purpose — it has to survive the process being
/// killed — and the same property makes the result awkward to watch. This is the
/// step that gives the user one file back, and it runs on purpose **after** the
/// recording: remuxing while FFmpeg is still writing would read a segment that is
/// still open, and a merge that takes a minute on a phone must not be the thing
/// standing between two recordings.
///
/// It reads the recording's own records rather than a directory listing: the
/// [FfmpegRecordingManifest] says which attempt journals exist, and a journal
/// says which segments were closed. Anything not named there is not part of the
/// recording, which is also why a kill mid-write loses one segment and not the
/// file.
final class FfmpegRecordingRemuxer {
  /// Creates the remuxer.
  ///
  /// [executor] defaults to the FFmpegKit implementation, the same one a
  /// recording ran on — a second FFmpeg build would be a second native library in
  /// the app. [probe] is used to confirm the result decodes; without it the
  /// result is judged by size alone.
  FfmpegRecordingRemuxer({FfmpegExecutor? executor, FfmpegProbe? probe}) : _executor = executor, _probe = probe;

  /// File name a merged recording gets, beside the segments it came from.
  ///
  /// Named from the recording's own prefix so a folder of several recordings
  /// stays readable, and distinct from every segment name so the merged file can
  /// never be picked up as input by a later run.
  static String combinedName(String prefix, FfmpegRemuxTarget target) => '$prefix.combined.${target.extension}';

  FfmpegExecutor? _executor;
  final FfmpegProbe? _probe;

  /// The ledger this remux reports to: a merge writes a second copy of every
  /// byte, and a host watching memory should see it.
  final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.recording);

  late final String _memoryKey = memoryContributorKey(this);

  /// Joins [manifest]'s segments into one file in [directory].
  ///
  /// Returns a failed result rather than throwing when the merge cannot be done:
  /// the recording itself is safe on disk at this point, and a host that called
  /// this after the fact should be told what went wrong, not interrupted.
  Future<FfmpegRemuxResult> run({
    required FfmpegRecordingManifest manifest,
    required String directory,
    FfmpegRemuxTarget target = FfmpegRemuxTarget.mp4,
  }) async {
    final outputPath = joinOutputPath(directory, combinedName(manifest.prefix, target));

    final segments = _segmentsOf(manifest, directory);

    if (segments.isEmpty) {
      // Not "nothing was recorded" but "nothing was closed": the segment still
      // open when the process ended is not joinable, and a merge that invents a
      // file out of a half-written one is worse than no merge.
      return FfmpegRemuxResult.failed(
        outputPath: outputPath,
        error: const FfmpegRemuxException('the recording journal lists no closed segment to join'),
      );
    }

    final existing = FileStat.statSync(outputPath);

    if (existing.type != FileSystemEntityType.notFound && existing.size > 0) {
      return FfmpegRemuxResult.alreadyThere(outputPath: outputPath, bytesWritten: existing.size);
    }

    final listPath = joinOutputPath(directory, '${manifest.prefix}.concat.txt');

    try {
      File(listPath).writeAsStringSync(_concatList(segments));
    } on Object catch (error) {
      return FfmpegRemuxResult.failed(outputPath: outputPath, error: error);
    }

    final arguments = List<String>.unmodifiable(<String>[
      // Never overwrite: an output that appeared between the check above and this
      // run belongs to someone else.
      '-n',
      '-hide_banner',
      '-loglevel',
      'info',
      // The list is generated here with absolute paths, and the concat demuxer
      // rejects an absolute path unless told it is safe — the guard exists for
      // lists written by third parties, not for ours.
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      listPath,
      // The same mapping rule as the recording: first video, first audio, and
      // either is allowed to be absent (an audio-only room has no video track).
      '-map',
      '0:v:0?',
      '-map',
      '0:a:0?',
      '-c',
      'copy',
      ...target.outputArguments,
      outputPath,
    ]);

    _log.info(
      'joining a recording into one file',
      fields: <String, Object?>{
        'segments': segments.length,
        'output': outputPath,
        'target': target.name,
        'container': manifest.container.name,
      },
    );

    try {
      final execution = await _executorOf().start(
        arguments: arguments,
        onStatistics: (statistics) =>
            _memory.report(_memoryKey, items: 1, bytes: statistics.sizeBytes, note: 'remux of ${manifest.prefix}'),
      );

      final code = await _awaitExit(execution);
      final output = FileStat.statSync(outputPath);

      if (code != 0 || output.type == FileSystemEntityType.notFound || output.size <= 0) {
        return FfmpegRemuxResult.failed(
          outputPath: outputPath,
          error: FfmpegRemuxException(
            'FFmpeg exited with $code and left ${output.type == FileSystemEntityType.notFound ? 'no' : '${output.size}B'} output',
          ),
        );
      }

      final duration = await _probeOf()?.durationOf(outputPath) ?? Duration.zero;

      _log.info(
        'recording joined',
        fields: <String, Object?>{'output': outputPath, 'bytes': output.size, 'durationMs': duration.inMilliseconds},
      );

      return FfmpegRemuxResult.completed(outputPath: outputPath, bytesWritten: output.size, duration: duration);
    } on Object catch (error) {
      _log.error('the remux could not run', error: error, fields: <String, Object?>{'output': outputPath});

      return FfmpegRemuxResult.failed(outputPath: outputPath, error: error);
    } finally {
      _memory.withdraw(_memoryKey);
      // The list is an instruction, not a record: everything it says is
      // reconstructible from the journal, so leaving it behind would put a second
      // description of the same recording on disk for someone to distrust.
      try {
        final list = File(listPath);
        if (list.existsSync()) {
          list.deleteSync();
        }
      } on Object {
        // A list that cannot be deleted is a leftover file, not a failed remux.
      }
    }
  }

  FfmpegExecutor _executorOf() => _executor ??= FfmpegKitExecutor();

  FfmpegProbe? _probeOf() => _probe ?? const FFprobeKitFfmpegProbe();

  /// The segments this recording closed, in the order they were written.
  ///
  /// Every attempt's journal is read, oldest attempt first: a recording whose
  /// source dropped five times is one recording, and the join has to produce its
  /// whole timeline.
  List<FfmpegJournalledSegment> _segmentsOf(FfmpegRecordingManifest manifest, String directory) {
    // A host that wrote its own manifest (or an older one) may name no journals at
    // all; the conventional name for the recording's first attempt is then the
    // only thing left to read, and a recording that never re-opened has exactly it.
    final journals = manifest.journals.isEmpty
        ? <String>[joinOutputPath(directory, '${manifest.prefix}.clock-v1.csv')]
        : manifest.journals.map((journal) => joinOutputPath(directory, journal)).toList();

    return FfmpegSegmentJournal.fromFiles(journals.map(File.new)).entries.toList();
  }

  /// The concat demuxer's list: one `file '<path>'` line per segment.
  ///
  /// Forward slashes, because FFmpeg's own path parser treats a backslash as an
  /// escape inside a quoted name, and the Windows API accepts the other separator.
  static String _concatList(List<FfmpegJournalledSegment> segments) {
    return segments.map((segment) => "file '${segment.path.replaceAll(r'\', '/')}'").join('\n');
  }

  Future<int?> _awaitExit(FfmpegExecution execution) async {
    try {
      return await execution.exitCode;
    } on Object catch (_) {
      return null;
    }
  }
}

/// Why a recording could not be joined.
final class FfmpegRemuxException implements Exception {
  /// Creates the exception.
  const FfmpegRemuxException(this.message);

  /// What went wrong, in the words the caller should show.
  final String message;

  @override
  String toString() => 'FfmpegRemuxException($message)';
}
