import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';

/// What a file on disk actually contains, as far as FFprobe can tell.
///
/// An exit code says a process ended and the journal says which files were
/// closed; neither says the bytes form a stream a decoder can open. FFprobe is
/// the only thing in this dependency that can say that, and it is a native call,
/// so it sits behind a seam: the verification logic is judged in tests against a
/// probe that returns fixed answers, and production uses [FFprobeKitFfmpegProbe].
abstract interface class FfmpegProbe {
  /// Duration of the media at [path], or null when it cannot be determined.
  ///
  /// Null is the answer for a missing file, an unparsable container and a native
  /// layer that is not initialized. The caller treats all three the same way —
  /// *unverified* — because a probe that cannot answer is not evidence that the
  /// file is bad.
  Future<Duration?> durationOf(String path);
}

/// [FfmpegProbe] backed by the plugin's own FFprobe.
///
/// Uses `MediaInformationSession`, which is the plugin's parsed `-show_format`
/// path, rather than shelling out to an ffprobe command line: the arguments are
/// built natively, so a path with spaces or quotes cannot break them.
final class FFprobeKitFfmpegProbe implements FfmpegProbe {
  /// Creates a probe.
  ///
  /// [timeout] bounds a single native probe call. Five seconds is generous for
  /// a local MPEG-TS segment (the container is read from the front) and still
  /// short enough that a stuck FFprobe cannot hold a `stop()` open.
  const FFprobeKitFfmpegProbe({this.timeout = 5000});

  /// FFprobe's per-call timeout, in milliseconds.
  final int timeout;

  @override
  Future<Duration?> durationOf(String path) async {
    try {
      final session = await MediaInformationSession.fromPath(path, timeout: timeout).executeAsync();
      final seconds = double.tryParse(session.getMediaInformation()?.duration ?? '');

      return seconds == null ? null : Duration(milliseconds: (seconds * 1000).round());
    } on Object catch (_) {
      // A probe that throws is a probe that has no answer. Verification is
      // something a recording reports, not something that can fail one - and
      // what it can throw is whatever the native binding decides to raise, which
      // is exactly why there is no `on` clause here.
      return null;
    }
  }
}
