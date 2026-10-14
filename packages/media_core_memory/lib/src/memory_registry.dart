import 'dart:async';
import 'package:media_core_logging/media_core_logging.dart';

import 'package:media_core_memory/src/memory_account.dart';
import 'package:media_core_memory/src/memory_budget.dart';
import 'package:media_core_memory/src/memory_estimates.dart';
import 'package:media_core_memory/src/memory_module.dart';
import 'package:media_core_memory/src/memory_monitor.dart' show MemoryMonitor;
import 'package:media_core_memory/src/memory_pressure.dart';
import 'package:media_core_memory/src/memory_report.dart';
import 'package:media_core_memory/src/memory_snapshot.dart';

/// Decision trail for memory.
final LogModule _log = MediaCoreLog.of(LogCategory.memory);

/// The ledger for every module's reported memory.
///
/// Responsibilities:
///
/// - hand out one [MemoryAccount] per module
/// - total the accounts and judge the total against a [MemoryBudget]
/// - build [MemoryReport]s, and publish them
/// - log pressure transitions
///
/// It does not:
///
/// - measure device memory ([MemoryMonitor] does)
/// - release anything: pressure is a signal, and each module decides what to do
///   with it
final class MemoryRegistry {
  /// Creates a registry.
  MemoryRegistry({MemoryBudget budget = const MemoryBudget(), DateTime Function()? clock})
    : _budget = budget,
      _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  MemoryBudget _budget;
  final Map<String, MemoryAccount> _accounts = <String, MemoryAccount>{};
  final StreamController<MemoryReport> _reports = StreamController<MemoryReport>.broadcast();

  MemoryPressure _lastPressure = MemoryPressure.normal;
  MemoryReport? _lastReport;
  bool _disposed = false;

  /// The budget accounts are judged against.
  MemoryBudget get budget => _budget;

  /// Replaces the budget and re-evaluates pressure.
  ///
  /// A budget change is a policy change, not a new measurement: pressure is
  /// recomputed from what is already reported, so a host that tightens the
  /// budget gets the reaction immediately rather than at the next update.
  set budget(MemoryBudget value) {
    _ensureNotDisposed();
    _budget = value;
    _evaluatePressure();
  }

  /// Every ledger, whether or not it has been reported to.
  List<MemoryAccount> get accounts => List<MemoryAccount>.unmodifiable(_accounts.values);

  /// Sum of every module's reported bytes.
  int get totalBytes {
    var total = 0;
    for (final account in _accounts.values) {
      total += account.bytes;
    }
    return total;
  }

  /// Sum of every module's reported items.
  int get totalItems {
    var total = 0;
    for (final account in _accounts.values) {
      total += account.items;
    }
    return total;
  }

  /// Current pressure, from the total against the budget.
  MemoryPressure get pressure => _budget.pressureFor(totalBytes);

  /// Remaining budget.
  int get remainingBytes => _budget.remainingBytes(totalBytes);

  /// The most recent report, or `null` before the first [report] call.
  MemoryReport? get lastReport => _lastReport;

  /// Reports as they are built.
  Stream<MemoryReport> get onReport => _reports.stream;

  /// The ledger of [module], created on first use.
  ///
  /// Creating on demand is what keeps instrumentation cheap: a module calls
  /// this once at construction and reports only when it actually holds
  /// something.
  MemoryAccount accountFor(MemoryModule module, {int? limitBytes}) {
    _ensureNotDisposed();

    final existing = _accounts[module.name];
    if (existing != null) {
      if (limitBytes != null) {
        existing.limitBytes = limitBytes;
      }
      return existing;
    }

    final account = MemoryAccount(module: module, limitBytes: limitBytes);
    _accounts[module.name] = account;
    return account;
  }

  /// The ledger of [module] if it was ever requested.
  MemoryAccount? account(MemoryModule module) => _accounts[module.name];

  /// Whether [bytes] fits in the remaining budget.
  bool canAllocate(int bytes) => _budget.canAllocate(bytes, totalBytes);

  /// Builds a report from the current ledgers.
  ///
  /// [device] is attached when the caller has a device measurement; the report
  /// carries both because they answer different questions.
  MemoryReport report({MemorySnapshot? device}) {
    _ensureNotDisposed();

    final pressure = _budget.pressureFor(totalBytes);

    final snapshots =
        <MemoryAccountSnapshot>[for (final account in _accounts.values) account.snapshot(pressure: pressure)]
          ..sort((a, b) {
            final byBytes = b.bytes.compareTo(a.bytes);
            return byBytes != 0 ? byBytes : a.module.name.compareTo(b.module.name);
          });

    final report = MemoryReport(
      at: _clock(),
      accounts: List<MemoryAccountSnapshot>.unmodifiable(snapshots),
      totalBytes: totalBytes,
      totalItems: totalItems,
      pressure: pressure,
      budget: _budget,
      device: device,
    );

    _lastReport = report;

    if (!_reports.isClosed) {
      _reports.add(report);
    }

    _logReport(report);

    return report;
  }

  /// Forgets one module's ledger.
  ///
  /// For a module that is being torn down: its account would otherwise keep
  /// reporting whatever it held at the moment it died.
  void remove(MemoryModule module) {
    _ensureNotDisposed();
    _accounts.remove(module.name);
  }

  /// Empties every ledger, keeping the accounts themselves.
  void clear() {
    _ensureNotDisposed();
    for (final account in _accounts.values) {
      account.clear();
    }
  }

  /// Empties every ledger and forgets the peaks.
  void reset() {
    _ensureNotDisposed();
    for (final account in _accounts.values) {
      account.reset();
    }
    _lastPressure = MemoryPressure.normal;
    _lastReport = null;
  }

  /// Disposes the registry.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _accounts.clear();
    _lastReport = null;
    await _reports.close();
  }

  /// Logs a pressure change when the level moved, and the breakdown at debug.
  ///
  /// The transition is logged rather than every report: a pressure level that
  /// changed is the event a developer is looking for, and the breakdown per
  /// event is what says which module caused it.
  void _logReport(MemoryReport report) {
    final pressure = report.pressure;
    if (pressure != _lastPressure) {
      final rising = pressure.isHigherThan(_lastPressure);
      final fields = <String, Object?>{
        'from': _lastPressure.label,
        'to': pressure.label,
        'totalBytes': report.totalBytes,
        'budgetBytes': report.budget.maxBytes,
        'largest': report.largest?.module.name,
      };
      if (rising && pressure.hasPressure) {
        if (pressure.shouldReleaseResources) {
          _log.error('memory budget exceeded; modules must release', fields: fields);
        } else {
          _log.warning('memory pressure rising', fields: fields);
        }
      } else {
        _log.info('memory pressure released', fields: fields);
      }
      _lastPressure = pressure;
    }

    if (!_log.isDebugEnabled) {
      return;
    }

    _log.debug(
      'memory report',
      fields: <String, Object?>{
        'totalBytes': report.totalBytes,
        'items': report.totalItems,
        'holders': report.holders.length,
        'breakdown': report.holders
            .take(6)
            .map((account) => '${account.module.name}=${MemoryEstimates.formatBytes(account.bytes)}')
            .join(' '),
      },
    );
  }

  /// Re-evaluates pressure without building a full report.
  void _evaluatePressure() {
    final pressure = this.pressure;
    if (pressure == _lastPressure) {
      return;
    }
    _logReport(report());
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('MemoryRegistry has been disposed.');
    }
  }

  @override
  String toString() =>
      'MemoryRegistry(modules=${_accounts.length}, '
      'total=${MemoryEstimates.formatBytes(totalBytes)}, pressure=$pressure)';
}
