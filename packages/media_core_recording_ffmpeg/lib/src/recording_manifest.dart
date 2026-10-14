import 'dart:convert';
import 'dart:io';

import 'package:media_core/media_core.dart' show RecordingSource;
import 'package:media_core_recording_ffmpeg/src/ffmpeg_record_container.dart';

/// The small JSON file that says what a recording was.
///
/// It exists for the two moments after the recording is gone: whoever joins the
/// segments, or whoever wonders what time of day a point in a six-hour capture
/// happened, needs the wall-clock start and the container the files were written
/// as. Neither is recoverable from the segment files themselves — a TS carries no
/// creation date at all, and a re-muxed file has the re-mux's timestamp rather
/// than the recording's.
///
/// The reference implementation met the same need by spawning a thread that
/// appended one subtitle cue per second of wall-clock time to a sidecar file; that
/// drifts whenever the input stalls and mislabels hours of a long recording, so
/// this stores the start instead and lets a reader do the arithmetic.
final class FfmpegRecordingManifest {
  /// Creates a manifest view of one recording.
  const FfmpegRecordingManifest({
    required this.prefix,
    required this.container,
    required this.segmentTime,
    required this.startedAt,
    required this.sourceLabel,
    required this.journals,
    required this.attempts,
  });

  /// Schema of the file, so a reader can tell it is ours and from which revision.
  static const int schemaVersion = 1;

  /// File-name prefix the segments were written under.
  final String prefix;

  /// Container each segment is written in.
  final FfmpegRecordContainer container;

  /// Requested segment length, in seconds.
  final int segmentTime;

  /// Wall-clock time the recording started — the first attempt, not the current one.
  final DateTime startedAt;

  /// What was recorded, with the query string removed.
  ///
  /// A live room's URL is signed, and a signing token pasted into a file the user
  /// shares with a friend is a credential leak. The address without its query names
  /// the stream well enough for a person reading the folder back, which is what
  /// this file is for.
  final String sourceLabel;

  /// Journals of the attempts this recording ran, oldest first.
  final List<String> journals;

  /// How many FFmpeg processes ran.
  final int attempts;

  /// Reads a manifest, or null when the file is missing or not ours.
  static FfmpegRecordingManifest? read(File file) {
    if (!file.existsSync()) {
      return null;
    }

    final Object? decoded;

    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      // A half-written manifest is a manifest that does not exist: it is written
      // before the process starts and after each re-opening, so a kill can land in
      // the middle of it, and the recording itself is intact regardless.
      return null;
    }

    if (decoded is! Map<String, dynamic> || decoded['schema'] != schemaVersion) {
      return null;
    }

    final container = switch (decoded['container']) {
      'mp4Fragmented' => FfmpegRecordContainer.mp4Fragmented,
      'mpegTs' => FfmpegRecordContainer.mpegTs,
      _ => null,
    };

    if (container == null) {
      return null;
    }

    return FfmpegRecordingManifest(
      prefix: decoded['prefix'] as String? ?? '',
      container: container,
      segmentTime: decoded['segmentTime'] as int? ?? 0,
      startedAt: DateTime.tryParse(decoded['startedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      sourceLabel: decoded['sourceLabel'] as String? ?? '',
      journals: (decoded['journals'] as List<dynamic>? ?? const <dynamic>[]).whereType<String>().toList(),
      attempts: decoded['attempts'] as int? ?? 1,
    );
  }

  /// This manifest as the file's JSON text.
  String toJson() {
    return const JsonEncoder.withIndent('  ').convert(<String, Object>{
      'schema': schemaVersion,
      'prefix': prefix,
      'container': container.name,
      'segmentTime': segmentTime,
      'startedAt': startedAt.toIso8601String(),
      'sourceLabel': sourceLabel,
      'journals': journals,
      'attempts': attempts,
    });
  }

  @override
  String toString() => 'FfmpegRecordingManifest($prefix, ${container.name}, $attempts attempt(s), $sourceLabel)';
}

/// Name of the manifest file a recording's prefix gets.
///
/// Profiled like the segment and journal names, so a manifest from an older
/// layout is never read as this one's.
String recordingManifestName(String prefix) => '$prefix.clock-v1.json';

/// The label a recording is identified by in the manifest.
///
/// The source's own id wins when the host set one (a room id is exactly what a
/// person browsing a folder wants); otherwise the URL's host and path are used,
/// with the query dropped, because that query is a signature.
String recordingSourceLabel(RecordingSource source) {
  if (source.id != null && source.id!.isNotEmpty) {
    return source.id!;
  }

  final uri = Uri.tryParse(source.value);

  if (uri == null) {
    return source.value.split('?').first;
  }

  final path = uri.path.isEmpty ? '' : uri.path;

  return '${uri.host}$path';
}
