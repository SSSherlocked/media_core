import 'package:flutter/rendering.dart';

import 'package:flv_lzc/fijkplayer.dart';
import 'package:media_core/media_core.dart';

/// Helpers shared by the ijkplayer adapter.
abstract final class FijkHelper {
  /// Translates the framework's source headers into ijkplayer's format
  /// options: a CRLF-terminated `headers` string, with `user_agent`
  /// lifted out because ijkplayer treats it separately.
  ///
  /// Validation is the framework's single rule — see [HttpHeaderSanitizer].
  /// ijkplayer writes both names and values verbatim into a native option
  /// string, so a header that cannot be sent exactly as given is refused
  /// here rather than rewritten into something the site never issued.
  static Map<String, Object> sourceHeaderOptions(Map<String, String> headers) {
    final sanitized = HttpHeaderSanitizer.sanitize(headers);
    final userAgent = sanitized.remove('user-agent');

    final buffer = StringBuffer();
    sanitized.forEach((name, value) => buffer.write('$name:$value\r\n'));

    return <String, Object>{'headers': buffer.toString(), 'user_agent': ?userAgent};
  }

  /// Level the engine was last told to log at.
  ///
  /// Static because the plugin's level is process-wide: one value per app,
  /// not one per player, and a room-per-player host must not push it again
  /// on every open.
  static FijkLogLevel? _engineLogLevel;

  /// Copies the host's logging configuration onto the engine's own log.
  ///
  /// ijkplayer logs from C — a line per state transition and a block per player
  /// create/release (`IJKMEDIA`), plus a Dart line per plugin call — and none of
  /// that goes through [MediaCoreLog]. A host that keeps the hub silent still
  /// gets hundreds of engine lines in logcat, which reads as "this adapter logs
  /// too much" when the adapter itself logs nothing at all.
  ///
  /// The engine has its own switch and this is the only place it is set, so the
  /// hub stays the single authority: a silent hub is a silent engine, and a host
  /// chasing an engine problem sets `MediaCoreLog.level = LogLevel.trace` to get
  /// the engine's own output back. The mapping is monotone; the plugin normalizes
  /// the value on its own side (`level / 100`, clamped to 0..8, then ijk's
  /// `setLogLevel`).
  ///
  /// Call before the first player exists: setting it loads the plugin's native
  /// libraries, and doing that mid-open pays for it on the user's first frame.
  static void syncLogLevel() {
    final level = _engineLogLevelOf(MediaCoreLog.level);

    if (level == _engineLogLevel) {
      return;
    }

    _engineLogLevel = level;

    FijkLog.setLevel(level);
  }

  static FijkLogLevel _engineLogLevelOf(LogLevel level) {
    return switch (level) {
      LogLevel.trace => FijkLogLevel.Verbose,
      LogLevel.debug => FijkLogLevel.Debug,
      LogLevel.info => FijkLogLevel.Info,
      LogLevel.warning => FijkLogLevel.Warn,
      LogLevel.error => FijkLogLevel.Error,
      LogLevel.critical => FijkLogLevel.Fatal,
      LogLevel.nothing => FijkLogLevel.Silent,
    };
  }

  /// Formats a player position as a readable string.
  static String formatDuration(Duration duration) {
    if (duration.inMilliseconds < 0) return '-: negative';

    String two(int n) => n.toString().padLeft(2, '0');

    final minutes = two(duration.inMinutes.remainder(60));
    final seconds = two(duration.inSeconds.remainder(60));
    final hours = duration.inHours;

    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  /// Maps a Flutter [BoxFit] to the closest [FijkFit] the engine understands.
  ///
  /// BoxFit gains and deprecates values across Flutter releases, so an
  /// explicit default falls back to the safest fit rather than breaking here.
  static FijkFit getIjkBoxFit(BoxFit videoFit) {
    switch (videoFit) {
      case BoxFit.contain:
        return FijkFit.contain;
      case BoxFit.cover:
        return FijkFit.cover;
      case BoxFit.fill:
        return FijkFit.fill;
      case BoxFit.fitHeight:
        return FijkFit.fitHeight;
      case BoxFit.fitWidth:
        return FijkFit.fitWidth;
      // BoxFit may carry deprecated or newly added members; a default keeps
      // this mapping compiling across SDK versions.
      // ignore: no_default_cases
      default:
        return FijkFit.contain;
    }
  }
}
