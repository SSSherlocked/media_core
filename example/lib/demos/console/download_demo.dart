import 'package:example/demos/fakes/fake_download.dart';
import 'package:example/demos/module_demo.dart';
import 'package:media_core/media_core.dart' show TaskId, TaskPriority;
import 'package:media_core_download/media_core_download.dart';

/// The download queue: concurrency, resume, verification and retries.
///
/// Downloads fail in specific ways, and each one has a decision attached: a
/// server that ignores `Range`, a partial file that is not a prefix of the
/// remote one, an attempt budget that runs out. The demo drives all of them
/// against a fake transport, so the output is what the manager decided rather
/// than what a particular server happened to do.
class DownloadDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'download';

  @override
  ModuleCategory get category => ModuleCategory.capability;

  @override
  String get nameZh => '下载队列：并发 / 续传校验 / 重试预算';

  @override
  String get nameEn => 'Download queue: concurrency, resume verification, retry budget';

  @override
  String get purposeZh =>
      '下载建立在内核的 TaskManager 上：并发与优先级由队列给，续传与校验由本模块给。续传前先比对文件尾与远端前若干字节，不一致就整文件重下——因为"能播到某个位置"的文件比没有文件更坏。';

  @override
  String get purposeEn =>
      'Downloads sit on the core TaskManager: concurrency and priority come from the queue, resume and verification from this module. Before appending, the tail on disk is compared with the head of the remote file; a mismatch restarts the whole file, because a file that plays up to some offset is worse than no file at all.';

  @override
  List<String> get pointsZh => const <String>[
    'maxConcurrent 决定同时几个传输，priority 决定下一个是谁',
    '续传：先读本地尾 N 字节与远端前 N 字节比对（verifyTailBytes），一致才 append',
    '服务端忽略 Range（返回 200 + 整个文件）时，文件从头重下，绝不重复追加',
    'attempt 用尽 → failed；ResumeMismatch 不重试（重试也会得到同一个文件）',
    '进度与速度按 200ms 采样，事件流直接可绑进度条',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'maxConcurrent sets how many transfers run at once; priority sets which one is next',
    'Resume: the local tail is compared with the remote head (verifyTailBytes) before anything is appended',
    'A server that ignores Range (200 + whole body) restarts the file instead of duplicating bytes',
    'A spent attempt budget → failed; a resume mismatch is not retried (a retry would produce the same file)',
    'Progress and speed are sampled every 200ms, and the task stream binds straight to a progress bar',
  ];

  @override
  String get snippet => r'''
final manager = DownloadManager(
  transport: HttpDownloadTransport(config: config),
  config: const DownloadConfig(maxConcurrent: 2, maxAttempts: 3, verifyTailBytes: 1024),
);

manager.onTaskChanged.listen((task) => print('${task.id} ${task.status.name}'));

manager.add(DownloadTask(id: TaskId('ep1'), url: url, filePath: '${dir}/ep1.mp4'));
await manager.pause('ep1');    // keeps the partial file
await manager.resume('ep1');   // verifies, then continues
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();

    await _concurrencySection(buffer);
    await _resumeSection(buffer);
    await _ignoredRangeSection(buffer);
    await _retryBudgetSection(buffer);

    return buffer.toString();
  }

  /// Two transfers at a time, the third waiting for a slot.
  Future<void> _concurrencySection(StringBuffer buffer) async {
    final transport = FakeDownloadTransport(chunkDelay: const Duration(milliseconds: 12));
    final files = FakeDownloadFileSink();
    final manager = DownloadManager(
      transport: transport,
      files: files,
      config: const DownloadConfig(maxConcurrent: 2, verifyTailBytes: 0),
    );

    final events = <String>[];
    final lastStatus = <String, String>{};
    final subscription = manager.onTaskChanged.listen((task) {
      // One line per status change per task: progress fires per chunk, and
      // alternating between tasks would otherwise repeat two lines twenty times.
      if (lastStatus[task.id.value] == task.status.name) {
        return;
      }
      lastStatus[task.id.value] = task.status.name;
      events.add('${task.id.value} → ${task.status.name}');
    });

    for (final name in <String>['ep1', 'ep2', 'ep3']) {
      manager.add(
        DownloadTask(
          id: TaskId(name),
          url: 'https://example.com/$name.mp4',
          filePath: '/tmp/$name.mp4',
          priority: name == 'ep3' ? TaskPriority.high : TaskPriority.normal,
        ),
      );
    }

    await _settle(manager);
    await subscription.cancel();

    buffer
      ..writeln('DownloadConfig(maxConcurrent: 2), three tasks added (ep3 at high priority):')
      ..writeln('  ${events.join('   ')}')
      ..writeln('  → queued → running → completed per task; never three running at once')
      ..writeln('  requests the transport saw: ${transport.requests.length}')
      ..writeln();

    await manager.dispose();
  }

  /// Resume: verified tail, then continue where it stopped.
  Future<void> _resumeSection(StringBuffer buffer) async {
    final transport = FakeDownloadTransport(chunkDelay: const Duration(milliseconds: 8));
    final files = FakeDownloadFileSink();
    final manager = DownloadManager(
      transport: transport,
      files: files,
      config: const DownloadConfig(maxConcurrent: 1, verifyTailBytes: 256),
    )..add(DownloadTask(id: TaskId('movie'), url: 'https://example.com/movie.mp4', filePath: '/tmp/movie.mp4'));

    // Let it get partway, then pause: the partial file is the whole point.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await manager.pause('movie');

    final partial = await files.length('/tmp/movie.mp4');
    final requestsBefore = transport.requests.length;

    buffer
      ..writeln('paused after $partial bytes of ${transport.totalBytes}:')
      ..writeln('  status=${manager.task('movie')?.status.name}, file kept on disk')
      ..writeln('  looks like a prefix of the remote file: ${files.looksLikePrefixOf('/tmp/movie.mp4')}')
      ..writeln();

    await manager.resume('movie');
    await _settle(manager);

    final resumedRequests = transport.requests.skip(requestsBefore).toList();

    buffer
      ..writeln('after resume:')
      ..writeln(
        '  status=${manager.task('movie')?.status.name}, '
        'bytes=${files.files['/tmp/movie.mp4']?.length ?? 0}',
      )
      ..writeln('  requests the resume issued: $resumedRequests')
      ..writeln('  the first 256 bytes were re-fetched and compared before anything was appended —')
      ..writeln('  that is what makes appending to a stale file safe.')
      ..writeln();

    await manager.dispose();
  }

  /// A server that ignores Range: restart, never duplicate.
  Future<void> _ignoredRangeSection(StringBuffer buffer) async {
    final transport = FakeDownloadTransport(chunkDelay: const Duration(milliseconds: 8));
    final files = FakeDownloadFileSink();
    final manager = DownloadManager(
      transport: transport,
      files: files,
      config: const DownloadConfig(maxConcurrent: 1, verifyTailBytes: 128),
    );

    // A partial file left by a previous run: bytes that were never served by
    // this transport, so it cannot be a prefix of the remote file.
    files.seed('/tmp/poisoned.mp4', 4096);

    manager.add(DownloadTask(id: TaskId('poisoned'), url: 'https://example.com/x.mp4', filePath: '/tmp/poisoned.mp4'));

    await _settle(manager);

    buffer
      ..writeln('a partial file that is NOT a prefix of the remote one (simulating a rotated URL):')
      ..writeln(
        '  status=${manager.task('poisoned')?.status.name}, '
        'final bytes=${files.files['/tmp/poisoned.mp4']?.length ?? 0}',
      )
      ..writeln('  the manager truncated it and started over instead of appending 60KB of garbage')
      ..writeln(
        '  requests: ${transport.requests.length} '
        '(one rejected by the tail check, one full fetch)',
      )
      ..writeln();

    await manager.dispose();
  }

  /// An attempt budget that runs out.
  Future<void> _retryBudgetSection(StringBuffer buffer) async {
    final transport = FakeDownloadTransport(
      chunkDelay: const Duration(milliseconds: 4),
      // Fails more often than the budget allows, so the task ends failed.
      failuresBeforeSuccess: 5,
    );
    final files = FakeDownloadFileSink();
    final manager = DownloadManager(
      transport: transport,
      files: files,
      config: const DownloadConfig(maxConcurrent: 1, retryDelay: Duration(milliseconds: 10)),
    );

    final statuses = <String>[];
    final subscription = manager.onTaskChanged.listen((task) {
      if (statuses.isEmpty || statuses.last != task.status.name) {
        statuses.add(task.status.name);
      }
    });

    manager.add(DownloadTask(id: TaskId('flaky'), url: 'https://example.com/flaky.mp4', filePath: '/tmp/flaky.mp4'));

    await _settle(manager, timeout: const Duration(seconds: 3));
    await subscription.cancel();

    buffer
      ..writeln('a transport that refuses 5 times, with maxAttempts: 3:')
      ..writeln('  ${statuses.join(' → ')}')
      ..writeln('  the failure carries the last error: ${manager.task('flaky')?.error}')
      ..writeln('  → a retry budget that never gives up is a battery drain; the task ends, visibly.')
      ..writeln();

    await manager.dispose();
  }

  /// Waits until nothing is queued or running, or the timeout passes.
  Future<void> _settle(DownloadManager manager, {Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final busy = manager.tasks.any((task) => task.isRunning) || manager.queue.hasQueuedTasks;
      if (!busy) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}
