import 'dart:io';

import 'package:example/demos/module_demo.dart';
import 'package:media_core_logging/media_core_logging.dart';

/// Levelled logging: what gets through, where it goes, and what it costs.
///
/// Logging is the module a developer configures but rarely inspects, so this
/// demo prints the *records*, not a description of them: which lines survived a
/// level, what the per-category override changed, what a filter narrowed, and
/// the counts a throttle reported on the next line that got through.
class LoggingDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'logging';

  @override
  ModuleCategory get category => ModuleCategory.foundation;

  @override
  String get nameZh => '分级日志：等级 / 分类 / sink / 过滤 / 节流';

  @override
  String get nameEn => 'Levelled logging: levels, categories, sinks, filters, throttling';

  @override
  String get purposeZh => '日志默认完全静默；开启后按「分类的有效最低等级」决定是否产生记录。同一份记录可以同时进控制台、内存环形缓冲与轮转文件，开发者还能按分类收窄、按关键词搜索、给热路径限流。';

  @override
  String get purposeEn =>
      'Logging is silent by default; once on, a record is produced when its level meets the effective minimum for its category. The same record can go to the console, a memory ring buffer and a rotating file at once, and a developer can narrow by category, search by keyword and rate-limit a hot path.';

  @override
  List<String> get pointsZh => const <String>[
    'MediaCoreLog.level — 全局最低等级；setCategoryLevel 只调高一个模块',
    'MemoryLogSink — 内存环形缓冲，给应用内日志页或"复制诊断"用',
    'LogFileSink — 追加写文件，按 maxBytes 轮转、保留 maxFiles 份',
    'LogFilter — 限定分类 + 关键词搜索（消息与字段一起搜）',
    'LogThrottle — 被丢弃的条数附在下一条通过的记录上（suppressed）',
    'LogScope.run — 作用域内每条记录自动带上 roomId 之类的上下文',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'MediaCoreLog.level — the global floor; setCategoryLevel raises one module only',
    'MemoryLogSink — a ring buffer for an in-app log screen or "copy diagnostics"',
    'LogFileSink — append-only file, rotating at maxBytes and keeping maxFiles',
    'LogFilter — category narrowing plus keyword search over messages and fields',
    'LogThrottle — the dropped count rides on the next record that gets through (suppressed)',
    'LogScope.run — every record inside carries context such as roomId',
  ];

  @override
  String get snippet => r'''
MediaCoreLog.level = LogLevel.warning;                            // global floor
MediaCoreLog.setCategoryLevel(LogCategory.playback, LogLevel.trace);  // one module louder

final memory = MediaCoreLog.attachMemorySink(capacity: 500);
MediaCoreLog.attachFileSink(File('${dir}/media_core.log'));

LogScope.run({'roomId': room.id}, () {
  MediaCoreLog.playback('opened', fields: {'uri': uri});   // tagged with the room
});

print(memory.messagesFor(LogCategory.playback));
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();

    // The example app turns logging on globally; start from silence so the demo
    // shows what the settings do rather than what the app already configured.
    MediaCoreLog.reset();
    MediaCoreLog.level = LogLevel.warning;

    final memory = MemoryLogSink(capacity: 100);
    MediaCoreLog.addSink(memory.call);
    MediaCoreLog.setCategoryLevel(LogCategory.playback, LogLevel.trace);

    try {
      buffer
        ..writeln(
          'global level: ${MediaCoreLog.level.name}, '
          'playback override: ${MediaCoreLog.minimumLevelFor(LogCategory.playback).name}',
        )
        ..writeln();

      // Five records, three of which are below their category's floor.
      MediaCoreLog.trace(LogCategory.playback, 'per-frame detail');
      MediaCoreLog.debug(LogCategory.playback, 'opened stream');
      MediaCoreLog.info(LogCategory.pool, 'acquired a player');
      MediaCoreLog.warning(LogCategory.recovery, 'retrying the same line');
      MediaCoreLog.error(LogCategory.source, 'signed URL expired', fields: <String, Object?>{'expiresIn': '0s'});

      buffer
        ..writeln(
          'after emitting 5 records (playback trace, playback debug, pool info, recovery warning, source error):',
        )
        ..writeln(memory.dump())
        ..writeln();

      // Scope fields: the same message, once inside a scope.
      MediaCoreLog.setCategoryLevel(LogCategory.session, LogLevel.debug);
      LogScope.run(<String, Object?>{'roomId': 'r-8891', 'engine': 'media_kit'}, () {
        MediaCoreLog.debug(LogCategory.session, 'session opened');
      });
      MediaCoreLog.debug(LogCategory.session, 'session opened');

      final scoped = memory.forCategory(LogCategory.session);
      buffer
        ..writeln('scope fields (same message, inside and outside LogScope.run):')
        ..writeln('  inside : ${scoped.first.fields}')
        ..writeln('  outside: ${scoped.last.fields}')
        ..writeln();

      // A filter is what a developer reaches for while staring at output.
      MediaCoreLog.setCategoryLevel(LogCategory.playback, LogLevel.nothing);
      MediaCoreLog.filter = LogFilter(categories: <LogCategory>{LogCategory.recovery}, keyword: 'line');
      memory.clear();

      MediaCoreLog.warning(LogCategory.recovery, 'retrying the same line');
      MediaCoreLog.warning(LogCategory.recovery, 'gave up on the engine');
      MediaCoreLog.warning(LogCategory.pool, 'retrying the same line');

      buffer
        ..writeln('filter {recovery} + keyword "line" → ${memory.length} record(s)')
        ..writeln('  ${memory.messagesFor(LogCategory.recovery)}')
        ..writeln();

      MediaCoreLog.filter = null;

      // Throttling a hot path, and how the dropped count is reported.
      MediaCoreLog.setCategoryLevel(LogCategory.buffering, LogLevel.trace);
      MediaCoreLog.throttle = LogThrottle(maxRecords: 2, window: const Duration(seconds: 30));
      memory.clear();

      for (var frame = 1; frame <= 6; frame++) {
        MediaCoreLog.trace(LogCategory.buffering, 'frame $frame');
      }

      buffer
        ..writeln('throttle {2 records / 30s}, 6 frames emitted →')
        ..writeln('  delivered: ${memory.messagesFor(LogCategory.buffering)}')
        ..writeln('  reported : ${MediaCoreLog.throttledCount} record(s) dropped by the throttle')
        ..writeln('  (a burst is not lost silently: the count rides on the next record that passes)')
        ..writeln();

      MediaCoreLog.throttle = null;

      // A file sink is what a bug report reads; rotation is its whole policy.
      final directory = await Directory.systemTemp.createTemp('media_core_logging_demo');
      final file = File('${directory.path}${Platform.pathSeparator}media_core.log');
      final fileSink = LogFileSink(file, maxBytes: 4 * 1024);

      MediaCoreLog.addSink(fileSink.call);
      MediaCoreLog.setCategoryLevel(LogCategory.logging, LogLevel.info);
      MediaCoreLog.info(LogCategory.logging, 'this line goes to the console, the memory sink and the file');

      // Closing the sink is not enough to let go of the file: it is still
      // registered, and the next record would open it again.
      MediaCoreLog.removeSink(fileSink.call);

      await fileSink.close();

      final written = file.existsSync() ? await file.readAsString() : '';
      buffer
        ..writeln('file sink → ${file.path}')
        ..writeln(
          '  lines on disk: ${written.trim().split('\n').length}, '
          'rotating at ${fileSink.maxBytes ~/ 1024}KB, keeping ${fileSink.maxFiles} file(s)',
        )
        ..writeln('  last line: ${written.trim().split('\n').last}');

      await _deleteQuietly(directory);

      buffer
        ..writeln()
        ..writeln('cost when disabled: one enum comparison per dropped record — nothing is built')
        ..writeln('until a level check passes, which is why call sites pass values, not strings.');

      return buffer.toString();
    } finally {
      MediaCoreLog.reset();
    }
  }

  /// Removes a temp directory, tolerating a Windows file lock.
  ///
  /// A demo that fails while cleaning up after itself looks broken for a reason
  /// that has nothing to do with what it demonstrates.
  Future<void> _deleteQuietly(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Windows keeps the handle briefly after close; the OS cleans the temp
      // directory up later.
    }
  }
}
