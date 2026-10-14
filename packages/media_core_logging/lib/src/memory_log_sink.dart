import 'dart:developer' as developer;
import 'package:media_core_logging/src/log_category.dart';
import 'package:media_core_logging/src/log_file_sink.dart';
import 'package:media_core_logging/src/log_formatter.dart';
import 'package:media_core_logging/src/log_level.dart';
import 'package:media_core_logging/src/media_core_log.dart' show MediaCoreLog;
import 'package:media_core_logging/src/player_logger.dart';

/// Writes log records to the platform console.
///
/// The default sink of [MediaCoreLog]. It is deliberately dependency-free:
/// `dart:developer` is the only logging channel that is visible both in
/// `flutter run` and in the DevTools log view, and it needs no
/// initialization.
///
/// The line format is chosen for reading a *decision trail*, not for
/// machine parsing:
///
/// ```text
/// [media_core/backend][debug] selected better_player (score 120) | ...
/// ```
///
/// `name` is `media_core/<category>` so a console can be filtered by
/// category, and the level is mapped onto `dart:developer`'s numeric
/// levels so a full record still shows up with its severity attached.
PlayerLogSink consoleLogSink({bool includeFields = true, bool includeTime = true}) {
  return (PlayerLogRecord record) {
    final buffer = StringBuffer();

    if (includeTime) {
      buffer.write('[${_formatTime(record.timestamp)}]');
    }

    buffer
      ..write('[${record.category.name}]')
      ..write('[${record.level.name}] ')
      ..write(record.message);

    if (includeFields && record.fields.isNotEmpty) {
      buffer.write(' | ${_formatFields(record.fields)}');
    }

    developer.log(
      buffer.toString(),
      name: 'media_core/${record.category.name}',
      level: _developerLevel(record.level),
      error: record.error,
      stackTrace: record.stackTrace,
    );
  };
}

/// Collects log records in memory.
///
/// Useful in tests and for a debug overlay: a bounded ring buffer that can
/// be read back without attaching a stream.
final class MemoryLogSink implements LogSink {
  /// Creates a sink retaining up to [capacity] records.
  MemoryLogSink({this.capacity = 500, this.minimumLevel = LogLevel.trace});

  /// Maximum number of retained records.
  final int capacity;

  /// Records below this level are dropped before they reach the buffer.
  ///
  /// A diagnostics screen rarely wants trace output from four modules at once;
  /// the console can carry that, this keeps the last few hundred useful lines.
  final LogLevel minimumLevel;

  @override
  void call(PlayerLogRecord record) {
    if (!record.level.isAtLeast(minimumLevel)) {
      return;
    }
    _records.add(record);
    while (_records.length > capacity) {
      _records.removeAt(0);
    }
  }

  final List<PlayerLogRecord> _records = <PlayerLogRecord>[];

  /// Retained records, oldest first.
  List<PlayerLogRecord> get records => List<PlayerLogRecord>.unmodifiable(_records);

  /// How many records are retained.
  int get length => _records.length;

  /// Retained records of one category, oldest first.
  List<PlayerLogRecord> forCategory(LogCategory category) {
    return _records.where((record) => record.category == category).toList(growable: false);
  }

  /// Retained messages of one category, oldest first.
  List<String> messagesFor(LogCategory category) {
    return forCategory(category).map((record) => record.message).toList(growable: false);
  }

  /// Whether any retained record contains [fragment].
  bool contains(String fragment) {
    return _records.any((record) => record.message.contains(fragment));
  }

  /// Drops every retained record.
  void clear() {
    _records.clear();
  }

  /// Retained records as text, one line each.
  String dump({LogFormatter formatter = const LogFormatter()}) => _records.map(formatter.format).join('\n');

  @override
  String toString() => 'MemoryLogSink(${_records.length}/$capacity)';
}

String _formatTime(DateTime timestamp) {
  String pad(int value, [int width = 2]) => value.toString().padLeft(width, '0');

  return '${pad(timestamp.hour)}:'
      '${pad(timestamp.minute)}:'
      '${pad(timestamp.second)}.'
      '${pad(timestamp.millisecond, 3)}';
}

String _formatFields(Map<String, Object?> fields) {
  final parts = <String>[];

  for (final entry in fields.entries) {
    parts.add('${entry.key}=${_formatValue(entry.value)}');
  }

  return parts.join(' ');
}

String _formatValue(Object? value) {
  if (value == null) {
    return 'null';
  }

  if (value is String || value is num || value is bool) {
    return '$value';
  }

  if (value is Iterable) {
    return '[${value.map(_formatValue).join(', ')}]';
  }

  return '$value';
}

int _developerLevel(LogLevel level) {
  return switch (level) {
    LogLevel.trace => 300,
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warning => 900,
    LogLevel.error => 1000,
    LogLevel.critical => 1200,
    LogLevel.nothing => 0,
  };
}
