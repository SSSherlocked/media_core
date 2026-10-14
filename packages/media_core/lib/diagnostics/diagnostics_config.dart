import 'package:equatable/equatable.dart';
import 'package:media_core_logging/media_core_logging.dart';

/// Defines configuration for the diagnostics subsystem.
///
/// A [DiagnosticsConfig] controls which diagnostic capabilities are enabled
/// and how much diagnostic data is retained.
///
/// Responsibilities:
///
/// - enable or disable diagnostics
/// - configure log filtering
/// - configure performance sample retention
/// - configure periodic monitoring behavior
/// - provide immutable diagnostic configuration
///
/// It does not:
///
/// - collect diagnostic measurements
/// - emit log records
/// - schedule monitoring work
/// - own diagnostic monitor instances
///
/// Those responsibilities belong to:
///
/// - DiagnosticsManager
/// - PlayerLogger
/// - PerformanceMonitor
/// - MemoryMonitor
/// - NetworkMonitor
final class DiagnosticsConfig extends Equatable {
  /// Creates diagnostic configuration.
  const DiagnosticsConfig({
    this.enabled = true,
    this.loggingEnabled = true,
    this.performanceMonitoringEnabled = true,
    this.memoryMonitoringEnabled = true,
    this.networkMonitoringEnabled = true,
    this.minimumLogLevel = LogLevel.info,
    this.maxPerformanceSamples = 200,
    this.monitoringInterval = const Duration(seconds: 5),
  }) : assert(maxPerformanceSamples > 0, 'maxPerformanceSamples must be positive'),
       assert(monitoringInterval > Duration.zero, 'monitoringInterval must be positive');

  /// Whether the diagnostics subsystem is enabled.
  final bool enabled;

  /// Whether diagnostic logging is enabled.
  final bool loggingEnabled;

  /// Whether performance monitoring is enabled.
  final bool performanceMonitoringEnabled;

  /// Whether memory monitoring is enabled.
  final bool memoryMonitoringEnabled;

  /// Whether network monitoring is enabled.
  final bool networkMonitoringEnabled;

  /// Minimum severity level emitted by the diagnostic logger.
  final LogLevel minimumLogLevel;

  /// Maximum number of performance samples retained by the monitor.
  final int maxPerformanceSamples;

  /// Default interval between periodic diagnostic measurements.
  final Duration monitoringInterval;

  /// Creates a copy with selected configuration values replaced.
  DiagnosticsConfig copyWith({
    bool? enabled,
    bool? loggingEnabled,
    bool? performanceMonitoringEnabled,
    bool? memoryMonitoringEnabled,
    bool? networkMonitoringEnabled,
    LogLevel? minimumLogLevel,
    int? maxPerformanceSamples,
    Duration? monitoringInterval,
  }) {
    return DiagnosticsConfig(
      enabled: enabled ?? this.enabled,
      loggingEnabled: loggingEnabled ?? this.loggingEnabled,
      performanceMonitoringEnabled: performanceMonitoringEnabled ?? this.performanceMonitoringEnabled,
      memoryMonitoringEnabled: memoryMonitoringEnabled ?? this.memoryMonitoringEnabled,
      networkMonitoringEnabled: networkMonitoringEnabled ?? this.networkMonitoringEnabled,
      minimumLogLevel: minimumLogLevel ?? this.minimumLogLevel,
      maxPerformanceSamples: maxPerformanceSamples ?? this.maxPerformanceSamples,
      monitoringInterval: monitoringInterval ?? this.monitoringInterval,
    );
  }

  @override
  List<Object?> get props => [
    enabled,
    loggingEnabled,
    performanceMonitoringEnabled,
    memoryMonitoringEnabled,
    networkMonitoringEnabled,
    minimumLogLevel,
    maxPerformanceSamples,
    monitoringInterval,
  ];

  @override
  String toString() {
    return 'DiagnosticsConfig('
        'enabled: $enabled, '
        'loggingEnabled: $loggingEnabled, '
        'performanceMonitoringEnabled: $performanceMonitoringEnabled, '
        'memoryMonitoringEnabled: $memoryMonitoringEnabled, '
        'networkMonitoringEnabled: $networkMonitoringEnabled, '
        'minimumLogLevel: $minimumLogLevel, '
        'maxPerformanceSamples: $maxPerformanceSamples, '
        'monitoringInterval: $monitoringInterval'
        ')';
  }
}
