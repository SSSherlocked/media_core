import 'package:example/demos/module_demo.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// Memory accounting: who is holding what, and how close that is to the budget.
///
/// The point this demo makes is the one a single "memory used" number cannot:
/// every module reports its own footprint, several instances of the same module
/// add up instead of overwriting each other, and the total is judged against a
/// budget that turns into a pressure level the modules can act on.
class MemoryDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'memory';

  @override
  ModuleCategory get category => ModuleCategory.foundation;

  @override
  String get nameZh => '内存记账与压力';

  @override
  String get nameEn => 'Memory accounting & pressure';

  @override
  String get purposeZh =>
      '每个模块把自己持有的东西报进账本（items + bytes），账户按贡献者分别记账再求和；总量对照 MemoryBudget 折算成四级压力。没有 Dart API 能报出解码器真实占用，所以模块上报的是申报值，磁盘缓存/下载/录像是实测值。';

  @override
  String get purposeEn =>
      "Every module reports what it holds (items + bytes); an account sums its contributors instead of keeping the last one; the total is turned into one of four pressure levels by MemoryBudget. No Dart API reports a decoder's real bytes, so module figures are declared — while the cache, downloads and recordings report measured ones.";

  @override
  List<String> get pointsZh => const <String>[
    'MediaCoreMemory.of(MemoryModule.pool) — 取账本，report/withdraw 按实例记账',
    '多个贡献者相加：一面 3×3 视频墙的 9 个弹幕队列不会被最后一个覆盖',
    'MemoryBudget 阈值 → normal / elevated / critical / emergency',
    'report().describe() — 一行一模块，最大的排在最前',
    'attachDeviceProvider — 设备实测值与申报值同框显示（是不同的两个数）',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'MediaCoreMemory.of(MemoryModule.pool) — take a ledger; report/withdraw per instance',
    'Contributors add up: nine walls do not collapse into the last one that reported',
    'MemoryBudget thresholds → normal / elevated / critical / emergency',
    'report().describe() — one line per module, largest first',
    'attachDeviceProvider — measured device numbers next to declared ones (two different numbers)',
  ];

  @override
  String get snippet => '''
final pool = MediaCoreMemory.of(MemoryModule.pool);
pool.report('wall-1', items: 4, bytes: 4 * MemoryEstimates.videoStream720p);
pool.report('wall-2', items: 4, bytes: 4 * MemoryEstimates.videoStream720p);  // adds up

MediaCoreMemory.budget = const MemoryBudget(maxBytes: 512 * 1024 * 1024);
if (MediaCoreMemory.pressure.shouldStopPreload) return;

print(MediaCoreMemory.report().describe());
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();

    // The demo runs inside the example app, which has its own (empty) hub.
    // Setting a small budget makes the thresholds reachable in a few lines
    // instead of in a few hundred megabytes.
    final previousBudget = MediaCoreMemory.budget;
    MediaCoreMemory.budget = const MemoryBudget(
      maxBytes: 600 * 1024 * 1024,
      warningThreshold: 0.5,
      criticalThreshold: 0.75,
    );

    try {
      buffer
        ..writeln('budget: ${MediaCoreMemory.budget}')
        ..writeln(
          '  warning at ${MemoryEstimates.formatBytes(MediaCoreMemory.budget.warningBytes)}, '
          'critical at ${MemoryEstimates.formatBytes(MediaCoreMemory.budget.criticalBytes)}',
        )
        ..writeln();

      // One module, two instances: a host running two walls.
      final danmaku = MediaCoreMemory.of(MemoryModule.danmaku)
        ..report('wall-1', items: 120, bytes: 120 * MemoryEstimates.danmakuMessage, note: 'wall 1 queue')
        ..report('wall-2', items: 80, bytes: 80 * MemoryEstimates.danmakuMessage, note: 'wall 2 queue');

      buffer
        ..writeln('two contributors on one account:')
        ..writeln(
          '  danmaku account: ${danmaku.bytes} bytes, ${danmaku.items} items, '
          '${danmaku.contributorCount} contributor(s)',
        )
        ..writeln('  → summed, not overwritten; note comes from the largest: "${danmaku.note}"')
        ..writeln();

      // A single-instance module uses the implicit contributor.
      final pool = MediaCoreMemory.of(MemoryModule.pool)
        ..set(items: 6, bytes: 6 * MemoryEstimates.videoStream720p, note: '4 active, 2 warm');

      buffer
        ..writeln(
          'pool holds ${pool.items} players → '
          '${MemoryEstimates.formatBytes(pool.bytes)} (${MemoryEstimates.formatBytes(MemoryEstimates.videoStream720p)} each, declared)',
        )
        ..writeln('  pressure now: ${MediaCoreMemory.pressure.label}')
        ..writeln();

      // Cross the thresholds and watch the level move. The numbers land in each
      // band: 16 players is 512MiB of a 600MiB budget (85%), and 19 is past it
      // (the 720p estimate is 32MiB per stream).
      for (final players in <int>[8, 16, 19]) {
        pool.set(items: players, bytes: players * MemoryEstimates.videoStream720p, note: '$players players');
        final report = MediaCoreMemory.report();

        buffer.writeln(
          '$players players → ${MemoryEstimates.formatBytes(report.totalBytes)} '
          '(${(report.budgetUsage * 100).toStringAsFixed(0)}% of budget) → ${report.pressure.label}'
          '${report.pressure.shouldStopPreload ? ' — preload should stop' : ''}'
          '${report.pressure.shouldReleaseResources ? ' — release now' : ''}',
        );
      }

      buffer
        ..writeln()
        ..writeln(
          'the ledger knows it was higher before: pool peak = '
          '${MemoryEstimates.formatBytes(pool.peakBytes)} (the report shows peaks per module)',
        )
        ..writeln();

      // Measuring the device is the host's job; the framework ships no reader.
      MediaCoreMemory.attachDeviceProvider(
        () => MemorySnapshot(
          timestamp: DateTime.now(),
          usedBytes: 1800 * 1024 * 1024,
          availableBytes: 2200 * 1024 * 1024,
          externalBytes: 210 * 1024 * 1024,
        ),
      );
      MediaCoreMemory.sampleDevice();

      final report = MediaCoreMemory.report();
      buffer
        ..writeln('full report (declared + measured):')
        ..writeln(report.describe())
        ..writeln();

      // Releasing: a module that goes away withdraws its share.
      danmaku.withdraw('wall-2');
      pool.set(bytes: 0, items: 0, note: 'released');

      buffer
        ..writeln('after one wall closed and the pool released everything:')
        ..writeln(MediaCoreMemory.report().describe())
        ..writeln()
        ..writeln('note the difference between the two numbers above:')
        ..writeln('  tracked  = what the modules declare they hold')
        ..writeln('  device   = what the operating system reports the process uses')
        ..writeln('  they never match, and confusing them is how memory bugs get misfiled.');

      return buffer.toString();
    } finally {
      // Leave the app's hub as it was found: the fake device reader would
      // otherwise keep answering for every later page.
      MediaCoreMemory.monitor.setProvider(null);
      MediaCoreMemory.budget = previousBudget;
      MediaCoreMemory.clear();
      MediaCoreMemory.remove(MemoryModule.danmaku);
      MediaCoreMemory.remove(MemoryModule.pool);
    }
  }
}
