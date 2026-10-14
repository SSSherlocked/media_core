import 'package:media_core_memory/src/memory_budget.dart';
import 'package:media_core_memory/src/memory_monitor.dart' show MemoryMonitor;
import 'package:media_core_memory/src/memory_pressure.dart';
import 'package:media_core_memory/src/memory_registry.dart';

/// The resource layer's view of memory.
///
/// The resource coordinator needs one number for memory (to fill its metrics and
/// to fold into the combined `ResourcePressure`), and this is what it reads.
///
/// Two ways to feed it, and the choice is the host's:
///
/// - **With a [MemoryRegistry]**: the registry's total is the answer, so the
///   resource layer and the per-module accounting can never disagree. This is
///   what a host that instruments its modules wants.
/// - **Without one**: the manager accumulates whatever the caller reports
///   through [updateUsage]/[addUsage]/[removeUsage]. Enough for a host that has
///   its own accounting, or a test.
///
/// It does not:
///
/// - allocate or release native memory
/// - destroy decoders or players
/// - measure the device ([MemoryMonitor] does)
final class MemoryManager {
  /// Creates a memory manager.
  ///
  /// Passing [registry] makes the registry's total authoritative; passing
  /// [budget] alone uses the manager's own accounting under that budget.
  MemoryManager({MemoryBudget? budget, this.registry}) : _budget = budget ?? registry?.budget ?? const MemoryBudget();

  /// Registry whose total is authoritative, when the host has one.
  final MemoryRegistry? registry;

  MemoryBudget _budget;
  int _memoryBytes = 0;

  /// The budget in force.
  ///
  /// Reads through to the registry when one is attached, so a budget change
  /// made there is what both layers see.
  MemoryBudget get budget => registry?.budget ?? _budget;

  /// Replaces the budget (ignored while a registry is attached: the registry
  /// owns it then).
  set budget(MemoryBudget value) {
    if (registry != null) {
      registry!.budget = value;
      return;
    }
    _budget = value;
  }

  /// Current tracked memory.
  int get memoryBytes => registry?.totalBytes ?? _memoryBytes;

  /// Current memory pressure.
  MemoryPressure get pressure => budget.pressureFor(memoryBytes);

  /// Whether any pressure exists.
  bool get hasPressure => pressure.hasPressure;

  /// Remaining capacity.
  int get remainingBytes => budget.remainingBytes(memoryBytes);

  /// Whether cleanup should start.
  bool get shouldCleanup => pressure.shouldStopPreload;

  /// Whether emergency cleanup is required.
  bool get requiresEmergencyCleanup => pressure.shouldReleaseResources;

  /// Updates the tracked total.
  ///
  /// Ignored while a registry is attached: the registry's accounts are then the
  /// source of truth, and a second writer would make them disagree.
  void updateUsage(int bytes) {
    if (registry != null) {
      return;
    }
    _memoryBytes = bytes < 0 ? 0 : bytes;
  }

  /// Adds to the tracked total.
  void addUsage(int bytes) {
    if (registry != null || bytes <= 0) {
      return;
    }
    _memoryBytes += bytes;
  }

  /// Subtracts from the tracked total.
  void removeUsage(int bytes) {
    if (registry != null || bytes <= 0) {
      return;
    }
    _memoryBytes -= bytes;
    if (_memoryBytes < 0) {
      _memoryBytes = 0;
    }
  }

  /// Whether [additionalBytes] fits.
  bool canAllocate(int additionalBytes) => budget.canAllocate(additionalBytes, memoryBytes);

  /// Immutable view of memory state.
  MemoryUsageSnapshot snapshot() => MemoryUsageSnapshot(memoryBytes: memoryBytes, pressure: pressure);

  /// Resets the manager's own accounting (a no-op with a registry attached).
  void clear() {
    _memoryBytes = 0;
  }

  @override
  String toString() =>
      'MemoryManager(memory=${memoryBytes ~/ 1024 ~/ 1024}MB, pressure=$pressure'
      "${registry == null ? '' : ', registry'})";
}

/// Immutable view of tracked memory.
final class MemoryUsageSnapshot {
  /// Creates a memory usage snapshot.
  const MemoryUsageSnapshot({required this.memoryBytes, required this.pressure});

  /// Tracked memory, in bytes.
  final int memoryBytes;

  /// Pressure level at the time.
  final MemoryPressure pressure;

  /// Whether pressure exists.
  bool get hasPressure => pressure.hasPressure;

  @override
  String toString() => 'MemoryUsageSnapshot(memory=${memoryBytes ~/ 1024 ~/ 1024}MB, pressure=$pressure)';
}
