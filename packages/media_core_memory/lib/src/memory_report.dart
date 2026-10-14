import 'package:media_core_memory/src/memory_account.dart';
import 'package:media_core_memory/src/memory_budget.dart';
import 'package:media_core_memory/src/memory_estimates.dart';
import 'package:media_core_memory/src/memory_module.dart';
import 'package:media_core_memory/src/memory_pressure.dart';
import 'package:media_core_memory/src/memory_snapshot.dart';

/// One moment of memory accounting across every module.
///
/// This is what a diagnostics screen or a bug report reads: the declared
/// breakdown, plus the device measurement when one was available.
final class MemoryReport {
  /// Creates a report.
  const MemoryReport({
    required this.at,
    required this.accounts,
    required this.totalBytes,
    required this.totalItems,
    required this.pressure,
    required this.budget,
    this.device,
  });

  /// When the report was built.
  final DateTime at;

  /// Per-module ledgers, largest first.
  final List<MemoryAccountSnapshot> accounts;

  /// Sum of every module's reported bytes.
  final int totalBytes;

  /// Sum of every module's reported items.
  final int totalItems;

  /// Global pressure, from [totalBytes] against [budget].
  final MemoryPressure pressure;

  /// The budget this report was judged against.
  final MemoryBudget budget;

  /// Latest device measurement, when a monitor had one.
  ///
  /// Declared (this report) and measured (device) are different numbers on
  /// purpose: the first says who is holding memory, the second says how much
  /// the process is using in total.
  final MemorySnapshot? device;

  /// Modules that currently hold something, largest first.
  List<MemoryAccountSnapshot> get holders => accounts.where((account) => !account.isEmpty).toList(growable: false);

  /// The module holding the most, or `null` when nothing is reported.
  MemoryAccountSnapshot? get largest {
    for (final account in accounts) {
      if (!account.isEmpty) {
        return account;
      }
    }
    return null;
  }

  /// The ledger of [module], or `null` when it never reported.
  MemoryAccountSnapshot? forModule(MemoryModule module) {
    for (final account in accounts) {
      if (account.module == module) {
        return account;
      }
    }
    return null;
  }

  /// [module]'s share of the reported total, in `0.0..1.0`.
  double shareOf(MemoryModule module) {
    if (totalBytes <= 0) {
      return 0;
    }
    return (forModule(module)?.bytes ?? 0) / totalBytes;
  }

  /// Fraction of the budget in use, in `0.0..1.0`.
  double get budgetUsage => budget.usageRatio(totalBytes);

  /// Remaining budget, never negative.
  int get remainingBytes => budget.remainingBytes(totalBytes);

  /// One line per module, largest first, for logs and diagnostics screens.
  String describe({bool includeEmpty = false}) {
    final buffer = StringBuffer()
      ..write('${MemoryEstimates.formatBytes(totalBytes)} tracked')
      ..write(' / ${MemoryEstimates.formatBytes(budget.maxBytes)} budget')
      ..write(' [${pressure.label}]');

    final device = this.device;
    if (device != null) {
      final ratio = device.usageRatio;
      buffer.write(
        ' | device ${MemoryEstimates.formatBytes(device.usedBytes)} used'
        '${ratio == null ? '' : ' (${(ratio * 100).toStringAsFixed(0)}%)'}',
      );
    }

    for (final account in accounts) {
      if (!includeEmpty && account.isEmpty) {
        continue;
      }
      buffer
        ..write('\n  ${account.module.name}: ${MemoryEstimates.formatBytes(account.bytes)}')
        ..write(' in ${account.items} item(s)');
      if (account.contributorCount > 1) {
        buffer.write(' from ${account.contributorCount} instances');
      }
      if (account.hasReported && account.peakBytes > account.bytes) {
        buffer.write(', peak ${MemoryEstimates.formatBytes(account.peakBytes)}');
      }
      if (account.isOverLimit) {
        buffer.write(' OVER LIMIT');
      }
      final note = account.note;
      if (note != null) {
        buffer.write(' — $note');
      }
    }

    return buffer.toString();
  }

  /// Serializes this report.
  Map<String, Object?> toMap() {
    return {
      'at': at.toIso8601String(),
      'totalBytes': totalBytes,
      'totalItems': totalItems,
      'pressure': pressure.label,
      'budgetBytes': budget.maxBytes,
      'accounts': <Map<String, Object?>>[
        for (final account in accounts)
          {
            'module': account.module.name,
            'bytes': account.bytes,
            'items': account.items,
            'peakBytes': account.peakBytes,
            if (account.note != null) 'note': account.note,
          },
      ],
      if (device != null) 'device': device!.toMap(),
    };
  }

  @override
  String toString() => 'MemoryReport(${describe()})';
}
