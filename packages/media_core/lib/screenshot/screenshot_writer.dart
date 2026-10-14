import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_core/screenshot/player_screenshot.dart';
import 'package:media_core_logging/media_core_logging.dart';
import 'package:path/path.dart' as p;

/// Writes captured frames to disk.
///
/// Responsibilities:
///
/// - build a file name from the capture
/// - create the target directory
/// - write the bytes
///
/// It does not:
///
/// - decide when a capture happens
/// - encode images (the capture already produced the bytes)
/// - manage a gallery or a database of captures
///
/// Those belong to:
///
/// - ScreenshotManager
/// - PlayerAdapter / ScreenshotSurface
/// - the application
final class ScreenshotWriter {
  /// Creates a writer.
  ///
  /// [directory] is used when a call does not name one; without it the system
  /// temporary directory is used, which is right for a quick "save and share"
  /// and wrong for a permanent gallery — a host that keeps screenshots passes
  /// its own directory.
  const ScreenshotWriter({this.directory, this.fileNameBuilder});

  /// Directory used when a call does not name one.
  final String? directory;

  /// Builds the file name (without directory) for a capture.
  ///
  /// Defaults to [defaultFileName].
  final String Function(PlayerScreenshot screenshot)? fileNameBuilder;

  /// Writes [screenshot] and returns the file path.
  ///
  /// [path] names the file outright; otherwise the name is generated inside
  /// [directory] (or the writer's own directory, or the system temporary
  /// directory).
  Future<String> save(PlayerScreenshot screenshot, {String? path, String? directory}) async {
    if (kIsWeb) {
      throw UnsupportedError('ScreenshotWriter needs a file system; keep the bytes in memory on web.');
    }

    if (screenshot.isEmpty) {
      throw ArgumentError.value(screenshot, 'screenshot', 'Cannot write an empty screenshot.');
    }

    final name = (fileNameBuilder ?? defaultFileName)(screenshot);

    final target = path ?? p.join(directory ?? this.directory ?? Directory.systemTemp.path, name);

    final file = File(target);

    await file.parent.create(recursive: true);
    await file.writeAsBytes(screenshot.bytes, flush: true);

    MediaCoreLog.info(
      LogCategory.renderer,
      'screenshot saved',
      fields: <String, Object?>{'path': file.path, 'bytes': screenshot.sizeInBytes},
    );

    return file.path;
  }

  /// Default name: `screenshot_<player>_<timestamp>.<ext>`.
  ///
  /// The timestamp is part of the name because captures are cheap and often
  /// repeated within the same second; without it a burst of captures would
  /// overwrite one file.
  static String defaultFileName(PlayerScreenshot screenshot) {
    final player = screenshot.playerId?.value ?? 'player';

    final stamp = _formatTimestamp(screenshot.capturedAt ?? clock.now());

    return 'screenshot_${sanitize(player)}_$stamp.${screenshot.format.fileExtension}';
  }

  /// Makes [value] safe to use as one path segment.
  ///
  /// A player id is caller-supplied and may contain separators or characters a
  /// file system rejects; a screenshot must never escape its directory.
  static String sanitize(String value) {
    final cleaned = value.trim().replaceAll(RegExp('[^A-Za-z0-9._-]+'), '_');

    return cleaned.isEmpty ? 'player' : cleaned;
  }

  static String _formatTimestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    String three(int number) => number.toString().padLeft(3, '0');

    return '${value.year}${two(value.month)}${two(value.day)}'
        '_${two(value.hour)}${two(value.minute)}${two(value.second)}'
        '_${three(value.millisecond)}';
  }
}
