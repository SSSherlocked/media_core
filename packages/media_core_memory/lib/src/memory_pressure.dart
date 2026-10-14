/// How close tracked memory is to its budget.
///
/// The framework's resource layer has `ResourcePressure` (memory + bandwidth +
/// thermal + decoders, resolved into one level). This is the memory-only view,
/// and it exists because the memory subsystem must not depend on the resource
/// subsystem that consumes it: the resource layer maps this onto its own type,
/// not the other way round.
enum MemoryPressure {
  /// Comfortably inside the budget.
  normal,

  /// Past the warning threshold: stop growing.
  elevated,

  /// Past the critical threshold: start releasing.
  critical,

  /// Over budget: release now, and refuse new allocations.
  emergency;

  /// Human-readable label.
  String get label => switch (this) {
    MemoryPressure.normal => 'normal',
    MemoryPressure.elevated => 'elevated',
    MemoryPressure.critical => 'critical',
    MemoryPressure.emergency => 'emergency',
  };

  /// Whether any pressure exists.
  bool get hasPressure => this != MemoryPressure.normal;

  /// Whether optional work (preload, warm players, prefetch) should stop.
  bool get shouldStopPreload => this == MemoryPressure.critical || this == MemoryPressure.emergency;

  /// Whether held resources should be released.
  bool get shouldReleaseResources => this == MemoryPressure.emergency;

  /// Whether new allocations should be refused.
  ///
  /// Same threshold as [shouldReleaseResources]: once the budget is exceeded,
  /// accepting more work is what turns one over-budget moment into an OOM.
  bool get shouldRefuseAllocation => this == MemoryPressure.emergency;

  /// Ordering weight; higher is more severe.
  int get priority => switch (this) {
    MemoryPressure.normal => 0,
    MemoryPressure.elevated => 1,
    MemoryPressure.critical => 2,
    MemoryPressure.emergency => 3,
  };

  /// Whether this level is more severe than [other].
  bool isHigherThan(MemoryPressure other) => priority > other.priority;

  /// The more severe of two levels.
  static MemoryPressure max(MemoryPressure a, MemoryPressure b) => a.priority >= b.priority ? a : b;

  @override
  String toString() => label;
}
