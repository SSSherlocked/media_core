import 'dart:async';

import 'package:clock/clock.dart';
import 'package:media_core/policy/resource_policy.dart';
import 'package:media_core/resource/bandwidth_manager.dart';
import 'package:media_core/resource/decoder_manager.dart';
import 'package:media_core/resource/memory_pressure_bridge.dart';
import 'package:media_core/resource/resource_metrics.dart';
import 'package:media_core/resource/resource_pressure.dart';
import 'package:media_core/resource/resource_snapshot.dart';
import 'package:media_core/resource/resource_state.dart';
import 'package:media_core/resource/thermal_manager.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// Coordinates runtime resource management.
///
/// [ResourceManager] is the top-level coordinator
/// of the media core resource subsystem.
///
/// It aggregates resource information from:
///
/// - DecoderManager
/// - MemoryManager
/// - BandwidthManager
/// - ThermalManager
///
/// Responsibilities:
///
/// - maintain global resource state
/// - evaluate resource pressure
/// - publish resource snapshots
/// - coordinate resource policies
/// - enter degraded mode
///
/// It does not:
///
/// - allocate decoders
/// - allocate memory
/// - read hardware sensors
/// - release platform resources directly
/// - control playback
///
/// Those responsibilities belong to:
///
/// - DecoderManager
/// - MemoryManager
/// - BandwidthManager
/// - ThermalManager
///
/// Architecture:
///
/// ```text
///
///                ResourcePolicy
///                      |
///                      v
///
/// +--------------------+--------------------+
/// |                    |                    |
/// v                    v                    v
///
/// DecoderManager   MemoryManager   BandwidthManager
///
///                      |
///                      v
///
///               ThermalManager
///
///                      |
///                      v
///
///              ResourceManager
///
///                      |
///                      v
///
///              ResourceSnapshot
///
/// ```
final class ResourceManager {
  /// Creates resource manager.
  ///
  /// All sub managers are injected.
  /// ResourceManager does not own their creation.
  ResourceManager({
    required this.policy,

    required this.decoderManager,

    required this.memoryManager,

    required this.bandwidthManager,

    required this.thermalManager,
  });

  /// Resource policy.
  final ResourcePolicy policy;

  /// Decoder resource manager.
  final DecoderManager decoderManager;

  /// Memory resource manager.
  final MemoryManager memoryManager;

  /// Bandwidth resource manager.
  final BandwidthManager bandwidthManager;

  /// Thermal resource manager.
  final ThermalManager thermalManager;

  /// Current resource state.
  ResourceState _state = ResourceState.initial;

  /// Snapshot controller.
  final StreamController<ResourceSnapshot> _controller = StreamController<ResourceSnapshot>.broadcast();

  /// Current resource state.
  ResourceState get state {
    return _state;
  }

  /// Current resource snapshot.
  ResourceSnapshot get snapshot {
    return ResourceSnapshot.fromState(_state);
  }

  /// Resource snapshot stream.
  Stream<ResourceSnapshot> get snapshots {
    return _controller.stream;
  }

  /// Whether resource management is enabled.
  bool get enabled {
    return policy.enabled;
  }

  /// Initializes resource manager.
  ///
  /// Does not allocate resources.
  Future<void> initialize() async {
    _publish();
  }

  /// Updates resource state.
  ///
  /// This only collects current information.
  void update() {
    if (!enabled) {
      return;
    }

    final metrics = _collectMetrics();

    final pressure = _calculatePressure();

    _state = _state.copyWith(
      metrics: metrics,

      pressure: pressure,

      degraded: pressure.shouldReduceQuality,

      timestamp: clock.now(),
    );

    _publish();
  }

  /// Collects current resource metrics.
  ResourceMetrics _collectMetrics() {
    return ResourceMetrics(
      decoderCount: decoderManager.decoderCount,

      hardwareDecoderCount: decoderManager.hardwareDecoderCount,

      memoryBytes: memoryManager.memoryBytes,

      bandwidthMbps: bandwidthManager.currentMbps,

      thermalState: thermalManager.state.label,

      timestamp: clock.now(),
    );
  }

  /// Calculates global resource pressure.
  ///
  /// The highest pressure level wins.
  ResourcePressure _calculatePressure() {
    var result = ResourcePressure.none;

    result = ResourcePressure.max(result, decoderManager.pressure);

    result = ResourcePressure.max(result, memoryManager.resourcePressure);

    result = ResourcePressure.max(result, bandwidthManager.pressure);

    result = ResourcePressure.max(result, thermalManager.pressure);

    return result;
  }

  /// Enters resource release state.
  ///
  /// Actual resource cleanup is delegated
  /// to resource owners.
  Future<void> release() async {
    _state = _state.startRelease();

    _publish();

    //
    // ResourceManager does not directly
    // destroy resources.
    //
    // Child managers decide how to
    // cleanup their own state.
    //

    decoderManager.clear();

    memoryManager.clear();

    _state = _state.finishRelease();

    _publish();
  }

  /// Enables degraded mode.
  ///
  /// Degraded mode allows upper layers
  /// to reduce resource consumption.
  void enterDegradedMode() {
    _state = _state.enableDegradedMode();

    _publish();
  }

  /// Leaves degraded mode.
  void leaveDegradedMode() {
    _state = _state.disableDegradedMode();

    _publish();
  }

  /// Resets resource state.
  void reset() {
    _state = ResourceState.initial;

    _publish();
  }

  /// Publishes resource snapshot.
  void _publish() {
    if (!_controller.isClosed) {
      _controller.add(snapshot);
    }
  }

  /// Disposes manager.
  ///
  /// Sub managers are not disposed here.
  ///
  /// Their lifecycle belongs to creator.
  Future<void> dispose() async {
    await _controller.close();
  }
}
