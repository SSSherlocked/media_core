import 'package:example/demos/module_demo.dart';
import 'package:media_core/media_core.dart';

/// Tasks, ordering and retries: the primitives every other module is built on.
///
/// These are the modules a host rarely calls directly and always depends on
/// indirectly, so what is worth seeing is their *ordering guarantee*: a task
/// queue that starts work by priority under a concurrency cap, a serial executor
/// that never runs two operations at once, a mutex that makes a read-modify-write
/// atomic, and a retry policy that backs off instead of spinning.
class TaskDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'task';

  @override
  ModuleCategory get category => ModuleCategory.control;

  @override
  String get nameZh => '任务队列、串行化与重试';

  @override
  String get nameEn => 'Task queue, serialization & retries';

  @override
  String get purposeZh =>
      'TaskManager 按优先级出队、按 maxConcurrentTasks 限并发；SerialExecutor 保证同一队列内的操作严格串行；Mutex/Lock 把一段读改写变成原子操作；RetryUtils 提供尝试预算与指数退避。下载、池、弹幕都建立在这四个原语上。';

  @override
  String get purposeEn =>
      'TaskManager dequeues by priority under a concurrency cap; SerialExecutor guarantees strict ordering within one queue; Mutex/Lock turn a read-modify-write into an atomic operation; RetryUtils supplies an attempt budget and exponential backoff. Downloads, the pool and danmaku are all built on these four.';

  @override
  List<String> get pointsZh => const <String>[
    'createAndQueue(priority: highest) — 同批入队，按优先级而不是入队顺序开跑',
    'maxConcurrentTasks — 并发上限决定"同时跑几个"，不决定"下一个是谁"',
    'SerialExecutor.execute — 同一执行器内的操作首尾相接，用于状态不变的写路径',
    'Mutex.protect — 没有它，两次自增会互相覆盖；有它，结果可预测',
    'RetryUtils.run(shouldRetry:) + backoff(attempt) — 预算与退避分开表达',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'createAndQueue(priority: highest) — a batch starts by priority, not by insertion order',
    'maxConcurrentTasks sets how many run at once, not which one is next',
    'SerialExecutor.execute — operations in one executor never overlap; for state that must not interleave',
    'Mutex.protect — without it two increments lose each other; with it the result is predictable',
    'RetryUtils.run(shouldRetry:) + backoff(attempt) — the budget and the delay are separate decisions',
  ];

  @override
  String get snippet => '''
final queue = TaskManager(maxConcurrentTasks: 2);
queue.createAndQueue(id: TaskId('open'), type: TaskType.open, priority: TaskPriority.highest);
queue.createAndQueue(id: TaskId('preload'), type: TaskType.prepare, priority: TaskPriority.low);

while (queue.hasQueuedTasks) {
  await queue.executeAvailable((task) async => print(task.id));
}

final serial = SerialExecutor();
await Future.wait([serial.execute(step), serial.execute(step)]);   // run one after the other

final counter = Mutex();
await Future.wait([
  counter.protect(() async => value = value + 1),
  counter.protect(() async => value = value + 1),
]);
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();

    await _queueSection(buffer);
    await _serialSection(buffer);
    await _mutexSection(buffer);
    await _retrySection(buffer);

    return buffer.toString();
  }

  /// Priority + concurrency: what a task queue is for.
  Future<void> _queueSection(StringBuffer buffer) async {
    final queue = TaskManager(maxConcurrentTasks: 2)
      ..createAndQueue(id: TaskId('load-metadata'), type: TaskType.load, priority: TaskPriority.low)
      ..createAndQueue(id: TaskId('open-stream'), type: TaskType.open, priority: TaskPriority.highest)
      ..createAndQueue(id: TaskId('preload-next'), type: TaskType.prepare, priority: TaskPriority.low)
      ..createAndQueue(id: TaskId('resolve-source'), type: TaskType.prepare, priority: TaskPriority.high);

    buffer.writeln('TaskManager(maxConcurrentTasks: 2), four tasks queued (low, highest, low, high):');

    final timeline = <String>[];
    var clock = 0;

    while (queue.hasQueuedTasks || queue.hasRunningTasks) {
      final started = await queue.executeAvailable((task) async {
        final start = clock++;
        timeline.add('t$start start ${task.id} (${task.priority.name})');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        timeline.add('t$clock done  ${task.id}');
        return task.id.value;
      });

      if (started.isEmpty) {
        break;
      }
    }

    for (final line in timeline) {
      buffer.writeln('  $line');
    }

    buffer
      ..writeln('  → two at a time (the cap), highest priority first, resources released as slots free up')
      ..writeln(
        '  completed=${queue.completedCount} failed=${queue.failedCount} '
        'cancelled=${queue.cancelledCount}',
      )
      ..writeln();

    queue.dispose();
  }

  /// Serial execution: the guarantee that state does not interleave.
  Future<void> _serialSection(StringBuffer buffer) async {
    final serial = SerialExecutor();
    final order = <String>[];

    Future<void> step(String name, int milliseconds) async {
      order.add('$name begin');
      await Future<void>.delayed(Duration(milliseconds: milliseconds));
      order.add('$name end');
    }

    // Started together on purpose: `Future.wait` does not order them, the
    // executor does.
    await Future.wait(<Future<void>>[
      serial.execute(() => step('reconcile', 30)),
      serial.execute(() => step('apply-plan', 10)),
      serial.execute(() => step('emit', 5)),
    ]);

    buffer
      ..writeln('SerialExecutor, three operations started at once:')
      ..writeln('  ${order.join(' → ')}')
      ..writeln('  → never "begin/begin": each waits for the previous to finish.')
      ..writeln('  Serializing is what lets a module mutate its own state without a lock.')
      ..writeln();
  }

  /// Mutual exclusion: the failure it prevents.
  Future<void> _mutexSection(StringBuffer buffer) async {
    var unsafe = 0;
    var safe = 0;
    final mutex = Mutex();

    Future<void> incrementUnsafe() async {
      final current = unsafe;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      unsafe = current + 1;
    }

    Future<void> incrementSafe() {
      return mutex.protect(() async {
        final current = safe;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        safe = current + 1;
      });
    }

    await Future.wait(<Future<void>>[incrementUnsafe(), incrementUnsafe(), incrementUnsafe()]);
    await Future.wait(<Future<void>>[incrementSafe(), incrementSafe(), incrementSafe()]);

    buffer
      ..writeln('three concurrent increments:')
      ..writeln('  without a mutex: $unsafe (expected 3) — the read-modify-write raced')
      ..writeln('  with Mutex.protect: $safe (expected 3)')
      ..writeln();
  }

  /// Retry budget and backoff: two separate decisions.
  Future<void> _retrySection(StringBuffer buffer) async {
    var attempts = 0;

    buffer.writeln('RetryUtils.until(3) on an action that fails twice (3 attempts allowed):');

    final value = await RetryUtils.run(
      () async {
        attempts++;
        if (attempts < 3) {
          throw StateError('signed URL not ready yet');
        }
        return 'stream-$attempts';
      },
      delay: const Duration(milliseconds: 5),
      shouldRetry: RetryUtils.until(3),
    );

    buffer
      ..writeln('  attempts=$attempts → "$value"')
      ..writeln('  backoff sequence for attempts 1..5 (base 200ms, doubling, jittered):')
      ..writeln(
        '    ${<String>[for (var attempt = 1; attempt <= 5; attempt++) '${RetryUtils.backoff(attempt).inMilliseconds}ms'].join(', ')}',
      )
      ..writeln('  → a retry that waits is a retry that gives a transient outage time to clear;')
      ..writeln('    a retry that spins is how a retry budget gets spent in 200ms.');

    try {
      await RetryUtils.run<void>(
        () async => throw StateError('always broken'),
        maxAttempts: 2,
        shouldRetry: RetryUtils.never,
      );
    } on Object catch (error) {
      buffer.writeln('  RetryUtils.never stops after the first failure: $error');
    }
  }
}
