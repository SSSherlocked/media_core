import 'dart:async';

import 'package:media_core_logging/src/log_category.dart';
import 'package:media_core_logging/src/log_filter.dart';
import 'package:media_core_logging/src/log_level.dart';
import 'package:media_core_logging/src/log_scope.dart';

/// Represents one diagnostic log record.
///
/// A [PlayerLogRecord] contains the information associated with one
/// diagnostic log entry.
///
/// Responsibilities:
///
/// - describe log severity
/// - describe log category
/// - store the log message
/// - optionally store an error and stack trace
/// - carry structured diagnostic fields
///
/// It does not:
///
/// - write logs to files
/// - format logs for a specific platform
/// - decide whether a log should be emitted
///
/// Those responsibilities belong to:
///
/// - [PlayerLogger]
/// - platform-specific log sinks
final class PlayerLogRecord {
  /// Creates a log record.
  PlayerLogRecord({
    required this.level,
    required this.category,
    required this.message,
    DateTime? timestamp,
    this.error,
    this.stackTrace,
    Map<String, Object?> fields = const {},
  }) : timestamp = timestamp ?? DateTime.now(),
       fields = Map<String, Object?>.unmodifiable(fields);

  /// Log severity.
  final LogLevel level;

  /// Diagnostic category.
  final LogCategory category;

  /// Human-readable log message.
  final String message;

  /// Time at which the record was created.
  final DateTime timestamp;

  /// Optional error associated with the record.
  final Object? error;

  /// Optional stack trace associated with the record.
  final StackTrace? stackTrace;

  /// Structured diagnostic fields.
  ///
  /// Fields are intended for machine-readable diagnostic information and
  /// should not be used as a replacement for the main log message.
  final Map<String, Object?> fields;

  /// Whether this record contains an error.
  bool get hasError {
    return error != null;
  }

  /// Whether this record contains a stack trace.
  bool get hasStackTrace {
    return stackTrace != null;
  }

  @override
  String toString() {
    return 'PlayerLogRecord('
        'level: $level, '
        'category: $category, '
        'message: $message, '
        'timestamp: $timestamp, '
        'error: $error'
        ')';
  }
}

/// Receives diagnostic log records.
///
/// A sink can forward records to a platform logger, file logger, console,
/// telemetry system, or another diagnostic destination.
typedef PlayerLogSink = void Function(PlayerLogRecord record);

/// Provides centralized diagnostic logging for the media core.
///
/// A [PlayerLogger] is responsible for deciding whether a log record should
/// be emitted and forwarding accepted records to the configured sink and
/// reactive log stream.
///
/// Responsibilities:
///
/// - filter logs by minimum level
/// - enable or disable logging
/// - create [PlayerLogRecord] instances
/// - forward records to a log sink
/// - expose emitted records as a stream
///
/// It does not:
///
/// - implement platform-specific logging
/// - persist diagnostic records
/// - collect performance or memory metrics
/// - decide application-specific logging policy
///
/// Those responsibilities belong to:
///
/// - [PlayerLogSink]
/// - `PerformanceMonitor`
/// - `MemoryMonitor`
/// - `DiagnosticsManager`
final class PlayerLogger {
  /// Creates a player logger.
  PlayerLogger({this.minimumLevel = LogLevel.info, this.enabled = true, PlayerLogSink? sink}) {
    if (sink != null) {
      _sinks.add(sink);
    }
  }

  /// Minimum log level accepted by this logger.
  ///
  /// Records below this level are ignored.
  LogLevel minimumLevel;

  /// Whether logging is enabled.
  bool enabled;

  /// Resolves the minimum level for a category, overriding [minimumLevel].
  ///
  /// This is what makes per-module levels possible. Without it a facade can
  /// only lower the bar globally: raising one category to trace would be undone
  /// here, because the record would still be compared against [minimumLevel].
  /// The facade installs a resolver that reads its category overrides, so
  /// "download at trace, everything else at warning" works with a single logger.
  LogLevel Function(LogCategory category)? levelResolver;

  /// Effective minimum level for [category].
  LogLevel levelFor(LogCategory category) => levelResolver?.call(category) ?? minimumLevel;

  /// Whether a record of [level] in [category] would be emitted.
  bool isEnabledFor(LogCategory category, LogLevel level) => enabled && level.isAtLeast(levelFor(category));

  /// Registered sinks, in registration order.
  final List<PlayerLogSink> _sinks = <PlayerLogSink>[];

  /// Optional developer filter applied before the sinks.
  LogFilter? filter;

  /// Optional rate limit applied per category.
  ///
  /// Off by default: a developer who turned logging on wants to see what
  /// happened, and a throttle that silently drops the first hundred lines of a
  /// burst hides the beginning of the problem.
  LogThrottle? throttle;

  /// How many records this logger has emitted.
  int _emitted = 0;

  /// How many records were dropped by the throttle.
  int _throttled = 0;

  /// Clock used by [throttle]; overridable for deterministic tests.
  DateTime Function() clock = DateTime.now;

  /// Whether this logger has been disposed.
  bool _disposed = false;

  /// Controller for emitted diagnostic records.
  final StreamController<PlayerLogRecord> _recordsController = StreamController<PlayerLogRecord>.broadcast(sync: true);

  /// Stream of accepted diagnostic records.
  Stream<PlayerLogRecord> get records {
    return _recordsController.stream;
  }

  /// Replaces every registered sink with [sink].
  void setSink(PlayerLogSink? sink) {
    _ensureNotDisposed();

    _sinks.clear();
    if (sink != null) {
      _sinks.add(sink);
    }
  }

  /// Adds a sink, keeping the ones already registered.
  ///
  /// Several sinks at once is the normal case: the console for a developer, the
  /// memory sink for a diagnostics screen and the file sink for a bug report are
  /// not alternatives.
  void addSink(PlayerLogSink sink) {
    _ensureNotDisposed();
    _sinks.add(sink);
  }

  /// Removes [sink].
  void removeSink(PlayerLogSink sink) {
    _ensureNotDisposed();
    _sinks.remove(sink);
  }

  /// Removes every sink.
  void clearSinks() {
    _ensureNotDisposed();
    _sinks.clear();
  }

  /// Registered sinks.
  List<PlayerLogSink> get sinks => List<PlayerLogSink>.unmodifiable(_sinks);

  /// Records emitted since this logger was created.
  int get emittedCount => _emitted;

  /// Records dropped by [throttle].
  int get throttledCount => _throttled;

  /// Emits a diagnostic log record.
  ///
  /// The record is emitted only when logging is enabled and [level] meets
  /// [minimumLevel].
  void log(
    LogLevel level,
    LogCategory category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    _ensureNotDisposed();

    if (!isEnabledFor(category, level)) {
      return;
    }

    // Scope fields are merged first so an explicitly passed field wins: the call
    // site knows more about this line than the enclosing scope does.
    final scope = LogScope.fields;
    final mergedFields = scope.isEmpty ? fields : <String, Object?>{...scope, ...fields};

    final developerFilter = filter;
    if (developerFilter != null &&
        !developerFilter.accepts(
          PlayerLogRecord(level: level, category: category, message: message, fields: mergedFields),
        )) {
      return;
    }

    var suppressed = 0;
    final limiter = throttle;
    if (limiter != null) {
      final admission = limiter.admit(category, clock());
      if (!admission.allowed) {
        _throttled++;
        return;
      }
      suppressed = admission.suppressed;
    }

    final record = PlayerLogRecord(
      level: level,
      category: category,
      message: message,
      error: error,
      stackTrace: stackTrace,
      // A throttled burst is reported on the next line that gets through, so a
      // reader can tell one occurrence from four thousand.
      fields: suppressed > 0 ? <String, Object?>{...mergedFields, 'suppressed': suppressed} : mergedFields,
    );

    _emitted++;

    for (final sink in List<PlayerLogSink>.of(_sinks)) {
      sink(record);
    }

    if (!_recordsController.isClosed) {
      _recordsController.add(record);
    }
  }

  /// Emits a trace-level diagnostic record.
  void trace(LogCategory category, String message, {Map<String, Object?> fields = const {}}) {
    log(LogLevel.trace, category, message, fields: fields);
  }

  /// Emits a debug-level diagnostic record.
  void debug(LogCategory category, String message, {Map<String, Object?> fields = const {}}) {
    log(LogLevel.debug, category, message, fields: fields);
  }

  /// Emits an informational diagnostic record.
  void info(LogCategory category, String message, {Map<String, Object?> fields = const {}}) {
    log(LogLevel.info, category, message, fields: fields);
  }

  /// Emits a warning diagnostic record.
  void warning(
    LogCategory category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    log(LogLevel.warning, category, message, error: error, stackTrace: stackTrace, fields: fields);
  }

  /// Emits an error diagnostic record.
  void error(
    LogCategory category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    log(LogLevel.error, category, message, error: error, stackTrace: stackTrace, fields: fields);
  }

  /// Emits a critical diagnostic record.
  void critical(
    LogCategory category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    log(LogLevel.critical, category, message, error: error, stackTrace: stackTrace, fields: fields);
  }

  /// Disposes the logger.
  ///
  /// After disposal, no new records may be emitted.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _sinks.clear();

    await _recordsController.close();
  }

  /// Ensures the logger has not been disposed.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PlayerLogger has been disposed.');
    }
  }
}
