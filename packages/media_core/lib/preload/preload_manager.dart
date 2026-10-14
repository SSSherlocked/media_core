import 'dart:async';

import 'package:media_core/preload/preload_metrics.dart';
import 'package:media_core/preload/preload_request.dart';
import 'package:media_core/preload/preload_scheduler.dart';
import 'package:media_core/preload/preload_task.dart';
import 'package:media_core_memory/media_core_memory.dart';
import 'package:rxdart/rxdart.dart';

/// Manages preload lifecycle.
final class PreloadManager {
  /// Creates an empty preload manager.
  PreloadManager();

  final PreloadScheduler _scheduler = PreloadScheduler();

  final Map<String, PreloadTask> _tasks = {};

  final BehaviorSubject<PreloadMetrics> _metricsSubject = BehaviorSubject.seeded(const PreloadMetrics());

  /// A stream of preload statistics, emitting whenever a task changes state.
  Stream<PreloadMetrics> get metrics => _metricsSubject.stream;

  /// The most recent preload statistics.
  PreloadMetrics get currentMetrics => _metricsSubject.value;

  /// The number of tasks currently tracked.
  int get count => _tasks.length;

  /// Ledger of the sources being preloaded.
  ///
  /// A preload is an open stream the viewer has not asked for yet: it is the
  /// first thing that should give up under memory pressure, and this is how a
  /// report shows it exists.
  /// This instance's key in the shared account.
  late final String _memoryKey = memoryContributorKey(this);

  final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.preload);

  /// Registers [request] as a new preload task and schedules it.
  void add(PreloadRequest request) {
    final task = PreloadTask(sourceId: request.sourceId, priority: request.priority);

    _tasks[request.sourceId.value] = task;

    _scheduler.add(task);

    _updateMetrics(total: currentMetrics.total + 1);

    _reportMemory();
  }

  /// Takes the next scheduled task to run, or `null` when none is queued.
  PreloadTask? next() {
    return _scheduler.next();
  }

  /// Marks [task] as successfully completed and drops it from the ledger.
  void complete(PreloadTask task) {
    task.complete();
    _forget(task);

    _updateMetrics(completed: currentMetrics.completed + 1);

    _reportMemory();
  }

  /// Marks [task] as failed and drops it from the ledger.
  void fail(PreloadTask task) {
    task.fail();
    _forget(task);

    _updateMetrics(failed: currentMetrics.failed + 1);

    _reportMemory();
  }

  /// Marks [task] as cancelled and drops it from the ledger.
  void cancel(PreloadTask task) {
    task.cancel();
    _forget(task);

    _updateMetrics(cancelled: currentMetrics.cancelled + 1);

    _reportMemory();
  }

  /// Drops a finished task from the open-preload ledger.
  ///
  /// [_reportMemory] multiplies the open count by a per-stream estimate, so a
  /// task left behind after it completed, failed or was cancelled keeps
  /// claiming memory nobody holds — and the shared account is what other
  /// modules read when they decide whether to shed work.
  void _forget(PreloadTask task) {
    _tasks.removeWhere((_, candidate) => identical(candidate, task));
  }

  /// Reports the preloads still open.
  void _reportMemory() {
    _memory.report(
      _memoryKey,
      items: _tasks.length,
      bytes: _tasks.length * MemoryEstimates.videoStream720p,
      note: '${_tasks.length} preloading source(s)',
    );
  }

  void _updateMetrics({int? total, int? completed, int? failed, int? cancelled}) {
    _metricsSubject.add(
      currentMetrics.copyWith(total: total, completed: completed, failed: failed, cancelled: cancelled),
    );
  }

  /// Releases the scheduler, ledger, memory claim and metrics stream.
  Future<void> dispose() async {
    _scheduler.clear();

    _tasks.clear();

    _memory.withdraw(_memoryKey);

    await _metricsSubject.close();
  }
}
