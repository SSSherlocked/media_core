import 'package:media_core_logging/src/log_category.dart';
import 'package:media_core_logging/src/log_level.dart';
import 'package:media_core_logging/src/media_core_log.dart' show MediaCoreLog;
import 'package:media_core_logging/src/player_logger.dart';

/// A logger bound to one category.
///
/// Every module logs under its own category, and repeating that category on
/// every call site is both noise and a chance to get it wrong. A module holds
/// one of these and its lines are tagged automatically:
///
/// ```dart
/// final _log = MediaCoreLog.of(LogCategory.playback);
/// _log.debug('opened', fields: {'uri': uri});
/// ```
///
/// [isEnabled] exists for the hot paths: a record that would be filtered out
/// still costs whatever it took to build its fields, and a per-frame call site
/// should not format a map per frame just to have it dropped.
///
/// The logger is resolved per call rather than captured at construction: a host
/// that replaces the hub's logger ([MediaCoreLog.reset], [MediaCoreLog.install])
/// would otherwise leave every module logging into the logger it replaced, and
/// the module's records would silently stop reaching the new sinks.
final class LogModule {
  /// Creates a module logger.
  const LogModule(this.category, this._loggerOf);

  /// Category every record from this logger is tagged with.
  final LogCategory category;

  final PlayerLogger Function() _loggerOf;

  PlayerLogger get _logger => _loggerOf();

  /// Whether [level] would be emitted for this category.
  bool isEnabled(LogLevel level) => _logger.isEnabledFor(category, level);

  /// Whether trace records are emitted.
  bool get isTraceEnabled => isEnabled(LogLevel.trace);

  /// Whether debug records are emitted.
  bool get isDebugEnabled => isEnabled(LogLevel.debug);

  /// Emits a trace record.
  void trace(String message, {Map<String, Object?> fields = const {}}) =>
      _logger.trace(category, message, fields: fields);

  /// Emits a debug record.
  void debug(String message, {Map<String, Object?> fields = const {}}) =>
      _logger.debug(category, message, fields: fields);

  /// Emits an info record.
  void info(String message, {Map<String, Object?> fields = const {}}) =>
      _logger.info(category, message, fields: fields);

  /// Emits a warning record.
  void warning(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?> fields = const {}}) =>
      _logger.warning(category, message, error: error, stackTrace: stackTrace, fields: fields);

  /// Emits an error record.
  void error(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?> fields = const {}}) =>
      _logger.error(category, message, error: error, stackTrace: stackTrace, fields: fields);

  /// Emits a critical record.
  void critical(String message, {Object? error, StackTrace? stackTrace, Map<String, Object?> fields = const {}}) =>
      _logger.critical(category, message, error: error, stackTrace: stackTrace, fields: fields);

  @override
  String toString() => 'LogModule(${category.name})';
}
