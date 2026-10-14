import 'package:media_core_memory/src/memory_account.dart' show MemoryAccount;

/// Notional per-unit memory costs.
///
/// ## These are estimates, and that is deliberate
///
/// No Dart API reports how many bytes a decoded video stream, a texture or a
/// platform player is holding. The real number lives in native memory, in a
/// codec's internal buffers and in the GPU's allocator, and none of them expose
/// it. So a framework that wants to answer "which module is using the memory?"
/// has two options: report nothing, or report a declared, configurable estimate
/// and say so.
///
/// This file is the second option. The numbers are deliberately round and
/// deliberately conservative: they are meant for *ranking* consumers and for
/// driving a budget, not for telling a viewer how many megabytes are free.
///
/// Measured truth comes from a different place: `MemoryMonitor` takes
/// device-level snapshots from the platform (used/available/external bytes),
/// and a report carries both. When the device says memory is tight and the
/// accounting says the pool holds most of it, the ranking is what matters, and
/// the estimate is good enough for that.
///
/// Hosts that know their own numbers (a player wrapper that can read its
/// decoder's usage, an audio engine with a real buffer size) should report
/// those instead: [MemoryAccount.set] takes whatever they measured.
abstract final class MemoryEstimates {
  /// Bytes one 1080p video stream is assumed to hold.
  ///
  /// A 1080p decoder holds reference frames plus its own scaling buffers; the
  /// figure is a mid-range Android/desktop value, not a measurement.
  static const int videoStream1080p = 64 * 1024 * 1024;

  /// Bytes one 720p video stream is assumed to hold.
  static const int videoStream720p = 32 * 1024 * 1024;

  /// Bytes one 480p (and below) video stream is assumed to hold.
  static const int videoStreamLow = 16 * 1024 * 1024;

  /// Bytes one video surface is assumed to hold.
  static const int videoSurface = 8 * 1024 * 1024;

  /// Bytes one decoded audio stream is assumed to hold.
  static const int audioStream = 4 * 1024 * 1024;

  /// Bytes one queued danmaku message is assumed to hold, including its
  /// rendered layout for the current frame.
  static const int danmakuMessage = 2 * 1024;

  /// Bytes one download transfer buffer is assumed to hold.
  static const int downloadTransferBuffer = 1024 * 1024;

  /// Bytes one recording segment is assumed to hold while it is being written.
  static const int recordingSegment = 4 * 1024 * 1024;

  /// Bytes one resolved-source cache entry is assumed to hold.
  static const int cacheEntry = 8 * 1024;

  /// Bytes one list/feed item is assumed to hold (its metadata, not its media).
  static const int playbackItem = 1024;

  /// Estimate for a video stream of an unknown or unspecified size.
  ///
  /// [height] is the video's height in pixels when known; the 720p figure is
  /// used between the 1080p and 480p bands so an unknown stream is neither
  /// hidden nor allowed to dominate a report.
  static int videoStream(int? height) {
    if (height == null || height <= 0) {
      return videoStream720p;
    }
    if (height >= 1000) {
      return videoStream1080p;
    }
    if (height >= 600) {
      return videoStream720p;
    }
    return videoStreamLow;
  }

  /// Formats [bytes] for a log line or a diagnostics screen.
  static String formatBytes(int bytes) {
    if (bytes < 0) {
      return '-${formatBytes(-bytes)}';
    }
    if (bytes < 1024) {
      return '${bytes}B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}
