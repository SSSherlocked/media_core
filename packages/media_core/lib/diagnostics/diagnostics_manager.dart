import 'package:media_core/diagnostics/network_diagnostics.dart';
import 'package:media_core/diagnostics/performance_monitor.dart';
import 'package:media_core/diagnostics/player_debug_snapshot.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// Coordinates the diagnostic monitors owned by the media core.
///
/// A [DiagnosticsManager] provides one entry point for collecting the current
/// diagnostic state of the player. It owns the individual monitoring
/// components but does not implement their measurement logic.
///
/// Responsibilities:
///
/// - own performance diagnostics
/// - own memory diagnostics
/// - own network diagnostics
/// - collect a combined player debug snapshot
/// - manage the lifetime of diagnostic monitors
///
/// It does not:
///
/// - perform platform-specific measurements
/// - decide application-specific diagnostic policy
/// - write diagnostic data to persistent storage
/// - implement logging
///
/// Those responsibilities belong to:
///
/// - PerformanceMonitor
/// - MemoryMonitor
/// - NetworkDiagnostics
/// - PlayerLogger
/// - DiagnosticsConfig
final class DiagnosticsManager {
  /// Creates a diagnostics manager.
  DiagnosticsManager({PerformanceMonitor? performance, MemoryMonitor? memory, NetworkDiagnostics? network})
    : performance = performance ?? PerformanceMonitor(),
      memory = memory ?? MemoryMonitor(),
      network = network ?? NetworkDiagnostics();

  /// Performance diagnostics monitor.
  final PerformanceMonitor performance;

  /// Memory diagnostics monitor.
  final MemoryMonitor memory;

  /// Network diagnostics monitor.
  final NetworkDiagnostics network;

  /// Whether this manager has been disposed.
  bool _disposed = false;

  /// Whether diagnostics are currently available.
  bool get isDisposed {
    return _disposed;
  }

  /// Captures the current diagnostic state of the player.
  ///
  /// The snapshot contains the latest memory and network measurements together
  /// with the currently retained performance samples.
  PlayerDebugSnapshot snapshot({Map<String, Object?> values = const {}}) {
    _ensureNotDisposed();

    return PlayerDebugSnapshot(
      timestamp: DateTime.now(),
      memory: memory.snapshot,
      network: network.snapshot,
      performanceSamples: performance.samples,
      values: values,
    );
  }

  /// Clears retained diagnostic measurements.
  ///
  /// The current memory and network monitors are reset while their monitor
  /// instances remain available for subsequent measurements.
  void clear() {
    _ensureNotDisposed();

    performance.clear();
    memory.clear();
    network.reset();
  }

  /// Disposes all diagnostic monitors.
  ///
  /// After disposal, the manager cannot be used again.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    performance.dispose();
    await memory.dispose();
    network.dispose();
  }

  /// Ensures the manager has not been disposed.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('DiagnosticsManager has been disposed.');
    }
  }
}
