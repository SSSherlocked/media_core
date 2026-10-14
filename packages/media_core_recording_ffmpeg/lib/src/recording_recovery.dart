import 'package:media_core/media_core.dart' show RecordingSource;

/// Gets a fresh address for [source].
///
/// A live room's stream URL is usually signed and short-lived: the address that
/// was right when the user pressed record has expired by the next segment, and
/// nothing inside FFmpeg can fix that — re-opening the same address is a retry
/// that cannot succeed. Only the host can mint a new one, which is why this is a
/// callback rather than something the backend does.
///
/// Returning null or an empty value says the refresh is not possible right now,
/// and the recording ends with [FfmpegRecordingGaveUpException] rather than
/// burning the remaining attempts on an address that will not work.
typedef UrlRefresher = Future<String?> Function(RecordingSource source);

/// Reports how many bytes are free where [directory] lives.
///
/// Null means the platform could not say. This is a callback rather than a
/// helper because there is no portable way to ask in Dart — the plugins that do
/// it are per-platform and this package is not going to depend on one for an
/// optional check — and because a missing answer is not a reason to refuse a
/// recording the user asked for.
typedef DiskSpaceProbe = Future<int?> Function(String directory);

/// The volume a recording writes to has no room left.
///
/// Raised instead of letting FFmpeg find out: a write error mid-segment arrives
/// as an exit code that says nothing about the disk, and the user reads it as a
/// stream problem and presses record again.
final class FfmpegRecordingDiskFullException implements Exception {
  /// Creates the exception.
  const FfmpegRecordingDiskFullException({
    required this.directory,
    required this.freeBytes,
    required this.watermarkBytes,
  });

  /// The directory the recording was to be written to.
  final String directory;

  /// Bytes free there, as the probe reported them.
  final int freeBytes;

  /// The floor the recording refused to start below.
  final int watermarkBytes;

  @override
  String toString() =>
      'FfmpegRecordingDiskFullException($directory has ${freeBytes}B free, '
      'below the ${watermarkBytes}B watermark)';
}

/// The source was not re-opened again.
///
/// Carries the attempts it took to decide that, because "the stream ended" and
/// "the stream ended five times in eight seconds" are different bugs — the first
/// is the room going off air, the second is an address that was never going to
/// work.
final class FfmpegRecordingGaveUpException implements Exception {
  /// Creates the exception.
  const FfmpegRecordingGaveUpException({required this.cause, required this.attempts, this.exitCode});

  /// Why the re-opening stopped: the limit was reached, the address could not be
  /// refreshed, or there was no room left.
  final String cause;

  /// How many processes this recording ran, counting the first.
  final int attempts;

  /// The exit code of the last process, when there was one.
  final int? exitCode;

  @override
  String toString() => 'FfmpegRecordingGaveUpException($cause after $attempts attempt(s), exit=$exitCode)';
}
