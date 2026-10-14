import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_logging/media_core_logging.dart';

/// Collects records for assertions.
final class _Collector {
  final List<PlayerLogRecord> records = <PlayerLogRecord>[];

  void call(PlayerLogRecord record) => records.add(record);

  List<String> get messages => records.map((record) => record.message).toList();
}

Directory _tempDirectory() {
  final directory = Directory.systemTemp.createTempSync('media_core_logging_test');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

void main() {
  group('LogLevel', () {
    test('orders levels from trace to nothing', () {
      expect(LogLevel.trace.isAtLeast(LogLevel.trace), isTrue);
      expect(LogLevel.debug.isAtLeast(LogLevel.trace), isTrue);
      expect(LogLevel.info.isAtLeast(LogLevel.debug), isTrue);
      expect(LogLevel.trace.isAtLeast(LogLevel.debug), isFalse);
      expect(LogLevel.nothing.isAtLeast(LogLevel.critical), isTrue);
      expect(LogLevel.critical.isAtLeast(LogLevel.nothing), isFalse);
    });

    test('marks error and critical as errors', () {
      expect(LogLevel.error.isError, isTrue);
      expect(LogLevel.critical.isError, isTrue);
      expect(LogLevel.warning.isError, isFalse);
    });

    test('has a stable name per level', () {
      expect(LogLevel.trace.name, 'trace');
      expect(LogLevel.critical.name, 'critical');
      expect(LogLevel.nothing.name, 'nothing');
    });
  });

  group('PlayerLogger', () {
    late _Collector collector;
    late PlayerLogger logger;

    setUp(() {
      collector = _Collector();
      logger = PlayerLogger(minimumLevel: LogLevel.debug, sink: collector.call);
    });

    test('drops records below the minimum level', () {
      logger
        ..trace(LogCategory.playback, 'ignored')
        ..debug(LogCategory.playback, 'kept');

      expect(collector.messages, <String>['kept']);
    });

    test('emits every level through its convenience method', () {
      logger
        ..trace(LogCategory.playback, 'trace')
        ..debug(LogCategory.playback, 'debug')
        ..info(LogCategory.playback, 'info')
        ..warning(LogCategory.playback, 'warning')
        ..error(LogCategory.playback, 'error')
        ..critical(LogCategory.playback, 'critical');

      expect(collector.messages, <String>['debug', 'info', 'warning', 'error', 'critical']);
      expect(logger.emittedCount, 5);
    });

    test('does nothing when disabled', () {
      logger
        ..enabled = false
        ..error(LogCategory.playback, 'nope');

      expect(collector.records, isEmpty);
    });

    test('fans out to every registered sink', () {
      final second = _Collector();
      logger
        ..addSink(second.call)
        ..info(LogCategory.playback, 'both');

      expect(collector.messages, <String>['both']);
      expect(second.messages, <String>['both']);
    });

    test('setSink replaces the list instead of adding to it', () {
      final replacement = _Collector();
      logger
        ..setSink(replacement.call)
        ..info(LogCategory.playback, 'only replacement');

      expect(collector.records, isEmpty);
      expect(replacement.messages, <String>['only replacement']);
    });

    test('removeSink stops delivery to that sink only', () {
      final second = _Collector();
      logger
        ..addSink(second.call)
        ..removeSink(second.call)
        ..info(LogCategory.playback, 'first only');

      expect(collector.messages, <String>['first only']);
      expect(second.records, isEmpty);
    });

    test('exposes records as a stream for a live view', () async {
      final seen = <String>[];
      final subscription = logger.records.listen((record) => seen.add(record.message));

      logger.info(LogCategory.playback, 'streamed');
      await Future<void>.delayed(Duration.zero);

      expect(seen, <String>['streamed']);
      await subscription.cancel();
    });

    test('a developer filter narrows by category and keyword', () {
      logger
        ..filter = LogFilter(categories: {LogCategory.playback}, keyword: 'open')
        ..info(LogCategory.playback, 'opened stream')
        ..info(LogCategory.playback, 'closed stream')
        ..info(LogCategory.session, 'opened session');

      expect(collector.messages, <String>['opened stream']);
    });

    test('a throttle bounds a hot path and reports what it dropped', () {
      logger
        ..minimumLevel = LogLevel.trace
        ..clock = (() => DateTime(2026, 9, 26, 12))
        ..throttle = LogThrottle(maxRecords: 2);

      for (var index = 0; index < 5; index++) {
        logger.debug(LogCategory.buffering, 'frame $index');
      }

      expect(collector.messages.length, 2);
      expect(logger.throttledCount, 3);
    });

    test('the suppressed count is attached to the next record that gets through', () {
      var now = DateTime(2026, 9, 26, 12);
      logger
        ..minimumLevel = LogLevel.trace
        ..clock = (() => now)
        ..throttle = LogThrottle(maxRecords: 1)
        ..debug(LogCategory.buffering, 'first')
        ..debug(LogCategory.buffering, 'dropped')
        ..debug(LogCategory.buffering, 'dropped');
      now = now.add(const Duration(seconds: 2));
      logger.debug(LogCategory.buffering, 'next window');

      expect(collector.records.last.fields['suppressed'], 2);
    });

    test('scope fields are attached to records inside the scope', () {
      LogScope.run(<String, Object?>{'roomId': 'r1'}, () {
        logger.info(LogCategory.session, 'inside');
      });
      logger.info(LogCategory.session, 'outside');

      expect(collector.records.first.fields['roomId'], 'r1');
      expect(collector.records.last.fields.containsKey('roomId'), isFalse);
    });

    test('an explicit field wins over the scope', () {
      LogScope.run(<String, Object?>{'roomId': 'scope'}, () {
        logger.info(LogCategory.session, 'explicit', fields: <String, Object?>{'roomId': 'call-site'});
      });

      expect(collector.records.single.fields['roomId'], 'call-site');
    });

    test('nested scopes merge', () {
      LogScope.run(<String, Object?>{'roomId': 'r1'}, () {
        LogScope.run(<String, Object?>{'playerId': 'p1'}, () {
          logger.info(LogCategory.session, 'nested');
        });
      });

      final fields = collector.records.single.fields;
      expect(fields['roomId'], 'r1');
      expect(fields['playerId'], 'p1');
    });

    test('a disposed logger refuses work', () async {
      await logger.dispose();

      expect(() => logger.info(LogCategory.playback, 'after dispose'), throwsA(isA<StateError>()));
    });
  });

  group('LogModule', () {
    late _Collector collector;
    late PlayerLogger logger;

    setUp(() {
      collector = _Collector();
      logger = PlayerLogger(minimumLevel: LogLevel.debug, sink: collector.call);
    });

    test('tags every record with its own category', () {
      final playback = LogModule(LogCategory.playback, () => logger);
      final session = LogModule(LogCategory.session, () => logger);

      playback.debug('opened');
      session.error('failed');

      expect(collector.records[0].category, LogCategory.playback);
      expect(collector.records[1].category, LogCategory.session);
    });

    test('reports whether a level is worth building fields for', () {
      final playback = LogModule(LogCategory.playback, () => logger);

      expect(playback.isDebugEnabled, isTrue);
      expect(playback.isTraceEnabled, isFalse);

      logger.minimumLevel = LogLevel.nothing;
      expect(playback.isDebugEnabled, isFalse);
    });
  });

  group('LogFormatter', () {
    test('renders one line with level, category, message and fields', () {
      const formatter = LogFormatter();
      final record = PlayerLogRecord(
        level: LogLevel.warning,
        category: LogCategory.playback,
        message: 'stalled',
        timestamp: DateTime(2026, 9, 26, 12, 3, 4, 5),
        fields: const <String, Object?>{'roomId': 'r1'},
      );

      final line = formatter.format(record);

      expect(line, contains('12:03:04.005'));
      expect(line, contains('[WARNING ]'));
      expect(line, contains('[playback'));
      expect(line, contains('stalled'));
      expect(line, contains('roomId=r1'));
      expect(line.contains('\n'), isFalse, reason: 'one record is one line');
    });

    test('appends the error but not the stack trace by default', () {
      const formatter = LogFormatter();
      final record = PlayerLogRecord(
        level: LogLevel.error,
        category: LogCategory.error,
        message: 'failed',
        error: StateError('boom'),
        stackTrace: StackTrace.current,
      );

      final line = formatter.format(record);

      expect(line, contains('error='));
      expect(line, isNot(contains('#0')));
    });

    test('can include the stack trace when asked', () {
      const formatter = LogFormatter(includeStackTrace: true);
      final record = PlayerLogRecord(
        level: LogLevel.error,
        category: LogCategory.error,
        message: 'failed',
        stackTrace: StackTrace.current,
      );

      expect(formatter.format(record), contains('\n'));
    });
  });

  group('MemoryLogSink', () {
    test('keeps the newest records within its capacity', () {
      final sink = MemoryLogSink(capacity: 2);

      for (var index = 0; index < 4; index++) {
        sink(PlayerLogRecord(level: LogLevel.info, category: LogCategory.playback, message: 'm$index'));
      }

      expect(sink.records.map((record) => record.message).toList(), <String>['m2', 'm3']);
    });

    test('drops records below its own level floor', () {
      final sink = MemoryLogSink(minimumLevel: LogLevel.warning);

      sink(PlayerLogRecord(level: LogLevel.debug, category: LogCategory.playback, message: 'debug'));
      sink(PlayerLogRecord(level: LogLevel.error, category: LogCategory.playback, message: 'error'));

      expect(sink.records.single.message, 'error');
    });

    test('filters by category and searches text', () {
      final sink = MemoryLogSink();
      sink(PlayerLogRecord(level: LogLevel.info, category: LogCategory.playback, message: 'opened r1'));
      sink(PlayerLogRecord(level: LogLevel.info, category: LogCategory.session, message: 'closed r1'));

      expect(sink.forCategory(LogCategory.playback).single.message, 'opened r1');
      expect(sink.messagesFor(LogCategory.session), <String>['closed r1']);
      expect(sink.contains('closed'), isTrue);
      expect(sink.contains('missing'), isFalse);
    });

    test('dumps as text and clears', () {
      final sink = MemoryLogSink();
      sink(PlayerLogRecord(level: LogLevel.info, category: LogCategory.playback, message: 'opened'));

      expect(sink.dump(), contains('opened'));

      sink.clear();
      expect(sink.length, 0);
    });
  });

  group('LogFileSink', () {
    test('appends formatted lines', () async {
      final directory = _tempDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}run.log');
      final sink = LogFileSink(file, flushInterval: const Duration(days: 1));
      // Settles the first auto-flush trigger, so every later write happens on an
      // explicit, awaited flush and the assertions are deterministic.
      await sink.flush();

      sink(PlayerLogRecord(level: LogLevel.info, category: LogCategory.pool, message: 'acquired'));
      await sink.flush();

      expect(await file.readAsString(), contains('acquired'));
      expect(sink.writtenLines, 1);
    });

    test('rotates when the file grows past its limit', () async {
      final separator = Platform.pathSeparator;
      final directory = _tempDirectory();
      final file = File('${directory.path}${separator}run.log');
      final sink = LogFileSink(file, maxBytes: 200, maxFiles: 2, flushInterval: const Duration(days: 1));
      await sink.flush();

      for (var index = 0; index < 40; index++) {
        sink(PlayerLogRecord(level: LogLevel.info, category: LogCategory.pool, message: 'line $index ${'x' * 20}'));
        await sink.flush();
      }

      expect(file.existsSync(), isTrue);
      expect(File('${file.path}.1').existsSync(), isTrue, reason: 'the previous file was rotated');
    });

    test('close waits for a write that is already in flight', () async {
      final directory = _tempDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}inflight.log');
      final sink = LogFileSink(file);

      // The first record triggers the sink's own unawaited flush; closing right
      // after must not return before those bytes are on disk, because a bug
      // report reads the file at that moment.
      sink(PlayerLogRecord(level: LogLevel.info, category: LogCategory.pool, message: 'in flight'));
      await sink.close();

      expect(file.existsSync(), isTrue);
      expect(await file.readAsString(), contains('in flight'));
    });

    test('close flushes and refuses further records', () async {
      final directory = _tempDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}run.log');
      final sink = LogFileSink(file, flushInterval: const Duration(days: 1));
      await sink.flush();

      sink(PlayerLogRecord(level: LogLevel.info, category: LogCategory.pool, message: 'before close'));
      await sink.close();
      sink(PlayerLogRecord(level: LogLevel.info, category: LogCategory.pool, message: 'after close'));

      final content = await file.readAsString();
      expect(content, contains('before close'));
      expect(content.contains('after close'), isFalse);
      expect(sink.isClosed, isTrue);
    });
  });

  group('MediaCoreLog facade', () {
    tearDown(MediaCoreLog.reset);

    test('is silent until a level is set', () {
      final collector = _Collector();
      MediaCoreLog.clearSinks();
      MediaCoreLog.addSink(collector.call);
      MediaCoreLog.level = LogLevel.nothing;

      MediaCoreLog.info(LogCategory.playback, 'silent');

      expect(MediaCoreLog.defaultLevel, LogLevel.nothing, reason: 'logging is opt-in');
      expect(collector.records, isEmpty);
    });

    test('emits once a level is set and stops when silenced again', () {
      final collector = _Collector();
      MediaCoreLog.clearSinks();
      MediaCoreLog.addSink(collector.call);
      MediaCoreLog.level = LogLevel.info;

      MediaCoreLog.info(LogCategory.playback, 'audible');
      MediaCoreLog.debug(LogCategory.playback, 'still below the level');

      expect(collector.messages, <String>['audible']);
    });

    test('a category level turns one module up without the rest', () {
      final collector = _Collector();
      MediaCoreLog.clearSinks();
      MediaCoreLog.addSink(collector.call);
      MediaCoreLog.level = LogLevel.warning;
      MediaCoreLog.setCategoryLevel(LogCategory.download, LogLevel.trace);

      MediaCoreLog.debug(LogCategory.download, 'download detail');
      MediaCoreLog.debug(LogCategory.playback, 'playback detail');

      expect(collector.messages, <String>['download detail']);
      expect(MediaCoreLog.minimumLevelFor(LogCategory.download), LogLevel.trace);
      expect(MediaCoreLog.isEnabled(LogCategory.download, LogLevel.trace), isTrue);
      expect(MediaCoreLog.isEnabled(LogCategory.playback, LogLevel.debug), isFalse);
    });

    test('a module logger follows a replaced hub logger', () {
      final module = MediaCoreLog.of(LogCategory.pool);
      final collector = _Collector();
      MediaCoreLog.level = LogLevel.info;
      MediaCoreLog.clearSinks();
      MediaCoreLog.addSink(collector.call);

      module.info('before reset');
      MediaCoreLog.reset();
      MediaCoreLog.level = LogLevel.info;
      final after = _Collector();
      MediaCoreLog.clearSinks();
      MediaCoreLog.addSink(after.call);
      module.info('after reset');

      expect(collector.messages, <String>['before reset']);
      expect(after.messages, <String>[
        'after reset',
      ], reason: 'the module must not keep logging into the replaced logger');
    });

    test('resolves a level from its name', () {
      expect(MediaCoreLog.levelFromName('debug'), LogLevel.debug);
      expect(MediaCoreLog.levelFromName('nonsense'), isNull);
      expect(MediaCoreLog.setLevelFromName('warning'), LogLevel.warning);
    });

    test('the module logger tags records with its category', () {
      final collector = _Collector();
      MediaCoreLog.clearSinks();
      MediaCoreLog.addSink(collector.call);
      MediaCoreLog.level = LogLevel.debug;

      MediaCoreLog.of(LogCategory.multiview).debug('cell assigned');

      expect(collector.records.single.category, LogCategory.multiview);
    });

    test('attachMemorySink registers a readable sink', () {
      final sink = MediaCoreLog.attachMemorySink(capacity: 10);
      MediaCoreLog.level = LogLevel.info;

      MediaCoreLog.info(LogCategory.logging, 'captured');

      expect(sink.contains('captured'), isTrue);
    });

    test('attachFileSink writes through to a file', () async {
      final directory = _tempDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}f.log');
      final sink = MediaCoreLog.attachFileSink(file);
      MediaCoreLog.level = LogLevel.info;
      await sink.flush();

      MediaCoreLog.info(LogCategory.logging, 'to disk');
      await sink.close();

      expect(await file.readAsString(), contains('to disk'));
    });

    test('scoped fields reach records logged through the facade', () {
      final collector = _Collector();
      MediaCoreLog.clearSinks();
      MediaCoreLog.addSink(collector.call);
      MediaCoreLog.level = LogLevel.info;

      MediaCoreLog.scoped(<String, Object?>{'roomId': 'r9'}, () {
        MediaCoreLog.info(LogCategory.session, 'scoped');
      });

      expect(collector.records.single.fields['roomId'], 'r9');
    });
  });
}
