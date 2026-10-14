import 'package:equatable/equatable.dart';
import 'package:media_core/resource/resource_metrics.dart';
import 'package:media_core/resource/resource_pressure.dart';

/// Represents current resource runtime state.
///
/// [ResourceState] is the central immutable state
/// model of the resource subsystem.
///
/// It aggregates:
///
/// - memory state
/// - decoder state
/// - bandwidth state
/// - thermal state
/// - pressure state
///
/// It is used by:
///
/// - ResourceManager
/// - PlayerCoordinator
/// - PreloadManager
/// - PerformanceMonitor
///
/// It does not:
///
/// - collect hardware information
/// - release resources
/// - allocate resources
/// - control players
///
/// Those responsibilities belong to:
///
/// - MemoryManager
/// - DecoderManager
/// - BandwidthManager
/// - ThermalManager
///
/// State flow:
///
/// ```text
/// MemoryManager
///       |
/// DecoderManager
///       |
/// BandwidthManager
///       |
/// ThermalManager
///       |
///       v
/// ResourceState
///       |
///       v
/// ResourceManager
/// ```
final class ResourceState extends Equatable {
  /// Creates resource state.
  const ResourceState({
    this.metrics = ResourceMetrics.empty,

    this.pressure = ResourcePressure.none,

    this.enabled = true,

    this.releasing = false,

    this.degraded = false,

    this.timestamp,
  });

  /// Current resource metrics.
  final ResourceMetrics metrics;

  /// Current resource pressure.
  final ResourcePressure pressure;

  /// Whether resource management is enabled.
  final bool enabled;

  /// Whether resources are currently being released.
  final bool releasing;

  /// Whether the system is running in degraded mode.
  ///
  /// Degraded mode may include:
  ///
  /// - lower quality stream
  /// - disabled preload
  /// - reduced decoder usage
  final bool degraded;

  /// State update timestamp.
  final DateTime? timestamp;

  /// Whether any resource pressure exists.
  bool get hasPressure {
    return pressure.hasPressure;
  }

  /// Whether emergency handling is required.
  bool get isEmergency {
    return pressure == ResourcePressure.emergency;
  }

  /// Whether cleanup should start.
  bool get shouldRelease {
    return pressure.shouldReleaseResources;
  }

  /// Whether preload should stop.
  bool get shouldStopPreload {
    return pressure.shouldStopPreload;
  }

  /// Whether quality reduction is recommended.
  bool get shouldReduceQuality {
    return pressure.shouldReduceQuality;
  }

  /// Whether resource layer is idle.
  bool get isIdle {
    return !releasing && !degraded && pressure == ResourcePressure.none;
  }

  /// Creates a modified state.
  ResourceState copyWith({
    ResourceMetrics? metrics,

    ResourcePressure? pressure,

    bool? enabled,

    bool? releasing,

    bool? degraded,

    DateTime? timestamp,
  }) {
    return ResourceState(
      metrics: metrics ?? this.metrics,

      pressure: pressure ?? this.pressure,

      enabled: enabled ?? this.enabled,

      releasing: releasing ?? this.releasing,

      degraded: degraded ?? this.degraded,

      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Creates state when resource pressure occurs.
  ResourceState withPressure(ResourcePressure value) {
    return copyWith(pressure: value, degraded: value.shouldReduceQuality);
  }

  /// Creates state while releasing resources.
  ResourceState startRelease() {
    return copyWith(releasing: true);
  }

  /// Creates state after releasing resources.
  ResourceState finishRelease() {
    return copyWith(releasing: false);
  }

  /// Creates degraded mode state.
  ResourceState enableDegradedMode() {
    return copyWith(degraded: true);
  }

  /// Creates normal mode state.
  ResourceState disableDegradedMode() {
    return copyWith(degraded: false);
  }

  /// Returns default state.
  static const ResourceState initial = ResourceState();

  @override
  List<Object?> get props => [metrics, pressure, enabled, releasing, degraded, timestamp];

  @override
  String toString() {
    return 'ResourceState('
        'pressure=$pressure, '
        'releasing=$releasing, '
        'degraded=$degraded, '
        'metrics=$metrics'
        ')';
  }
}
