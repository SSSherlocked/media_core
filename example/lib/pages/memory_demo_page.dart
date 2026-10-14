import 'dart:async';

import 'package:example/language.dart';
import 'package:example/ui/demo_log.dart';
import 'package:example/ui/demo_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// A live view of the memory hub.
///
/// The module's whole point is that the numbers are attributable, so the page
/// shows the report the framework would print in a bug report — and lets the
/// developer *cause* the interesting states: raise the pressure by reporting
/// holdings, cross a threshold, release everything, and watch which module the
/// report blames.
class MemoryDemoPage extends StatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  State<MemoryDemoPage> createState() => _MemoryDemoPageState();
}

final class _MemoryDemoPageState extends State<MemoryDemoPage> {
  final DemoLog _log = DemoLog();

  StreamSubscription<MemoryReport>? _reportSub;
  MemoryReport? _report;

  /// Installed by the "device provider" toggle; the framework ships no reader.
  bool _deviceProvider = false;

  /// Budget in MB, editable from the page.
  double _budgetMb = 512;

  /// Which consumers the "report holdings" button pretends to be.
  ///
  /// Not `const`: [MemoryModule] has value equality, which a constant map key
  /// is not allowed to have.
  static final Map<MemoryModule, int> _scenario = <MemoryModule, int>{
    MemoryModule.kernel: 3,
    MemoryModule.pool: 4,
    MemoryModule.preload: 2,
    MemoryModule.danmaku: 240,
    MemoryModule.cache: 32,
  };

  @override
  void initState() {
    super.initState();

    _applyBudget(_budgetMb);
    _reportSub = MediaCoreMemory.onReport.listen(_onReport);
    _report = MediaCoreMemory.report();

    _log
      ..add('budget: ${MemoryEstimates.formatBytes(MediaCoreMemory.budget.maxBytes)}')
      ..add('logging is on at debug level — pressure transitions appear here and in the console');
  }

  @override
  void dispose() {
    // dispose() is synchronous: the report subscription close is detached here.
    unawaited(_reportSub?.cancel());
    _detachDeviceProvider();
    MediaCoreMemory.clear();
    MediaCoreMemory.remove(MemoryModule.kernel);
    MediaCoreMemory.remove(MemoryModule.pool);
    MediaCoreMemory.remove(MemoryModule.preload);
    MediaCoreMemory.remove(MemoryModule.danmaku);
    MediaCoreMemory.remove(MemoryModule.cache);
    _log.dispose();

    super.dispose();
  }

  void _onReport(MemoryReport report) {
    if (!mounted) {
      return;
    }
    setState(() => _report = report);
  }

  void _applyBudget(double megabytes) {
    final maxBytes = (megabytes * 1024 * 1024).round();
    final previous = MediaCoreMemory.pressure;
    MediaCoreMemory.budget = MemoryBudget(maxBytes: maxBytes);

    if (previous != MediaCoreMemory.pressure) {
      _log.add(
        'budget → ${megabytes.toStringAsFixed(0)}MB, pressure ${previous.label} → '
        '${MediaCoreMemory.pressure.label}',
      );
    }
  }

  /// Reports a plausible set of holdings, one account per module.
  void _reportHoldings() {
    for (final entry in _scenario.entries) {
      final units = entry.value;
      final bytes = switch (entry.key) {
        MemoryModule.kernel || MemoryModule.pool || MemoryModule.preload => units * MemoryEstimates.videoStream720p,
        MemoryModule.danmaku => units * MemoryEstimates.danmakuMessage,
        _ => units * MemoryEstimates.cacheEntry,
      };

      MediaCoreMemory.of(entry.key).set(
        items: units,
        bytes: bytes,
        note: switch (entry.key) {
          MemoryModule.kernel => '$units open player(s)',
          MemoryModule.pool => '$units pooled player(s)',
          MemoryModule.preload => '$units preloading source(s)',
          MemoryModule.danmaku => '$units queued message(s)',
          _ => '$units cached entry(ies)',
        },
      );

      _log.add('${entry.key.name}: ${MemoryEstimates.formatBytes(bytes)} in $units item(s)');
    }

    _log.add(
      'report: ${MediaCoreMemory.pressure.label} '
      '(${MemoryEstimates.formatBytes(MediaCoreMemory.totalBytes)} of '
      '${MemoryEstimates.formatBytes(MediaCoreMemory.budget.maxBytes)})',
    );
    MediaCoreMemory.report();
  }

  /// Reports nothing at all: every account goes back to zero.
  void _releaseAll() {
    MediaCoreMemory.clear();
    MediaCoreMemory.report();
    _log.add('every module released its holdings → ${MediaCoreMemory.pressure.label}');
  }

  void _toggleDeviceProvider(bool value) {
    setState(() => _deviceProvider = value);

    if (value) {
      // A host installs this; the framework deliberately ships no platform
      // memory reader, because the dependency belongs to the application.
      MediaCoreMemory.attachDeviceProvider(
        () => MemorySnapshot(
          timestamp: DateTime.now(),
          usedBytes: 1400 * 1024 * 1024,
          availableBytes: 2600 * 1024 * 1024,
          externalBytes: 180 * 1024 * 1024,
        ),
      );
      MediaCoreMemory.sampleDevice();
      _log.add('device provider installed: 1.4GB used of 4GB (a fake — a real one reads the platform)');
    } else {
      _detachDeviceProvider();
      _log.add('device provider removed');
    }

    MediaCoreMemory.report();
  }

  void _detachDeviceProvider() {
    MediaCoreMemory.monitor.setProvider(null);
  }

  @override
  Widget build(BuildContext context) {
    final isZh = DemoLanguageScope.of(context) == DemoLanguage.zh;
    final report = _report;
    final pressure = report?.pressure ?? MemoryPressure.normal;

    return DemoPageScaffold(
      title: isZh ? '内存监控 / Memory' : 'Memory',
      subtitle: isZh ? '每个模块上报自己持有的东西；总量对照预算折算成压力等级。申报值来自模块，设备值来自平台 provider，两者是不同的两个数。' : 'Each module reports what it holds; the total is turned into a pressure level by the budget. Declared figures come from modules, measured ones from a platform provider — two different numbers.',
      log: _log,
      logHeight: 130,
      actions: <Widget>[
        FilledButton.icon(
          onPressed: _reportHoldings,
          icon: const Icon(Icons.memory),
          label: Text(isZh ? '上报一批占用' : 'Report holdings'),
        ),
        OutlinedButton(onPressed: _releaseAll, child: Text(isZh ? '全部释放' : 'Release all')),
        OutlinedButton(
          onPressed: () {
            MediaCoreMemory.of(MemoryModule.download)
                .set(items: 1, bytes: 96 * 1024 * 1024, note: 'one large download, measured bytes');
            MediaCoreMemory.report();
            _log.add('download: 96.0MB (a measured figure, not an estimate)');
          },
          child: Text(isZh ? '加上一个下载' : 'Add a download'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PressureBanner(pressure: pressure, report: report, isZh: isZh),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Text(isZh ? '预算' : 'Budget'),
              Expanded(
                child: Slider(
                  value: _budgetMb,
                  min: 64,
                  max: 2048,
                  divisions: 31,
                  label: '${_budgetMb.toStringAsFixed(0)}MB',
                  onChanged: (value) {
                    setState(() => _budgetMb = value);
                    _applyBudget(value);
                  },
                ),
              ),
              Text('${_budgetMb.toStringAsFixed(0)}MB'),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _deviceProvider,
            onChanged: _toggleDeviceProvider,
            title: Text(isZh ? '安装设备内存 provider（假数据）' : 'Install a device memory provider (fake)'),
            subtitle: Text(
              isZh
                  ? '真实读数由宿主提供：框架不替应用决定依赖与权限'
                  : 'The real reader belongs to the host: the framework does not pick the dependency for the app',
            ),
          ),
          if (report != null) ...<Widget>[const SizedBox(height: 4), _Breakdown(report: report, isZh: isZh)],
        ],
      ),
    );
  }
}

/// The headline: how close the tracked total is to the budget.
class _PressureBanner extends StatelessWidget {
  const new({required this.pressure, required this.report, required this.isZh});

  final MemoryPressure pressure;
  final MemoryReport? report;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final color = switch (pressure) {
      MemoryPressure.normal => Colors.green,
      MemoryPressure.elevated => Colors.orange,
      MemoryPressure.critical => Colors.deepOrange,
      MemoryPressure.emergency => Colors.red,
    };

    final actions = <String>[
      if (pressure.shouldStopPreload)
        if (isZh) '停止预载' else 'stop preloading',
      if (pressure.shouldReleaseResources)
        if (isZh) '立即释放' else 'release now',
      if (pressure == MemoryPressure.elevated)
        if (isZh) '停止增长' else 'stop growing',
    ];

    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.speed, color: color),
                const SizedBox(width: 8),
                Text(
                  pressure.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Text(
                  report == null
                      ? ''
                      : '${MemoryEstimates.formatBytes(report!.totalBytes)} / '
                            '${MemoryEstimates.formatBytes(report!.budget.maxBytes)} '
                            '(${(report!.budgetUsage * 100).toStringAsFixed(0)}%)',
                ),
              ],
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('→ ${actions.join(', ')}', style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

/// One line per module, largest first — the same breakdown `describe()` prints.
class _Breakdown extends StatelessWidget {
  const new({required this.report, required this.isZh});

  final MemoryReport report;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final holders = report.holders;
    final device = report.device;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          isZh ? '谁在用（申报值，最大者在前）' : 'Who holds what (declared, largest first)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        if (holders.isEmpty)
          Text(isZh ? '（账本为空：没有任何模块上报）' : '(nothing reported yet)', style: Theme.of(context).textTheme.bodySmall),
        for (final account in holders)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(account.module.name, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
                SizedBox(
                  width: 86,
                  child: Text(
                    MemoryEstimates.formatBytes(account.bytes),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: report.totalBytes == 0 ? 0 : account.bytes / report.totalBytes,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${account.items}×${account.contributorCount > 1 ? ' (${account.contributorCount} inst.)' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        if (holders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              isZh
                  ? '峰值：${holders.map((a) => '${a.module.name} ${MemoryEstimates.formatBytes(a.peakBytes)}').join('，')}'
                  : 'Peaks: ${holders.map((a) => '${a.module.name} ${MemoryEstimates.formatBytes(a.peakBytes)}').join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 10),
        Text(isZh ? '设备实测（进程视角）' : 'Measured device (whole process)', style: Theme.of(context).textTheme.titleSmall),
        Text(
          device == null
              ? (isZh ? '未安装 provider：只有申报值可用' : 'No provider installed: only declared figures are available')
              : 'used ${MemoryEstimates.formatBytes(device.usedBytes)}, '
                    'available ${MemoryEstimates.formatBytes(device.availableBytes)}, '
                    'external ${MemoryEstimates.formatBytes(device.externalBytes)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
