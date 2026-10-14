import 'package:media_core_logging/src/log_category.dart';
import 'package:media_core_logging/src/log_level.dart';
import 'package:media_core_logging/src/player_logger.dart';

/// Turns a record into one line of text.
///
/// Shared by the console and file sinks so both produce the same line: a
/// developer reading a console and a bug report's file should not have to
/// translate between two formats.
///
/// The line is deliberately single-line and field-suffixed rather than
/// multi-line: a stack trace is useful, a stack trace that pushes every
/// following record off the screen is not.
final class LogFormatter {
  /// Creates a formatter with the chosen record parts.
  const LogFormatter({
    this.includeTimestamp = true,
    this.includeCategory = true,
    this.includeFields = true,
    this.includeStackTrace = false,
    this.alignCategory = true,
  });

  /// Whether each line starts with a `HH:mm:ss.SSS` timestamp.
  final bool includeTimestamp;

  /// Whether the category is included.
  final bool includeCategory;

  /// Whether structured fields are appended as `key=value`.
  final bool includeFields;

  /// Whether the stack trace is appended for error records.
  ///
  /// Off by default: a console flood of traces is worse than the error itself.
  final bool includeStackTrace;

  /// Whether categories are padded so the messages line up.
  final bool alignCategory;

  /// Formats [record].
  String format(PlayerLogRecord record) {
    final buffer = StringBuffer();

    if (includeTimestamp) {
      buffer.write('${_time(record.timestamp)} ');
    }

    buffer.write('[${_levelLabel(record.level)}]');

    if (includeCategory) {
      final name = record.category.name;
      final padded = alignCategory ? name.padRight(_categoryWidth) : name;
      buffer.write(' [$padded]');
    }

    buffer.write(' ${record.message}');

    if (includeFields && record.fields.isNotEmpty) {
      for (final entry in record.fields.entries) {
        buffer.write(' ${entry.key}=${entry.value}');
      }
    }

    if (record.error != null) {
      buffer.write(' error=${record.error}');
    }

    if (includeStackTrace && record.stackTrace != null) {
      buffer.write('\n${record.stackTrace}');
    }

    return buffer.toString();
  }

  /// Formats many records.
  String formatAll(Iterable<PlayerLogRecord> records) => records.map(format).join('\n');

  static const int _categoryWidth = 12;

  /// Fixed-width level label so a console column stays readable.
  static String _levelLabel(LogLevel level) => switch (level) {
    LogLevel.trace => 'TRACE   ',
    LogLevel.debug => 'DEBUG   ',
    LogLevel.info => 'INFO    ',
    LogLevel.warning => 'WARNING ',
    LogLevel.error => 'ERROR   ',
    LogLevel.critical => 'CRITICAL',
    LogLevel.nothing => 'NOTHING ',
  };

  static String _time(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${three(time.millisecond)}';
  }
}
