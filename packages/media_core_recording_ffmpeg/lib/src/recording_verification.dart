import 'dart:io';

import 'package:media_core_recording_ffmpeg/src/ffmpeg_probe.dart';
import 'package:media_core_recording_ffmpeg/src/output_path.dart';

/// The segment journal FFmpeg writes when `-segment_list_type csv` is used, read
/// back as the record of *what was actually captured*.
///
/// This exists because an FFmpeg exit code answers "did the process end
/// cleanly", which is not the question a recording host asks. The question is
/// "is there a file, does it have parts, and are those parts readable" — and the
/// only record of that is the journal the muxer maintained while running, plus
/// the segment files it names.
///
/// The journal is parsed rather than trusted: FFmpeg rewrites the whole list on
/// every closed segment, so a half-written last line is possible if the process
/// was killed mid-update. A line that does not parse is counted, not fatal.
final class FfmpegSegmentJournal {
  FfmpegSegmentJournal._(this.entries, this.unreadableLines);

  /// Builds a journal view by reading [file].
  ///
  /// Synchronous by design: it is a small text file plus a `stat` per line, and
  /// the caller that wants an answer about a finished recording is already on an
  /// `async` path. A missing file is an empty journal, not an error — a
  /// recording that never reached its first segment boundary has no list, and
  /// that case is judged by [FfmpegRecordingCheck] rather than by the reader.
  factory FfmpegSegmentJournal.fromFile(File file) {
    final entries = <FfmpegJournalledSegment>[];
    var unreadable = 0;

    if (file.existsSync()) {
      final directory = outputDirectoryOf(file.path);

      for (final raw in file.readAsLinesSync()) {
        final line = raw.trim();

        if (line.isEmpty) {
          continue;
        }

        final name = _segmentNameOf(line);

        if (name == null) {
          unreadable++;

          continue;
        }

        final path = joinOutputPath(directory, name);

        entries.add(FfmpegJournalledSegment(index: entries.length, name: name, path: path, bytes: _sizeOf(path)));
      }
    }

    return FfmpegSegmentJournal._(List<FfmpegJournalledSegment>.unmodifiable(entries), unreadable);
  }

  /// Reads several journals as one recording's list, oldest first.
  ///
  /// A recording whose source dropped and was re-opened wrote one journal per
  /// process — FFmpeg's `-n` refuses to touch a list that already exists, and a
  /// restart that overwrote the first one would lose the segments it described.
  /// The attempts in order are the recording, so that is what a verdict is
  /// judged against.
  factory FfmpegSegmentJournal.fromFiles(Iterable<File> files) {
    final combined = <FfmpegJournalledSegment>[];
    var unreadable = 0;

    for (final file in files) {
      final journal = FfmpegSegmentJournal.fromFile(file);

      unreadable += journal.unreadableLines;

      for (final entry in journal.entries) {
        combined.add(
          FfmpegJournalledSegment(index: combined.length, name: entry.name, path: entry.path, bytes: entry.bytes),
        );
      }
    }

    return FfmpegSegmentJournal._(List<FfmpegJournalledSegment>.unmodifiable(combined), unreadable);
  }

  /// Segments in the order FFmpeg listed them, oldest first.
  final List<FfmpegJournalledSegment> entries;

  /// Lines that carried no usable file name.
  ///
  /// Reported rather than silent: a journal that is half garbage usually means
  /// the file was truncated by a kill, and the host should know its segment
  /// list may be incomplete.
  final int unreadableLines;

  /// Total bytes across every segment that is still present on disk.
  ///
  /// This, and not FFmpeg's statistics figure, is the size of the recording: the
  /// status line's `size=` describes the muxer's own byte counter, which for the
  /// segment muxer is not the sum of the child files it has already closed.
  int get totalBytes => entries.fold(0, (sum, entry) => sum + entry.bytes);

  /// Whether any segment made it to disk.
  bool get isEmpty => entries.isEmpty;

  /// Number of journalled segments, present on disk or not.
  int get length => entries.length;

  /// The oldest segment, or null when the journal lists nothing.
  FfmpegJournalledSegment? get first => entries.isEmpty ? null : entries.first;

  /// The newest segment, or null when the journal lists nothing.
  ///
  /// This is the one a kill truncates, and the one whose bytes a "the recording
  /// is short" report has to account for.
  FfmpegJournalledSegment? get last => entries.isEmpty ? null : entries.last;

  /// `file,'name.ts'` (and the older `file,name.ts` shape) is the CSV entry
  /// format; anything else in the file is a comment or a partial write.
  static String? _segmentNameOf(String line) {
    final parts = line.split(',');

    if (parts.length < 2 || parts.first.trim().toLowerCase() != 'file') {
      return null;
    }

    final name = parts.sublist(1).join(',').trim();

    if (name.length < 2 || name.startsWith("'") != name.endsWith("'")) {
      return null;
    }

    final unquoted = name.startsWith("'") ? name.substring(1, name.length - 1) : name;

    return unquoted.isEmpty ? null : unquoted;
  }

  static int _sizeOf(String path) {
    // `FileStat.statSync` reports a missing file as a stat of type notFound with
    // a size of -1 rather than by throwing, so the type is what says whether the
    // number means anything.
    final stat = FileStat.statSync(path);

    return stat.type == FileSystemEntityType.notFound ? 0 : stat.size;
  }
}

/// One segment the journal lists.
final class FfmpegJournalledSegment {
  /// Describes one segment as the journal lists it.
  FfmpegJournalledSegment({required this.index, required this.name, required this.path, required this.bytes});

  /// Zero-based position in the journal.
  final int index;

  /// File name as FFmpeg wrote it, relative to the journal's directory.
  final String name;

  /// Path of the segment, resolved against the journal's directory.
  final String path;

  /// Bytes on disk right now, `0` when the segment is gone.
  final int bytes;

  /// Whether anything at all was written to this segment.
  bool get isPresent => bytes > 0;

  @override
  String toString() => 'FfmpegJournalledSegment(#$index, $name, ${bytes}B)';
}

/// What the segments on disk, and FFprobe, say about a finished recording.
enum FfmpegRecordingVerdict {
  /// Every journalled segment is present, sized and (when probed) openable.
  complete,

  /// The recording has parts, but some of them are gone, stubs, or unreadable —
  /// usually a kill that landed while a segment was still open, or an input that
  /// died at a boundary. Usable, with a hole in it.
  suspicious,

  /// Nothing usable was written.
  missing,
}

/// The verdict of a finished recording's own output.
///
/// This is what a `stop()` is judged against, and what a host that needs more
/// than the core's `RecordingResult` reads.
final class FfmpegRecordingCheck {
  FfmpegRecordingCheck._({
    required this.verdict,
    required this.segments,
    required this.bytesOnDisk,
    required this.missingSegments,
    required this.stubSegments,
    required this.unreadableSegments,
    required this.journalLinesIgnored,
    required this.reason,
  });

  /// A segment below this size cannot carry a PAT/PMT plus enough payload to
  /// decode, so it is counted as a stub rather than as output.
  ///
  /// The floor is deliberately far below any real segment: at the shortest
  /// segment time this package allows (10 s) and a bitrate low enough to be
  /// silence (100 kbit/s), a segment is ~125 KB. Anything smaller than this was
  /// opened and abandoned.
  static const int minimumSegmentBytes = 4096;

  /// Checks a finished recording.
  ///
  /// [claimedDuration] is FFmpeg's own media time at the moment the process
  /// ended. It is used for the *message* only — for a live capture it is input
  /// media time processed, which is the figure a host shows, while the byte
  /// total is measured from the disk instead of taken from the same status line.
  ///
  /// [probe] is optional. Without it the check is a filesystem statement; with
  /// it the first and last segments are also opened by FFprobe, because a
  /// truncated header or an abandoned child file can look perfectly sized. Only
  /// those two are probed — the first proves the stream can be opened at all and
  /// the last is where a kill lands — so a day-long recording costs two native
  /// calls, not one per segment.
  static Future<FfmpegRecordingCheck> evaluate({
    required FfmpegSegmentJournal journal,
    Duration claimedDuration = Duration.zero,
    FfmpegProbe? probe,
    int minimumSegmentBytes = FfmpegRecordingCheck.minimumSegmentBytes,
  }) async {
    if (journal.isEmpty) {
      // The journal lists nothing. Either the stream died before the first
      // boundary, or it never produced a frame. Both are "no recording", and
      // saying which matters to whoever reads the log — the first is a short
      // stream, the second is a bad URL.
      return FfmpegRecordingCheck._(
        verdict: FfmpegRecordingVerdict.missing,
        segments: 0,
        bytesOnDisk: 0,
        missingSegments: 0,
        stubSegments: 0,
        unreadableSegments: 0,
        journalLinesIgnored: journal.unreadableLines,
        reason: claimedDuration > Duration.zero
            ? 'FFmpeg processed ${claimedDuration.inSeconds}s of input but closed no segment'
            : 'FFmpeg produced no segment: the input delivered nothing',
      );
    }

    final missing = journal.entries.where((entry) => !entry.isPresent).length;
    final stubs = journal.entries.where((entry) => entry.isPresent && entry.bytes < minimumSegmentBytes).length;

    if (missing == journal.length) {
      return FfmpegRecordingCheck._(
        verdict: FfmpegRecordingVerdict.missing,
        segments: journal.length,
        bytesOnDisk: 0,
        missingSegments: missing,
        stubSegments: 0,
        unreadableSegments: 0,
        journalLinesIgnored: journal.unreadableLines,
        reason: 'the journal lists ${journal.length} segment(s) and none of them is on disk',
      );
    }

    var unreadable = 0;

    if (probe != null) {
      // Probed in the open, so a host that supplies a probe is asking for this
      // judgement rather than a bare filesystem count.
      for (final entry in <FfmpegJournalledSegment?>[journal.first, journal.last]) {
        if (entry == null || !entry.isPresent || entry.bytes < minimumSegmentBytes) {
          continue;
        }

        final duration = await probe.durationOf(entry.path);

        if (duration == null) {
          unreadable++;
        }
      }
    }

    final findings = <String>[
      if (missing > 0) '$missing segment(s) listed but not on disk',
      if (stubs > 0) '$stubs segment(s) smaller than $minimumSegmentBytes B',
      if (journal.unreadableLines > 0) '${journal.unreadableLines} journal line(s) unreadable',
      if (unreadable > 0) '$unreadable probed segment(s) FFprobe could not open',
    ];

    final verdict = findings.isEmpty ? FfmpegRecordingVerdict.complete : FfmpegRecordingVerdict.suspicious;

    return FfmpegRecordingCheck._(
      verdict: verdict,
      segments: journal.length,
      bytesOnDisk: journal.totalBytes,
      missingSegments: missing,
      stubSegments: stubs,
      unreadableSegments: unreadable,
      journalLinesIgnored: journal.unreadableLines,
      reason: findings.isEmpty ? null : findings.join('; '),
    );
  }

  /// How the output was judged.
  final FfmpegRecordingVerdict verdict;

  /// Number of segments the journal lists.
  final int segments;

  /// Bytes those segments occupy on disk.
  final int bytesOnDisk;

  /// Journalled segments with no file behind them.
  final int missingSegments;

  /// Segments too small to hold a decodable stream.
  final int stubSegments;

  /// Probed segments FFprobe could not open.
  final int unreadableSegments;

  /// Journal lines that were skipped as garbage.
  final int journalLinesIgnored;

  /// Why the verdict is what it is; null when the output is complete.
  final String? reason;

  /// Whether a host may treat the recording as usable output.
  ///
  /// `suspicious` is usable: the completed segments are playable files and the
  /// hole is documented by [reason]. Only `missing` is not.
  bool get isUsable => verdict != FfmpegRecordingVerdict.missing;

  @override
  String toString() =>
      'FfmpegRecordingCheck(${verdict.name}, $segments segments, ${bytesOnDisk}B'
      '${reason == null ? '' : ', $reason'})';
}

/// Why a recording was reported as a failure.
///
/// An `Exception` rather than a bare string because the caller has to branch on
/// it — "nothing was written" and "the parts do not add up" want different
/// retries — and the branch is worth keeping next to the judgement that made it.
final class FfmpegRecordingFailure implements Exception {
  /// Wraps the judgement that made a recording unusable.
  const FfmpegRecordingFailure(this.check, {this.exitCode});

  /// The judgement the failure was raised from.
  final FfmpegRecordingCheck check;

  /// The process's exit code, when one was observed.
  ///
  /// `255` is what a killed FFmpeg reports, which is how an intentional stop
  /// arrives; a different code is the process failing on its own, and that is the
  /// difference a host acting on this needs.
  final int? exitCode;

  @override
  String toString() =>
      'FfmpegRecordingFailure(${check.verdict.name}, ${check.segments} segments, '
      '${check.bytesOnDisk}B, exit=$exitCode: ${check.reason ?? 'output not usable'})';
}
