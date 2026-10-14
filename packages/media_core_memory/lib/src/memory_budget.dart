import 'package:media_core_memory/src/memory_monitor.dart' show MemoryMonitor;
import 'package:media_core_memory/src/memory_pressure.dart';

/// Memory limits, expressed as thresholds on a byte total.
///
/// Responsibilities:
///
/// - define the maximum tracked memory
/// - turn a byte total into a [MemoryPressure]
/// - answer whether an allocation fits
///
/// It does not:
///
/// - allocate or release memory
/// - measure the device (that is [MemoryMonitor])
/// - know which module is holding the memory (that is the registry)
///
/// Threshold semantics:
///
/// ```text
/// 0
/// |
/// |  normal
/// +---------------- warningBytes
/// |
/// |  elevated
/// +---------------- criticalBytes
/// |
/// |  critical
/// +---------------- maxBytes
/// |
/// |  emergency
/// v
/// ```
final class MemoryBudget {
  /// Creates a memory budget.
  ///
  /// [maxBytes] is the tracked ceiling: usage at or above it is
  /// [MemoryPressure.emergency].
  const MemoryBudget({
    this.enabled = true,
    this.maxBytes = 512 * 1024 * 1024,
    this.warningThreshold = 0.70,
    this.criticalThreshold = 0.85,
  }) : assert(maxBytes > 0, 'maxBytes must be positive'),
       assert(warningThreshold >= 0.0, 'warningThreshold must be >= 0.0'),
       assert(warningThreshold <= 1.0, 'warningThreshold must be <= 1.0'),
       assert(criticalThreshold >= 0.0, 'criticalThreshold must be >= 0.0'),
       assert(criticalThreshold <= 1.0, 'criticalThreshold must be <= 1.0'),
       assert(warningThreshold <= criticalThreshold, 'warningThreshold must not exceed criticalThreshold');

  /// Whether budget enforcement is on.
  ///
  /// Off means usage is still tracked and reported, but nothing ever reports
  /// pressure: a host that wants the numbers without the reactions.
  final bool enabled;

  /// Maximum tracked memory, in bytes.
  final int maxBytes;

  /// Usage ratio at which [MemoryPressure.elevated] begins.
  final double warningThreshold;

  /// Usage ratio at which [MemoryPressure.critical] begins.
  final double criticalThreshold;

  /// Absolute amount at which elevated pressure begins.
  int get warningBytes => (maxBytes * warningThreshold).round();

  /// Absolute amount at which critical pressure begins.
  int get criticalBytes => (maxBytes * criticalThreshold).round();

  /// Pressure level for a tracked byte total.
  MemoryPressure pressureFor(int bytes) {
    if (!enabled) {
      return MemoryPressure.normal;
    }
    if (bytes >= maxBytes) {
      return MemoryPressure.emergency;
    }
    if (bytes >= criticalBytes) {
      return MemoryPressure.critical;
    }
    if (bytes >= warningBytes) {
      return MemoryPressure.elevated;
    }
    return MemoryPressure.normal;
  }

  /// Whether [bytes] is at or past the warning threshold.
  bool hasPressure(int bytes) => pressureFor(bytes).hasPressure;

  /// Remaining capacity, never negative.
  int remainingBytes(int bytes) {
    final remaining = maxBytes - bytes;
    return remaining > 0 ? remaining : 0;
  }

  /// Usage ratio, clamped to `0.0..1.0`.
  double usageRatio(int bytes) {
    if (maxBytes <= 0) {
      return 1;
    }
    final ratio = bytes / maxBytes;
    if (ratio <= 0.0) {
      return 0;
    }
    if (ratio >= 1.0) {
      return 1;
    }
    return ratio;
  }

  /// Whether [additionalBytes] fits in the budget given [currentBytes].
  bool canAllocate(int additionalBytes, int currentBytes) {
    if (!enabled || additionalBytes <= 0) {
      return true;
    }
    return currentBytes + additionalBytes <= maxBytes;
  }

  /// Creates a modified budget.
  MemoryBudget copyWith({bool? enabled, int? maxBytes, double? warningThreshold, double? criticalThreshold}) {
    return MemoryBudget(
      enabled: enabled ?? this.enabled,
      maxBytes: maxBytes ?? this.maxBytes,
      warningThreshold: warningThreshold ?? this.warningThreshold,
      criticalThreshold: criticalThreshold ?? this.criticalThreshold,
    );
  }

  @override
  String toString() {
    return 'MemoryBudget('
        'enabled=$enabled, '
        'max=${maxBytes ~/ 1024 ~/ 1024}MB, '
        'warning=${(warningThreshold * 100).round()}%, '
        'critical=${(criticalThreshold * 100).round()}%'
        ')';
  }
}
