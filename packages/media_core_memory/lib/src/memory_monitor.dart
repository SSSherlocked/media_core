import 'dart:async';

import 'package:media_core_memory/src/memory_snapshot.dart';

/// Produces a device memory measurement.
typedef MemorySnapshotProvider = MemorySnapshot Function();

/// Monitors device memory over time.
///
/// Responsibilities:
///
/// - take measurements from a platform provider, or record caller-supplied ones
/// - keep the latest measurement
/// - keep a bounded history, so a leak reads as a trend rather than a number
/// - publish measurements to listeners
///
/// It does not:
///
/// - implement a platform memory API (the provider does)
/// - schedule sampling on its own (the host decides when to ask)
/// - attribute memory to modules (the registry does)
final class MemoryMonitor {
  /// Creates a memory monitor.
  MemoryMonitor({MemorySnapshotProvider? provider, this.historyCapacity = 60, DateTime Function()? clock})
    : _provider = provider,
      _clock = clock ?? DateTime.now;

  /// Optional platform-specific measurement provider.
  MemorySnapshotProvider? _provider;

  final DateTime Function() _clock;

  /// How many measurements are retained for the trend.
  final int historyCapacity;

  final List<MemorySnapshot> _history = <MemorySnapshot>[];
  final StreamController<MemorySnapshot> _samples = StreamController<MemorySnapshot>.broadcast();

  MemorySnapshot? _last;
  bool _disposed = false;

  /// Latest measurement, or `null` before the first one.
  MemorySnapshot? get snapshot => _last;

  /// Retained measurements, oldest first.
  List<MemorySnapshot> get history => List<MemorySnapshot>.unmodifiable(_history);

  /// Measurements as they are taken.
  Stream<MemorySnapshot> get onSampled => _samples.stream;

  /// Whether a provider is installed, i.e. whether [sample] can produce anything.
  bool get hasProvider => _provider != null;

  /// Replaces the measurement provider.
  ///
  /// Passing `null` disables provider-based sampling.
  void setProvider(MemorySnapshotProvider? provider) {
    _ensureNotDisposed();
    _provider = provider;
  }

  /// Takes a measurement from the provider.
  ///
  /// Returns `null` when no provider is installed. A provider that throws is
  /// treated the same way: a diagnostics path must not be able to fail the
  /// playback it is observing.
  MemorySnapshot? sample() {
    _ensureNotDisposed();

    final provider = _provider;
    if (provider == null) {
      return null;
    }

    try {
      return record(provider());
    } on Object catch (_) {
      return null;
    }
  }

  /// Records a measurement supplied by the caller or a provider.
  ///
  /// The timestamp is stamped here, so a provider does not have to care about
  /// time and tests can drive it deterministically.
  MemorySnapshot record(MemorySnapshot snapshot) {
    _ensureNotDisposed();

    final stamped = snapshot.copyWith(timestamp: _clock());
    _last = stamped;

    _history.add(stamped);
    while (_history.length > historyCapacity) {
      _history.removeAt(0);
    }

    if (!_samples.isClosed) {
      _samples.add(stamped);
    }

    return stamped;
  }

  /// Records a measurement by value.
  MemorySnapshot recordValues({required int usedBytes, required int availableBytes, int externalBytes = 0}) {
    return record(
      MemorySnapshot(
        timestamp: _clock(),
        usedBytes: usedBytes,
        availableBytes: availableBytes,
        externalBytes: externalBytes,
      ),
    );
  }

  /// Forgets the latest measurement and the history.
  void clear() {
    _ensureNotDisposed();
    _last = null;
    _history.clear();
  }

  /// Disposes the monitor.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _provider = null;
    _last = null;
    _history.clear();
    await _samples.close();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('MemoryMonitor has been disposed.');
    }
  }

  @override
  String toString() => 'MemoryMonitor(samples=${_history.length}/$historyCapacity, hasProvider=$hasProvider)';
}
