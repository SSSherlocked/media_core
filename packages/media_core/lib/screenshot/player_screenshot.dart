import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart' show ImageProvider, MemoryImage;
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/screenshot/screenshot_format.dart';
import 'package:media_core_logging/media_core_logging.dart';

/// Where the pixels of a capture came from.
enum ScreenshotSource {
  /// The playback engine produced the frame itself, from the decoded video.
  ///
  /// The image has the source's resolution and contains no application
  /// widgets. Subtitles are included only when the engine renders them.
  engine,

  /// The rendered surface was captured.
  ///
  /// The image is what the user saw inside the player's box: the engine's
  /// output after fitting, mirroring and the engine's own subtitles. The
  /// application's overlays are not included, because the capture boundary
  /// wraps the video only. Always PNG.
  surface;

  /// Whether the image came from the engine's own capture.
  bool get isEngine => this == ScreenshotSource.engine;

  /// Whether the image came from the rendered surface.
  bool get isSurface => this == ScreenshotSource.surface;
}

/// One captured video frame.
///
/// A screenshot is a value: encoded bytes plus everything a consumer needs to
/// label, display or store them. It stays valid after the player it came from
/// is closed or recycled.
final class PlayerScreenshot extends Equatable {
  /// Creates a screenshot.
  const PlayerScreenshot({
    required this.bytes,
    required this.format,
    this.width = 0,
    this.height = 0,
    this.position = Duration.zero,
    this.capturedAt,
    this.source = ScreenshotSource.engine,
    this.playerId,
    this.requestedFormat,
  });

  /// Encoded image bytes.
  final Uint8List bytes;

  /// Format [bytes] are actually in.
  final ScreenshotFormat format;

  /// Frame width in pixels; `0` when the player had not reported it.
  final int width;

  /// Frame height in pixels; `0` when the player had not reported it.
  final int height;

  /// Playback position when the frame was captured.
  final Duration position;

  /// When the capture happened.
  final DateTime? capturedAt;

  /// Which route produced the image.
  final ScreenshotSource source;

  /// PlayerIdentity the frame belongs to, when the capture went through a handle.
  final PlayerId? playerId;

  /// Format that was requested, set only when it differs from [format].
  final ScreenshotFormat? requestedFormat;

  /// Whether no bytes were produced.
  bool get isEmpty => bytes.isEmpty;

  /// Whether bytes were produced.
  bool get isNotEmpty => bytes.isNotEmpty;

  /// Encoded size in bytes.
  int get sizeInBytes => bytes.length;

  /// Encoded size in kilobytes.
  double get sizeInKilobytes => bytes.length / 1024;

  /// Whether the frame size is known.
  bool get hasSize => width > 0 && height > 0;

  /// Frame aspect ratio, `0` when the size is unknown.
  double get aspectRatio => hasSize ? width / height : 0;

  /// Whether the produced [format] is the one that was requested.
  ///
  /// False when a surface capture served a JPEG request, or any other
  /// fallback produced a different encoding.
  bool get honoursRequestedFormat => requestedFormat == null || requestedFormat == format;

  /// Whether this frame can be handed to `Image(image: ...)`.
  ImageProvider get imageProvider => MemoryImage(bytes);

  /// Debug serialization.
  ///
  /// The bytes are represented by their size: a screenshot is far too large to
  /// belong in a log line or a JSON dump.
  Map<String, Object?> toMap() {
    return {
      'playerId': playerId?.value,
      'format': format.name,
      'requestedFormat': requestedFormat?.name,
      'source': source.name,
      'width': width,
      'height': height,
      'positionMs': position.inMilliseconds,
      'sizeInBytes': sizeInBytes,
      'capturedAt': capturedAt?.toIso8601String(),
    };
  }

  /// Log fields describing this frame.
  Map<String, Object?> toLogFields() {
    return {
      'playerId': playerId?.value,
      'format': format.name,
      'source': source.name,
      'bytes': sizeInBytes,
      'positionMs': position.inMilliseconds,
    };
  }

  @override
  List<Object?> get props => [bytes, format, width, height, position, capturedAt, source, playerId, requestedFormat];

  @override
  String toString() {
    return 'PlayerScreenshot('
        'playerId: ${playerId?.value}, '
        'format: ${format.name}, '
        'source: ${source.name}, '
        'size: ${width}x$height, '
        'position: ${position.inMilliseconds}ms, '
        'bytes: $sizeInBytes'
        ')';
  }
}

/// Frame-capture outcomes, for callers that only need to log one.
extension PlayerScreenshotLogging on PlayerScreenshot? {
  /// Logs this outcome at [level], describing a failure when it is null.
  void logCapture(String action, {LogLevel level = LogLevel.debug}) {
    final screenshot = this;

    if (screenshot == null) {
      MediaCoreLog.log(
        level,
        LogCategory.renderer,
        'screenshot unavailable',
        fields: <String, Object?>{'action': action},
      );

      return;
    }

    MediaCoreLog.log(level, LogCategory.renderer, 'screenshot captured', fields: screenshot.toLogFields());
  }
}
