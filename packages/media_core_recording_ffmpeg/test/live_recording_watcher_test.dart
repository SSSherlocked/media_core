import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_recording_ffmpeg/media_core_recording_ffmpeg.dart';

/// The watch loop: ask the room, record while it says live, notice the end.
///
/// Timers are the subject here, so the intervals are milliseconds rather than the
/// default minute, and what a test asserts is *how many times the room was asked*
/// and *what the watcher did about the answer* — not a wall-clock duration.
void main() {
  late _FakeExecutor executor;
  late Directory output;
  late FfmpegRecordingBackend backend;

  setUp(() {
    executor = _FakeExecutor();
    output = Directory.systemTemp.createTempSync('media_core_recording_watcher');
    backend = FfmpegRecordingBackend(
      executor: executor,
      // Without a directory every start throws before the executor is asked, and
      // the loop under test then only ever sees failed starts.
      outputDirectory: output.path,
      // One process, no verdict: these tests are about the loop around a
      // recording, and the loop's own decisions must not wait on file checks.
      config: const FfmpegRecordConfig(filePrefix: 'room', restartLimit: 0, verifyOutput: false),
    );
    addTearDown(backend.dispose);
    addTearDown(() => output.deleteSync(recursive: true));
  });

  /// Lets the timers, polls and state events run.
  Future<void> settle([int milliseconds = 150]) => Future<void>.delayed(Duration(milliseconds: milliseconds));

  FfmpegLiveRecordingWatcher watching({
    required List<FfmpegLiveRoomStatus> answers,
    void Function(FfmpegLiveRecordingSession)? onLiveStart,
    void Function(FfmpegLiveRecordingSession)? onLiveEnd,
    int maxConsecutiveProbeFailures = 5,
  }) {
    final watcher = FfmpegLiveRecordingWatcher(
      backend: backend,
      statusProbe: (source) async {
        final index = executor.probeCount;
        executor.probeCount = index + 1;

        if (index >= answers.length) {
          return answers.last;
        }

        return answers[index];
      },
      pollInterval: const Duration(milliseconds: 40),
      recheckInterval: const Duration(milliseconds: 20),
      maxConsecutiveProbeFailures: maxConsecutiveProbeFailures,
      onLiveStart: onLiveStart,
      onLiveEnd: onLiveEnd,
    );
    addTearDown(watcher.dispose);

    return watcher;
  }

  const offline = FfmpegLiveRoomStatus.offline();
  FfmpegLiveRoomStatus live({String? url}) => FfmpegLiveRoomStatus.live(url ?? 'https://e.com/live.flv');

  test('a room that is not live yet is waited for, not recorded', () async {
    var starts = 0;
    final watcher = watching(answers: <FfmpegLiveRoomStatus>[offline, offline, live()], onLiveStart: (_) => starts++);

    await watcher.watch(const RecordingSource.network('https://e.com/room.flv', id: 'room-1'));

    expect(executor.argumentLists, isEmpty);
    expect(watcher.isRecording, isFalse);

    await settle(300);

    expect(starts, 1, reason: 'one notification per live session, not one per poll');
    expect(executor.argumentLists, hasLength(1));
    expect(watcher.isRecording, isTrue);
  });

  test('the address the status probe resolved is the one recorded', () async {
    final watcher = watching(answers: <FfmpegLiveRoomStatus>[live(url: 'https://cdn.e.com/fresh.flv?sign=2')]);

    await watcher.watch(const RecordingSource.network('https://api.e.com/room.flv', id: 'room-1'));
    await settle();

    final arguments = executor.argumentLists.single;

    expect(
      arguments[arguments.indexOf('-i') + 1],
      'https://cdn.e.com/fresh.flv?sign=2',
      reason: 'the probe already paid for the fresh signed address; asking twice invites the second to expire',
    );
  });

  test('the room title is what the recording is named after', () async {
    final watcher = watching(
      answers: <FfmpegLiveRoomStatus>[const FfmpegLiveRoomStatus.live('https://e.com/live.flv', title: '主播8891')],
    );

    await watcher.watch(const RecordingSource.network('https://api.e.com/room.flv', id: 'room-1'));
    await settle();

    final arguments = executor.argumentLists.single;

    expect(
      arguments.last,
      endsWith('主播8891_%06d.clock-v1.ts'),
      reason: 'the watcher knows the title from the status probe; a file named `room` says nothing weeks later',
    );
  });

  test('the session starts once and ends once, with what was recorded', () async {
    final started = <FfmpegLiveRecordingSession>[];
    final ended = <FfmpegLiveRecordingSession>[];
    final watcher = watching(
      // The second answer arrives after the recording has ended: the room closed
      // as the stream did, which is what ends the session.
      answers: <FfmpegLiveRoomStatus>[live(), offline],
      onLiveStart: started.add,
      onLiveEnd: ended.add,
    );

    await watcher.watch(const RecordingSource.network('https://e.com/room.flv'));
    await settle();

    expect(started, hasLength(1));
    expect(ended, isEmpty, reason: 'a room that stays live is not a session that ended');

    executor.executions.single.finish(0);
    await settle(300);

    expect(ended, hasLength(1));
    expect(ended.single.recordings, hasLength(1));
    expect(ended.single.recordings.single.success, isTrue);
    expect(watcher.session?.endedAt, isNotNull);
  });

  test('a recording that ended in seconds is looked at again soon', () async {
    var asked = 0;
    final watcher = FfmpegLiveRecordingWatcher(
      backend: backend,
      statusProbe: (source) async {
        asked++;

        return asked == 1 ? live() : offline;
      },
      pollInterval: const Duration(seconds: 30),
      recheckInterval: const Duration(milliseconds: 20),
      shortRecordingAfter: const Duration(seconds: 5),
    );
    addTearDown(watcher.dispose);

    await watcher.watch(const RecordingSource.network('https://e.com/room.flv'));
    executor.executions.single.finish(255);

    // 30 seconds of waiting for the next question would miss the restart; the
    // short re-check has to be what happens instead.
    await settle(200);

    expect(asked, greaterThan(2), reason: 'an almost-start is re-checked on the short interval');
  });

  test('a probe that keeps failing ends the watch instead of hammering the endpoint', () async {
    var asked = 0;
    final watcher = FfmpegLiveRecordingWatcher(
      backend: backend,
      statusProbe: (source) async {
        asked++;

        throw StateError('the room API answered 503');
      },
      pollInterval: const Duration(milliseconds: 20),
      // A failing endpoint is waited for on the short interval too, so the limit
      // is reachable inside the test's own settle window.
      recheckInterval: const Duration(milliseconds: 20),
      maxConsecutiveProbeFailures: 3,
    );
    addTearDown(watcher.dispose);

    await watcher.watch(const RecordingSource.network('https://e.com/room.flv'));
    await settle(400);

    expect(asked, 3, reason: 'it gives up at the limit rather than polling a broken endpoint forever');
    expect(watcher.lastError, isA<StateError>());
    expect(executor.argumentLists, isEmpty);
  });

  test('a start that fails is retried on the next poll', () async {
    final failing = _FakeExecutor()..refuseStarts = 1;
    final flaky = FfmpegRecordingBackend(
      executor: failing,
      outputDirectory: output.path,
      config: const FfmpegRecordConfig(filePrefix: 'room', restartLimit: 0, verifyOutput: false),
    );
    addTearDown(flaky.dispose);

    final watcher = FfmpegLiveRecordingWatcher(
      backend: flaky,
      statusProbe: (source) async => live(),
      pollInterval: const Duration(milliseconds: 30),
      // The failed start counts as an almost-start, so it is the short interval
      // that decides when the room is asked again.
      recheckInterval: const Duration(milliseconds: 30),
    );
    addTearDown(watcher.dispose);

    await watcher.watch(const RecordingSource.network('https://e.com/room.flv'));
    await settle(300);

    expect(failing.startCalls, greaterThanOrEqualTo(2), reason: 'the room is live; one failed start is not a verdict');
    expect(failing.argumentLists, hasLength(1), reason: 'the retry is the one that is running, not a second process');
    expect(watcher.isRecording, isTrue);
  });

  test('stopping the watcher ends the recording it started', () async {
    final watcher = watching(answers: <FfmpegLiveRoomStatus>[live()]);

    await watcher.watch(const RecordingSource.network('https://e.com/room.flv'));
    await settle();

    await watcher.stop();

    expect(executor.executions.single.stopCalled, isTrue);
    expect(watcher.session?.endedAt, isNotNull);
    expect(watcher.session?.recordings, hasLength(1));
  });

  test('one watcher watches one room at a time', () async {
    final watcher = watching(answers: <FfmpegLiveRoomStatus>[offline]);

    await watcher.watch(const RecordingSource.network('https://e.com/a.flv'));

    await expectLater(watcher.watch(const RecordingSource.network('https://e.com/b.flv')), throwsA(isA<StateError>()));
    expect(watcher.source?.value, 'https://e.com/a.flv', reason: 'the refused call did not take the room over');
  });
}

/// An FFmpeg process list that records what was asked of it.
final class _FakeExecutor implements FfmpegExecutor {
  final List<List<String>> argumentLists = <List<String>>[];
  final List<_FakeExecution> executions = <_FakeExecution>[];

  /// How many times the status probe has been asked (the watcher reads this).
  int probeCount = 0;

  /// How many processes were asked for, including the ones refused.
  ///
  /// [argumentLists] can only ever show the ones that started, so a retry that
  /// succeeded after a refusal is invisible in it.
  int startCalls = 0;

  /// How many more starts to refuse before letting one through.
  int refuseStarts = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<FfmpegExecution> start({
    required List<String> arguments,
    void Function(FfmpegStatistics statistics)? onStatistics,
    void Function(String message)? onLog,
  }) async {
    startCalls++;

    if (refuseStarts > 0) {
      refuseStarts--;

      throw StateError('the engine refused to start');
    }

    argumentLists.add(arguments);
    final execution = _FakeExecution();
    executions.add(execution);
    return execution;
  }

  @override
  Future<void> dispose() async {}
}

final class _FakeExecution implements FfmpegExecution {
  final Completer<int> _exit = Completer<int>();

  bool stopCalled = false;

  @override
  bool get isRunning => !_exit.isCompleted;

  @override
  Future<int> get exitCode => _exit.future;

  void finish(int code) {
    if (!_exit.isCompleted) {
      _exit.complete(code);
    }
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
    finish(255);
  }

  @override
  Future<void> cancel() async => finish(255);
}
