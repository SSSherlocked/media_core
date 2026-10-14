import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_logging/media_core_logging.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// A device provider with a settable measurement.
final class _FakeDevice {
  int usedBytes = 0;
  int availableBytes = 0;
  int externalBytes = 0;
  bool throws = false;

  MemorySnapshot call() {
    if (throws) {
      throw StateError('provider failed');
    }
    return MemorySnapshot(
      timestamp: DateTime(2026, 9, 26),
      usedBytes: usedBytes,
      availableBytes: availableBytes,
      externalBytes: externalBytes,
    );
  }
}

void main() {
  group('MemoryBudget', () {
    const budget = MemoryBudget(maxBytes: 100, criticalThreshold: 0.9);

    test('maps a total onto a pressure level at its thresholds', () {
      expect(budget.pressureFor(0), MemoryPressure.normal);
      expect(budget.pressureFor(69), MemoryPressure.normal);
      expect(budget.pressureFor(70), MemoryPressure.elevated);
      expect(budget.pressureFor(89), MemoryPressure.elevated);
      expect(budget.pressureFor(90), MemoryPressure.critical);
      expect(budget.pressureFor(99), MemoryPressure.critical);
      expect(budget.pressureFor(100), MemoryPressure.emergency);
      expect(budget.pressureFor(500), MemoryPressure.emergency);
    });

    test('reports the absolute thresholds', () {
      expect(budget.warningBytes, 70);
      expect(budget.criticalBytes, 90);
    });

    test('a disabled budget never reports pressure', () {
      const disabled = MemoryBudget(enabled: false, maxBytes: 100);

      expect(disabled.pressureFor(1000), MemoryPressure.normal);
      expect(disabled.hasPressure(1000), isFalse);
      expect(disabled.canAllocate(1000, 1000), isTrue);
    });

    test('remaining capacity never goes negative and ratio is clamped', () {
      expect(budget.remainingBytes(30), 70);
      expect(budget.remainingBytes(300), 0);
      expect(budget.usageRatio(50), 0.5);
      expect(budget.usageRatio(500), 1.0);
      expect(budget.usageRatio(-10), 0.0);
    });

    test('allocation fits only while the total stays inside the budget', () {
      expect(budget.canAllocate(20, 70), isTrue);
      expect(budget.canAllocate(31, 70), isFalse);
      expect(budget.canAllocate(0, 100), isTrue);
    });
  });

  group('MemoryPressure', () {
    test('orders levels and exposes the actions each implies', () {
      expect(MemoryPressure.emergency.isHigherThan(MemoryPressure.critical), isTrue);
      expect(MemoryPressure.max(MemoryPressure.elevated, MemoryPressure.emergency), MemoryPressure.emergency);
      expect(MemoryPressure.normal.hasPressure, isFalse);
      expect(MemoryPressure.elevated.hasPressure, isTrue);
      expect(MemoryPressure.elevated.shouldStopPreload, isFalse);
      expect(MemoryPressure.critical.shouldStopPreload, isTrue);
      expect(MemoryPressure.critical.shouldReleaseResources, isFalse);
      expect(MemoryPressure.emergency.shouldReleaseResources, isTrue);
      expect(MemoryPressure.emergency.shouldRefuseAllocation, isTrue);
      expect(MemoryPressure.elevated.label, 'elevated');
    });
  });

  group('MemoryAccount', () {
    test('accumulates, tracks a peak and reports it', () {
      final account = MemoryAccount(module: MemoryModule.pool)
        ..add(bytes: 100, items: 1, note: 'warm player')
        ..add(bytes: 300, items: 2);
      expect(account.bytes, 400);
      expect(account.items, 3);
      expect(account.peakBytes, 400);
      expect(account.note, 'warm player');
      expect(account.hasReported, isTrue);

      account.remove(bytes: 400, items: 3);
      expect(account.bytes, 0);
      expect(account.items, 0);
      expect(account.peakBytes, 400, reason: 'the peak survives the release');
    });

    test('clamps at zero so a double release cannot corrupt other modules', () {
      final account = MemoryAccount(module: MemoryModule.danmaku)
        ..add(bytes: 10, items: 1)
        ..remove(bytes: 50, items: 5);

      expect(account.bytes, 0);
      expect(account.items, 0);
    });

    test('ignores negative deltas', () {
      final account = MemoryAccount(module: MemoryModule.cache)
        ..add(bytes: 10)
        ..add(bytes: -5)
        ..remove(bytes: -5);

      expect(account.bytes, 10);
    });

    test('set reports a measured value outright', () {
      final account = MemoryAccount(module: MemoryModule.download)..set(bytes: 1234, items: 2, note: 'partial file');

      expect(account.bytes, 1234);
      expect(account.items, 2);
      expect(account.note, 'partial file');
    });

    test('an untouched account is distinguishable from an emptied one', () {
      final untouched = MemoryAccount(module: MemoryModule.recording);
      final emptied = MemoryAccount(module: MemoryModule.recording)
        ..add(bytes: 5)
        ..clear();

      expect(untouched.hasReported, isFalse);
      expect(emptied.hasReported, isTrue);
      expect(emptied.isEmpty, isTrue);
    });

    test('a per-module limit refuses allocations that would break it', () {
      final account = MemoryAccount(module: MemoryModule.cache, limitBytes: 100)..add(bytes: 80);

      expect(account.canAllocate(20), isTrue);
      expect(account.canAllocate(21), isFalse);
      expect(account.isOverLimit, isFalse);

      account.add(bytes: 30);
      expect(account.isOverLimit, isTrue);
    });

    test('a global remaining-budget check also applies', () {
      final account = MemoryAccount(module: MemoryModule.preload);

      expect(account.canAllocate(100, availableBytes: 100), isTrue);
      expect(account.canAllocate(101, availableBytes: 100), isFalse);
      expect(account.canAllocate(101), isTrue, reason: 'no budget supplied means only the module limit applies');
    });

    test('several contributors add up instead of overwriting each other', () {
      final account = MemoryAccount(module: MemoryModule.danmaku)
        ..report('cell-1', bytes: 100, items: 10, note: 'cell 1 queue')
        ..report('cell-2', bytes: 200, items: 20, note: 'cell 2 queue')
        ..report('cell-3', bytes: 300, items: 30, note: 'cell 3 queue');

      expect(account.bytes, 600, reason: 'nine wall cells must not collapse to the last one');
      expect(account.items, 60);
      expect(account.contributorCount, 3);
      expect(account.note, 'cell 3 queue', reason: 'the largest contribution describes the account');
      expect(account.peakBytes, 600);
    });

    test('a contributor that reports again replaces its own share', () {
      final account = MemoryAccount(module: MemoryModule.pip)
        ..report('session', bytes: 100, items: 1)
        ..report('session', bytes: 40, items: 1);

      expect(account.bytes, 40);
      expect(account.contributorCount, 1);
    });

    test('withdraw drops one contributor and leaves the others alone', () {
      final account = MemoryAccount(module: MemoryModule.playback)
        ..report('feed', bytes: 10, items: 1)
        ..report('list', bytes: 20, items: 2)
        ..withdraw('feed');

      expect(account.bytes, 20);
      expect(account.items, 2);
      expect(account.contributorCount, 1);

      account.withdraw('unknown');
      expect(account.bytes, 20);
    });

    test('the implicit single-instance API and contributors share the total', () {
      final account = MemoryAccount(module: MemoryModule.cache)
        ..report('cache-a', bytes: 100, items: 1)
        ..set(bytes: 50, items: 5);

      expect(account.bytes, 150);
      expect(account.items, 6);
      expect(account.contributorCount, 2);

      account.clear();
      expect(account.bytes, 0);
      expect(account.contributorCount, 0);
    });

    test('snapshots carry the contributor count', () {
      final account = MemoryAccount(module: MemoryModule.multiview)
        ..report('wall-1', bytes: 10)
        ..report('wall-2', bytes: 10);

      expect(account.snapshot().contributorCount, 2);
      expect(account.snapshot().toString(), contains('from 2 instances'));
    });

    test('resetPeaks forgets the peak but keeps the current values', () {
      final account = MemoryAccount(module: MemoryModule.pool)
        ..add(bytes: 500, items: 5)
        ..remove(bytes: 400, items: 4)
        ..resetPeaks();

      expect(account.peakBytes, 100);
      expect(account.peakItems, 1);
      expect(account.bytes, 100);
    });
  });

  group('MemoryRegistry', () {
    test('totals every account and judges them against the budget', () {
      final registry = MemoryRegistry(budget: const MemoryBudget(maxBytes: 1000));

      registry.accountFor(MemoryModule.pool).add(bytes: 300, items: 1);
      registry.accountFor(MemoryModule.danmaku).add(bytes: 200, items: 100);

      expect(registry.totalBytes, 500);
      expect(registry.totalItems, 101);
      expect(registry.pressure, MemoryPressure.normal);
      expect(registry.remainingBytes, 500);

      registry.accountFor(MemoryModule.pool).add(bytes: 250);

      expect(registry.pressure, MemoryPressure.elevated);
      expect(registry.canAllocate(300), isFalse);
    });

    test('creates an account on demand and returns the same one after', () {
      final registry = MemoryRegistry();

      final first = registry.accountFor(MemoryModule.kernel)..add(bytes: 10);

      expect(registry.accountFor(MemoryModule.kernel).bytes, 10);
      expect(registry.account(MemoryModule.kernel), same(first));
      expect(registry.accounts.length, 1);
    });

    test('builds a report sorted by size with the largest holder first', () {
      final registry = MemoryRegistry(budget: const MemoryBudget(maxBytes: 1000), clock: () => DateTime(2026, 9, 26));
      registry.accountFor(MemoryModule.danmaku).add(bytes: 100, items: 50, note: 'queue');
      registry.accountFor(MemoryModule.pool).add(bytes: 400, items: 2, note: 'warm players');
      registry.accountFor(MemoryModule.recording);

      final report = registry.report();

      expect(report.at, DateTime(2026, 9, 26));
      expect(report.totalBytes, 500);
      expect(report.accounts.map((account) => account.module.name).toList(), <String>['pool', 'danmaku', 'recording']);
      expect(report.largest?.module, MemoryModule.pool);
      expect(report.holders.length, 2, reason: 'the empty account is not a holder');
      expect(report.forModule(MemoryModule.danmaku)?.note, 'queue');
      expect(report.forModule(MemoryModule.host), isNull);
      expect(report.shareOf(MemoryModule.pool), 0.8);
      expect(report.shareOf(MemoryModule.host), 0.0);
      expect(report.budgetUsage, 0.5);
      expect(report.remainingBytes, 500);
    });

    test('a report carries the device measurement alongside the declared one', () {
      final registry = MemoryRegistry(budget: const MemoryBudget(maxBytes: 1000));
      registry.accountFor(MemoryModule.pool).add(bytes: 500);

      final report = registry.report(
        device: MemorySnapshot(timestamp: DateTime(2026, 9, 26), usedBytes: 900, availableBytes: 100),
      );

      expect(report.device?.usedBytes, 900);
      expect(report.device?.usageRatio, 0.9);
      expect(report.describe(), contains('device'));
      expect(report.toMap()['device'], isNotNull);
      expect((report.toMap()['accounts']! as List<Object?>).length, 1);
    });

    test('describe lists holders and skips empty accounts unless asked', () {
      final registry = MemoryRegistry(budget: const MemoryBudget(maxBytes: 1000));
      registry.accountFor(MemoryModule.pool).add(bytes: 400, items: 2, note: 'warm players');
      registry.accountFor(MemoryModule.cache);

      final report = registry.report();

      expect(report.describe(), contains('pool: 400B in 2 item(s)'));
      expect(report.describe(), contains('warm players'));
      expect(report.describe().contains('cache'), isFalse);
      expect(report.describe(includeEmpty: true), contains('cache'));
    });

    test('publishes reports to listeners', () async {
      final registry = MemoryRegistry();
      final seen = <MemoryReport>[];
      final subscription = registry.onReport.listen(seen.add);

      registry.accountFor(MemoryModule.pool).add(bytes: 10);
      registry.report();
      await Future<void>.delayed(Duration.zero);

      expect(seen.length, 1);
      expect(seen.single.totalBytes, 10);
      await subscription.cancel();
    });

    test('a budget change re-evaluates pressure immediately', () {
      final registry = MemoryRegistry(budget: const MemoryBudget(maxBytes: 1000));
      registry.accountFor(MemoryModule.pool).add(bytes: 500);
      expect(registry.pressure, MemoryPressure.normal);

      registry.budget = const MemoryBudget(maxBytes: 550);

      expect(registry.pressure, MemoryPressure.critical);
      expect(registry.budget.maxBytes, 550);
    });

    test('remove drops a module whose owner went away', () {
      final registry = MemoryRegistry();
      registry.accountFor(MemoryModule.multiview).add(bytes: 900);

      registry.remove(MemoryModule.multiview);

      expect(registry.totalBytes, 0);
      expect(registry.account(MemoryModule.multiview), isNull);
    });

    test('clear empties the ledgers but keeps the accounts', () {
      final registry = MemoryRegistry();
      registry.accountFor(MemoryModule.pool).add(bytes: 100, items: 1);

      registry.clear();

      expect(registry.totalBytes, 0);
      expect(registry.accounts.length, 1);
      expect(registry.account(MemoryModule.pool)?.peakBytes, 100);
    });

    test('a disposed registry refuses work', () async {
      final registry = MemoryRegistry();
      await registry.dispose();

      expect(() => registry.accountFor(MemoryModule.pool), throwsA(isA<StateError>()));
      expect(registry.report, throwsA(isA<StateError>()));
    });

    test('logs a rising and a falling pressure transition', () {
      final sink = MemoryLogSink();
      MediaCoreLog.clearSinks();
      MediaCoreLog.addSink(sink.call);
      MediaCoreLog.level = LogLevel.debug;
      addTearDown(MediaCoreLog.reset);

      final registry = MemoryRegistry(budget: const MemoryBudget(maxBytes: 100));
      final pool = registry.accountFor(MemoryModule.pool)..add(bytes: 75);
      registry.report();
      expect(sink.contains('memory pressure rising'), isTrue, reason: '70..85 is critical-free but elevated');

      pool.add(bytes: 25);
      registry.report();
      expect(sink.contains('memory budget exceeded'), isTrue, reason: 'at the budget it is an error, not a warning');

      pool.remove(bytes: 100);
      registry.report();
      expect(sink.contains('memory pressure released'), isTrue);
      expect(sink.messagesFor(LogCategory.memory).length, greaterThanOrEqualTo(3));
    });
  });

  group('MemoryMonitor', () {
    test('samples through the provider and stamps the time', () {
      final device = _FakeDevice()..usedBytes = 512;
      var now = DateTime(2026, 9, 26, 12);
      final monitor = MemoryMonitor(provider: device.call, clock: () => now);

      final snapshot = monitor.sample();

      expect(snapshot?.usedBytes, 512);
      expect(snapshot?.timestamp, now);
      expect(monitor.hasProvider, isTrue);

      now = DateTime(2026, 9, 26, 13);
      expect(monitor.sample()?.timestamp, DateTime(2026, 9, 26, 13));
    });

    test('without a provider there is nothing to sample', () {
      final monitor = MemoryMonitor();

      expect(monitor.sample(), isNull);
      expect(monitor.snapshot, isNull);
    });

    test('a throwing provider is swallowed', () {
      final device = _FakeDevice()..throws = true;
      final monitor = MemoryMonitor(provider: device.call);

      expect(monitor.sample(), isNull);
    });

    test('keeps a bounded history, oldest dropped first', () {
      final monitor = MemoryMonitor(historyCapacity: 3);

      for (var index = 0; index < 5; index++) {
        monitor.recordValues(usedBytes: index * 10, availableBytes: 100);
      }

      expect(monitor.history.map((snapshot) => snapshot.usedBytes).toList(), <int>[20, 30, 40]);
      expect(monitor.snapshot?.usedBytes, 40);
    });

    test('publishes measurements', () async {
      final monitor = MemoryMonitor();
      final seen = <int>[];
      final subscription = monitor.onSampled.listen((snapshot) => seen.add(snapshot.usedBytes));

      monitor.recordValues(usedBytes: 42, availableBytes: 1);
      await Future<void>.delayed(Duration.zero);

      expect(seen, <int>[42]);
      await subscription.cancel();
    });

    test('clear forgets the latest measurement and the history', () {
      final monitor = MemoryMonitor()
        ..recordValues(usedBytes: 1, availableBytes: 1)
        ..clear();

      expect(monitor.snapshot, isNull);
      expect(monitor.history, isEmpty);
    });

    test('a disposed monitor refuses work', () async {
      final monitor = MemoryMonitor();
      await monitor.dispose();

      expect(() => monitor.recordValues(usedBytes: 1, availableBytes: 1), throwsA(isA<StateError>()));
    });
  });

  group('MemoryManager', () {
    test('tracks a total directly when no registry is attached', () {
      final manager = MemoryManager(budget: const MemoryBudget(maxBytes: 100))
        ..addUsage(60)
        ..addUsage(40);
      expect(manager.memoryBytes, 100);
      expect(manager.pressure, MemoryPressure.emergency);
      expect(manager.requiresEmergencyCleanup, isTrue);
      expect(manager.remainingBytes, 0);

      manager.removeUsage(60);
      expect(manager.memoryBytes, 40);
      expect(manager.pressure, MemoryPressure.normal);
    });

    test('reads the registry total when one is attached', () {
      final registry = MemoryRegistry(budget: const MemoryBudget(maxBytes: 1000));
      final manager = MemoryManager(registry: registry);

      registry.accountFor(MemoryModule.pool).add(bytes: 900);

      expect(manager.memoryBytes, 900);
      expect(manager.pressure, MemoryPressure.critical);
      expect(manager.shouldCleanup, isTrue);

      // A second writer would make the two views disagree, so it is ignored.
      manager.addUsage(50);
      expect(manager.memoryBytes, 900);
    });

    test('a budget change through the manager reaches the registry', () {
      final registry = MemoryRegistry(budget: const MemoryBudget(maxBytes: 1000));
      final manager = MemoryManager(registry: registry);
      registry.accountFor(MemoryModule.pool).add(bytes: 500);

      manager.budget = const MemoryBudget(maxBytes: 550);

      expect(registry.budget.maxBytes, 550);
      expect(manager.pressure, MemoryPressure.critical);
    });

    test('snapshot exposes the current state', () {
      final manager = MemoryManager(budget: const MemoryBudget(maxBytes: 100))..updateUsage(80);

      expect(manager.snapshot().memoryBytes, 80);
      expect(manager.snapshot().pressure, MemoryPressure.elevated);
      expect(manager.snapshot().hasPressure, isTrue);
    });
  });

  group('MediaCoreMemory hub', () {
    tearDown(() async {
      MediaCoreLog.reset();
      await MediaCoreMemory.reset();
    });

    test('hands out one account per module and reports the total', () {
      MediaCoreMemory.of(MemoryModule.pool).add(bytes: 100, items: 1);
      MediaCoreMemory.of(MemoryModule.download).set(bytes: 50);

      final report = MediaCoreMemory.report();

      expect(MediaCoreMemory.totalBytes, 150);
      expect(report.forModule(MemoryModule.pool)?.items, 1);
      expect(MediaCoreMemory.canAllocate(MediaCoreMemory.remainingBytes), isTrue);
    });

    test('a module can enforce its own limit through the hub', () {
      final account = MediaCoreMemory.of(MemoryModule.cache, limitBytes: 100);

      expect(account.limitBytes, 100);
      expect(account.canAllocate(50), isTrue);
    });

    test('samples the device when a provider is installed', () {
      expect(MediaCoreMemory.sampleDevice(), isNull, reason: 'no provider yet');

      final device = _FakeDevice()..usedBytes = 700;
      MediaCoreMemory.attachDeviceProvider(device.call);
      MediaCoreMemory.of(MemoryModule.pool).add(bytes: 100);

      final report = MediaCoreMemory.sampleDevice();

      expect(report?.device?.usedBytes, 700);
      expect(report?.totalBytes, 100);
    });

    test('pressure and the budget are readable without a report', () {
      MediaCoreMemory.budget = const MemoryBudget(maxBytes: 100);
      MediaCoreMemory.of(MemoryModule.kernel).add(bytes: 100);

      expect(MediaCoreMemory.pressure, MemoryPressure.emergency);
      expect(MediaCoreMemory.budget.maxBytes, 100);
      expect(MediaCoreMemory.canAllocate(1), isFalse);
      expect(MediaCoreMemory.account(MemoryModule.kernel)?.bytes, 100);
      expect(MediaCoreMemory.account(MemoryModule.host), isNull);
    });

    test('remove and clear drop reported memory', () {
      MediaCoreMemory.of(MemoryModule.live).add(bytes: 10);
      MediaCoreMemory.of(MemoryModule.playback).add(bytes: 20);

      MediaCoreMemory.remove(MemoryModule.live);
      MediaCoreMemory.clear();

      expect(MediaCoreMemory.totalBytes, 0);
      expect(MediaCoreMemory.account(MemoryModule.live), isNull);
      expect(MediaCoreMemory.account(MemoryModule.playback)?.hasReported, isTrue);
    });

    test('reset disposes the old registry and monitor', () async {
      MediaCoreMemory.of(MemoryModule.pool).add(bytes: 5);
      final old = MediaCoreMemory.registry;

      await MediaCoreMemory.reset();

      expect(MediaCoreMemory.totalBytes, 0);
      expect(identical(MediaCoreMemory.registry, old), isFalse);
      expect(old.report, throwsA(isA<StateError>()));
    });
  });

  group('MemoryEstimates', () {
    test('picks a stream estimate by height', () {
      expect(MemoryEstimates.videoStream(1080), MemoryEstimates.videoStream1080p);
      expect(MemoryEstimates.videoStream(720), MemoryEstimates.videoStream720p);
      expect(MemoryEstimates.videoStream(480), MemoryEstimates.videoStreamLow);
      expect(MemoryEstimates.videoStream(null), MemoryEstimates.videoStream720p);
      expect(MemoryEstimates.videoStream(0), MemoryEstimates.videoStream720p);
    });

    test('formats byte counts for humans', () {
      expect(MemoryEstimates.formatBytes(512), '512B');
      expect(MemoryEstimates.formatBytes(2048), '2.0KB');
      expect(MemoryEstimates.formatBytes(3 * 1024 * 1024), '3.0MB');
      expect(MemoryEstimates.formatBytes(2 * 1024 * 1024 * 1024), '2.00GB');
      expect(MemoryEstimates.formatBytes(-2048), '-2.0KB');
    });
  });
}
