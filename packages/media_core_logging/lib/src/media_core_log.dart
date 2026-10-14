import 'dart:io';

import 'package:media_core_logging/src/log_category.dart';
import 'package:media_core_logging/src/log_file_sink.dart';
import 'package:media_core_logging/src/log_filter.dart';
import 'package:media_core_logging/src/log_formatter.dart';
import 'package:media_core_logging/src/log_level.dart';
import 'package:media_core_logging/src/log_module.dart';
import 'package:media_core_logging/src/log_scope.dart';
import 'package:media_core_logging/src/memory_log_sink.dart';
import 'package:media_core_logging/src/player_logger.dart';

/// The framework-wide logging entry point.
///
/// Every module logs through this hub instead of holding a logger
/// reference. That is a deliberate trade: a logger injected through every
/// constructor would touch every public signature in the framework, and
/// the point of this log is to answer *cross-module* questions — "why did
/// playback end up on this backend?" — which single-module plumbing
/// cannot answer anyway.
///
/// ## Configuring it
///
/// One line turns on the decision trail:
///
/// ```dart
/// MediaCoreLog.level = LogLevel.debug;
/// ```
///
/// Or, when only one part of the framework is under investigation:
///
/// ```dart
/// MediaCoreLog.configure(
///   level: LogLevel.warning,
///   categories: <LogCategory, LogLevel>{
///     LogCategory.fallback: LogLevel.debug,
///     LogCategory.recovery: LogLevel.debug,
///   },
/// );
/// ```
///
/// Routing records somewhere other than the console:
///
/// ```dart
/// final memory = MemoryLogSink();
/// MediaCoreLog.configure(sink: memory.call);
/// // ... reproduce the problem ...
/// print(memory.messagesFor(LogCategory.fallback));
/// ```
///
/// Everything is reversible through [reset].
///
/// ## Levels
///
/// [LogLevel] orders severity; a record is emitted when its level is at
/// least as severe as the effective minimum for its category. The
/// per-category override map exists because debugging one broken engine
/// should not require drowning in another module's trace output.
///
/// Cost when disabled: one enum comparison per dropped record. Nothing is
/// built — no strings, no maps — until a level check passes, which is why
/// call sites pass values instead of pre-formatted messages.
abstract final class MediaCoreLog {
  MediaCoreLog._();

  /// Level used before any explicit configuration.
  ///
  /// The default is [LogLevel.nothing]: a host that never configures
  /// logging gets no output at all. Turn it on explicitly - typically in
  /// debug builds - with `MediaCoreLog.level = LogLevel.info` (or
  /// `configure` for per-category control).
  static const LogLevel defaultLevel = LogLevel.nothing;

  static PlayerLogger _logger = _createLogger();

  static final Map<LogCategory, LogLevel> _categoryLevels = <LogCategory, LogLevel>{};

  /// Builds the hub logger and links the per-category overrides into it.
  ///
  /// The logger cannot read [_categoryLevels] on its own, and without that link
  /// a category override would be accepted by the facade and then rejected by
  /// the logger's own global check.
  static PlayerLogger _createLogger() {
    final logger = PlayerLogger(minimumLevel: defaultLevel, sink: consoleLogSink())..levelResolver = _resolveLevel;

    return logger;
  }

  /// Effective minimum level of [category], honouring the override map.
  static LogLevel _resolveLevel(LogCategory category) => _categoryLevels[category] ?? _logger.minimumLevel;

  /// Adds a sink without dropping the ones already registered.
  ///
  /// The console is the default sink, so this is how a diagnostics screen or a
  /// bug report gets its data: the console stays for the developer watching, and
  /// the memory or file sink collects what needs to be handed over.
  static void addSink(PlayerLogSink sink) => _logger.addSink(sink);

  /// Removes a previously added sink.
  static void removeSink(PlayerLogSink sink) => _logger.removeSink(sink);

  /// Removes every sink, including the console.
  static void clearSinks() => _logger.clearSinks();

  /// Registered sinks.
  static List<PlayerLogSink> get sinks => _logger.sinks;

  /// Creates a memory sink, registers it and returns it.
  ///
  /// The returned sink is what an in-app log screen or a "copy diagnostics"
  /// button reads from; it keeps the most recent [capacity] records only.
  static MemoryLogSink attachMemorySink({int capacity = 500, LogLevel minimumLevel = LogLevel.trace}) {
    final sink = MemoryLogSink(capacity: capacity, minimumLevel: minimumLevel);
    addSink(sink.call);
    return sink;
  }

  /// Creates a rotating file sink, registers it and returns it.
  ///
  /// Call [LogFileSink.close] when done: the sink buffers, and a bug report
  /// needs the last lines on disk, not in a buffer.
  static LogFileSink attachFileSink(
    File file, {
    LogFormatter formatter = const LogFormatter(),
    int maxBytes = 2 * 1024 * 1024,
    int maxFiles = 3,
  }) {
    final sink = LogFileSink(file, formatter: formatter, maxBytes: maxBytes, maxFiles: maxFiles);
    addSink(sink.call);
    return sink;
  }

  /// The developer filter (category narrowing, keyword search), or `null`.
  static LogFilter? get filter => _logger.filter;

  /// Sets the developer filter (category narrowing, keyword search), or clears it.
  static set filter(LogFilter? value) => _logger.filter = value;

  /// The rate limit per category, or `null`.
  static LogThrottle? get throttle => _logger.throttle;

  /// Sets the rate limit per category, or clears it.
  static set throttle(LogThrottle? value) => _logger.throttle = value;

  /// Records emitted since start.
  static int get emittedCount => _logger.emittedCount;

  /// Records dropped by the throttle.
  static int get throttledCount => _logger.throttledCount;

  /// A logger bound to [category].
  ///
  /// The form used by modules: `MediaCoreLog.of(LogCategory.playback).debug(...)`
  /// keeps a call site from repeating its own category on every line, which is
  /// what makes per-module levels worth having.
  static LogModule of(LogCategory category) => LogModule(category, () => _logger);

  /// Runs [body] with [fields] attached to every record inside it.
  static R scoped<R>(Map<String, Object?> fields, R Function() body) => LogScope.run(fields, body);

  /// Runs [body] with [fields] attached, awaiting its result.
  static Future<R> scopedAsync<R>(Map<String, Object?> fields, Future<R> Function() body) =>
      LogScope.runAsync(fields, body);

  /// The underlying logger.
  ///
  /// Exposed for consumers that want the record stream or need to hand a
  /// logger to code that already expects one.
  static PlayerLogger get logger => _logger;

  /// Global minimum level.
  ///
  /// A category override wins over this value for that category.
  static LogLevel get level => _logger.minimumLevel;

  /// Changes the global minimum level.
  static set level(LogLevel value) {
    _logger.minimumLevel = value;
  }

  /// Whether logging is switched on at all.
  static bool get enabled => _logger.enabled;

  /// Switches logging on or off without touching levels.
  static set enabled(bool value) {
    _logger.enabled = value;
  }

  /// Stream of emitted records.
  static Stream<PlayerLogRecord> get records => _logger.records;

  /// Per-category level overrides.
  static Map<LogCategory, LogLevel> get categoryLevels => Map<LogCategory, LogLevel>.unmodifiable(_categoryLevels);

  /// Configures the hub in one call.
  ///
  /// [categories] is merged into the existing overrides unless
  /// [replaceCategories] is set, so a caller can enable one category
  /// without having to restate the others.
  static void configure({
    LogLevel? level,
    bool? enabled,
    PlayerLogSink? sink,
    Map<LogCategory, LogLevel>? categories,
    bool replaceCategories = false,
  }) {
    if (level != null) {
      _logger.minimumLevel = level;
    }

    if (enabled != null) {
      _logger.enabled = enabled;
    }

    if (sink != null) {
      _logger.setSink(sink);
    }

    if (categories != null) {
      if (replaceCategories) {
        _categoryLevels.clear();
      }

      _categoryLevels.addAll(categories);
    }
  }

  /// Overrides the level of one category.
  static void setCategoryLevel(LogCategory category, LogLevel level) {
    _categoryLevels[category] = level;
  }

  /// Removes the override of one category.
  static void clearCategoryLevel(LogCategory category) {
    _categoryLevels.remove(category);
  }

  /// Removes every category override.
  static void clearCategoryLevels() {
    _categoryLevels.clear();
  }

  /// Parses a level from its [LogLevelX.name], case-insensitively.
  ///
  /// Accepts the common aliases `warn` and `none`/`off` (`off` maps to
  /// [LogLevel.critical], which silences everything below it). Returns
  /// `null` for an unknown name so a caller can decide whether that is an
  /// error or a fallback.
  static LogLevel? levelFromName(String name) {
    switch (name.trim().toLowerCase()) {
      case 'trace':
        return LogLevel.trace;
      case 'debug':
        return LogLevel.debug;
      case 'info':
        return LogLevel.info;
      case 'warn':
      case 'warning':
        return LogLevel.warning;
      case 'error':
        return LogLevel.error;
      case 'critical':
      case 'fatal':
        return LogLevel.critical;
      case 'off':
      case 'none':
        return LogLevel.critical;
      default:
        return null;
    }
  }

  /// Sets the level from a name, falling back to [defaultLevel] when the
  /// name is unknown.
  static LogLevel setLevelFromName(String name) {
    final parsed = levelFromName(name) ?? defaultLevel;

    level = parsed;

    return parsed;
  }

  /// Effective minimum level of [category].
  static LogLevel minimumLevelFor(LogCategory category) {
    return _categoryLevels[category] ?? _logger.minimumLevel;
  }

  /// Whether a record of [level] in [category] would be emitted.
  static bool isEnabled(LogCategory category, LogLevel level) {
    if (!_logger.enabled) {
      return false;
    }

    return level.isAtLeast(minimumLevelFor(category));
  }

  /// Emits a record.
  static void log(
    LogLevel level,
    LogCategory category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    if (!isEnabled(category, level)) {
      return;
    }

    _logger.log(level, category, message, error: error, stackTrace: stackTrace, fields: fields);
  }

  /// Emits a trace-level record.
  static void trace(LogCategory category, String message, {Map<String, Object?> fields = const <String, Object?>{}}) {
    log(LogLevel.trace, category, message, fields: fields);
  }

  /// Emits a debug-level record.
  static void debug(LogCategory category, String message, {Map<String, Object?> fields = const <String, Object?>{}}) {
    log(LogLevel.debug, category, message, fields: fields);
  }

  /// Emits an info-level record.
  static void info(LogCategory category, String message, {Map<String, Object?> fields = const <String, Object?>{}}) {
    log(LogLevel.info, category, message, fields: fields);
  }

  /// Emits a warning-level record.
  static void warning(
    LogCategory category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    log(LogLevel.warning, category, message, error: error, stackTrace: stackTrace, fields: fields);
  }

  /// Emits an error-level record.
  static void error(
    LogCategory category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    log(LogLevel.error, category, message, error: error, stackTrace: stackTrace, fields: fields);
  }

  /// Emits a critical-level record.
  static void critical(
    LogCategory category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    log(LogLevel.critical, category, message, error: error, stackTrace: stackTrace, fields: fields);
  }

  /// Replaces the logger and returns the previous one.
  static PlayerLogger install(PlayerLogger logger) {
    final previous = _logger;

    // A caller who installed a logger with a resolver of their own keeps it;
    // otherwise the hub's per-category overrides are wired in, so
    // `setCategoryLevel` keeps working after an install.
    logger.levelResolver ??= _resolveLevel;

    _logger = logger;

    return previous;
  }

  /// Restores the default logger, level and category overrides.
  static void reset() {
    _categoryLevels.clear();
    _logger = _createLogger();
  }
}
