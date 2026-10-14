import 'package:equatable/equatable.dart';
import 'package:media_core_logging/media_core_logging.dart' show MediaCoreLog, PlayerLogger;

/// Defines the severity of a diagnostic log record.
///
/// A [LogLevel] is used by [PlayerLogger] to determine whether a log record
/// should be emitted.
///
/// Responsibilities:
///
/// - define the supported log severities
/// - provide ordering between severities
/// - provide common severity checks
///
/// It does not:
///
/// - write log records
/// - filter logs by category
/// - manage diagnostic configuration
///
/// Those responsibilities belong to:
///
/// - PlayerLogger
/// - DiagnosticsConfig
enum LogLevel {
  /// Extremely detailed diagnostic information.
  trace,

  /// Development-oriented diagnostic information.
  debug,

  /// Normal informational message.
  info,

  /// Potentially abnormal condition that does not stop processing.
  warning,

  /// An error occurred during processing.
  error,

  /// A critical error that may prevent normal operation.
  critical,

  /// Logging is disabled. The default for production: an application that
  /// never configures [MediaCoreLog] stays silent.
  nothing,
}

/// Provides common operations for [LogLevel].
extension LogLevelX on LogLevel {
  /// Numeric ordering used to compare log severities.
  int get weight {
    switch (this) {
      case LogLevel.trace:
        return 0;
      case LogLevel.debug:
        return 1;
      case LogLevel.info:
        return 2;
      case LogLevel.warning:
        return 3;
      case LogLevel.error:
        return 4;
      case LogLevel.critical:
        return 5;
      case LogLevel.nothing:
        return 6;
    }
  }

  /// Whether this level is at least as severe as [minimum].
  bool isAtLeast(LogLevel minimum) {
    return weight >= minimum.weight;
  }

  /// Whether this level represents an error condition.
  bool get isError {
    return this == LogLevel.error || this == LogLevel.critical;
  }

  /// Stable string representation used by diagnostic serialization.
  String get name {
    return switch (this) {
      LogLevel.trace => 'trace',
      LogLevel.debug => 'debug',
      LogLevel.info => 'info',
      LogLevel.warning => 'warning',
      LogLevel.error => 'error',
      LogLevel.critical => 'critical',
      LogLevel.nothing => 'nothing',
    };
  }
}

/// Immutable value object representing a [LogLevel].
///
/// This wrapper is useful when a log level needs value semantics in another
/// immutable model without exposing mutable configuration state.
final class LogLevelValue extends Equatable {
  /// Creates a log level value.
  const LogLevelValue(this.level);

  /// Wrapped log level.
  final LogLevel level;

  /// Whether this level is at least as severe as [minimum].
  bool isAtLeast(LogLevel minimum) {
    return level.isAtLeast(minimum);
  }

  @override
  List<Object?> get props => [level];

  @override
  String toString() {
    return level.name;
  }
}
