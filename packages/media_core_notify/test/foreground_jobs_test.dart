import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_native/media_core_native.dart'
    show BackgroundJobKind, BackgroundNotification, BackgroundProgress;
import 'package:media_core_notify/media_core_notify.dart';

/// The client this suite needs: the foreground calls and how many of each.
final class _ForegroundClient implements LocalNotificationClient {
  final List<NotifyEvent> started = <NotifyEvent>[];
  final List<NotifyEvent> updated = <NotifyEvent>[];
  final List<String> calls = <String>[];

  int get stopCount => calls.where((call) => call == 'stopForeground').length;

  @override
  Future<bool> configure(NotifySetup setup) async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Future<void> post(NotifyEvent event) async {}

  @override
  Future<void> dismiss(int id) async {}

  @override
  Future<void> startForeground(NotifyEvent event) async {
    calls.add('startForeground');

    started.add(event);
  }

  @override
  Future<void> updateForeground(NotifyEvent event) async {
    calls.add('updateForeground');

    updated.add(event);
  }

  @override
  Future<void> stopForeground() async {
    calls.add('stopForeground');
  }
}

BackgroundNotification _job(String title, String text, {BackgroundJobKind kind = BackgroundJobKind.download}) {
  return BackgroundNotification(
    title: title,
    text: text,
    kind: kind,
    progress: const BackgroundProgress.determinate(current: 1, total: 4),
  );
}

/// Runs [future] to its value inside the fake zone.
///
/// `fakeAsync` wants a **synchronous** callback: an async one hands back a future
/// nothing pumps, so the test waits on it until the 30 second timeout with the
/// zone already closed. Every step of this group resolves on microtasks — the
/// client is a fake, and the only timers are the ones a test elapses by hand — so
/// a flush is all an `await` costs here, and the check below is what keeps that
/// claim honest rather than assumed.
T _resolve<T>(FakeAsync async, Future<T> future) {
  late T value;
  var settled = false;
  unawaited(
    future.then((result) {
      value = result;
      settled = true;
    }),
  );
  async.flushMicrotasks();

  expect(settled, isTrue, reason: 'This step should need no timer, only the microtasks flushed above.');

  return value;
}

/// Runs a step that returns nothing, the way [_resolve] runs one that does.
void _settle(FakeAsync async, Future<void> future) {
  var settled = false;
  unawaited(future.whenComplete(() => settled = true));
  async.flushMicrotasks();

  expect(settled, isTrue, reason: 'This step should need no timer, only the microtasks flushed above.');
}

void main() {
  late _ForegroundClient client;

  setUp(() async {
    client = _ForegroundClient();
    ForegroundJobs.resetForTest();
    await MediaCoreNotify.enable(client: client);
  });

  tearDown(() {
    MediaCoreNotify.disable();
    ForegroundJobs.resetForTest();
  });

  group('several jobs, one line', () {
    test('the first job starts the line, and says nothing about the others', () {
      fakeAsync((async) {
        _resolve(async, ForegroundJobs.start(_job('正在下载', 'room-42 · 25%')));

        expect(client.started, hasLength(1));
        expect(client.updated, isEmpty, reason: 'a line that just opened has nothing to repaint');
        expect(client.started.single.tone, NotifyTone.progress);
        expect(client.started.single.channel.id, kNotifyChannelJobs.id);
        expect(client.started.single.body, 'room-42 · 25%');
        expect(ForegroundJobs.isShowingLine, isTrue);
      });
    });

    test('a second job joins the line instead of taking another service', () {
      fakeAsync((async) {
        _resolve(async, ForegroundJobs.start(_job('正在下载', 'room-42 · 25%')));
        _resolve(async, ForegroundJobs.start(_job('正在录制', 'room-7 · 00:12', kind: BackgroundJobKind.record)));

        expect(client.started, hasLength(1), reason: 'two foreground services would cancel each other');
        expect(ForegroundJobs.runningCount, 2);
        expect(ForegroundJobs.lineBody, 'room-7 · 00:12  (还有 1 个任务)');
      });
    });

    test('the newest job is what the line says', () {
      fakeAsync((async) {
        _resolve(async, ForegroundJobs.start(_job('正在下载', 'room-42 · 25%')));
        final recording = _resolve(async, ForegroundJobs.start(_job('正在录制', 'room-7 · 00:12')));

        async.elapse(const Duration(milliseconds: 1200));

        expect(client.updated.last.body, 'room-7 · 00:12  (还有 1 个任务)');

        _settle(async, recording.release());
        async.elapse(const Duration(milliseconds: 1200));

        expect(client.updated.last.body, 'room-42 · 25%', reason: 'the line falls back to what is left');
        expect(client.stopCount, 0, reason: 'one job ended, the other still needs the protection');
      });
    });

    test('releasing the last job ends the line once', () {
      fakeAsync((async) {
        final a = _resolve(async, ForegroundJobs.start(_job('A', 'a')));
        final b = _resolve(async, ForegroundJobs.start(_job('B', 'b')));

        _settle(async, a.release());
        _settle(async, b.release());

        expect(client.stopCount, 1);
        expect(ForegroundJobs.isShowingLine, isFalse);
        expect(ForegroundJobs.runningCount, 0);
        expect(ForegroundJobs.lineBody, isNull);
      });
    });
  });

  group('the line is reposted on a clock, not on byte reports', () {
    test('six updates inside one window become one repost', () {
      fakeAsync((async) {
        final handle = _resolve(async, ForegroundJobs.start(_job('正在下载', '0%')));

        // A download manager reports several times a second; a notification that
        // re-animates on every one is worse than a slightly stale one.
        for (var percent = 10; percent <= 60; percent += 10) {
          _settle(async, handle.update(_job('正在下载', '$percent%')));
        }

        async.elapse(const Duration(milliseconds: 500));

        expect(client.updated, isEmpty, reason: 'the window opened by start has not expired yet');

        async.elapse(const Duration(milliseconds: 700));

        expect(client.updated, hasLength(1));
        expect(client.updated.single.body, '60%', reason: 'the newest content survives, the intermediates do not');
      });
    });

    test('a quiet stretch posts nothing further', () {
      fakeAsync((async) {
        _resolve(async, ForegroundJobs.start(_job('正在下载', '30%')));

        async.elapse(const Duration(seconds: 5));

        expect(client.updated, isEmpty);
        expect(client.started, hasLength(1));
      });
    });

    test('an update after release cannot resurrect the line', () {
      fakeAsync((async) {
        final handle = _resolve(async, ForegroundJobs.start(_job('正在下载', '30%')));

        _settle(async, handle.release());
        _settle(async, handle.update(_job('正在下载', '90%')));

        async.elapse(const Duration(seconds: 3));

        expect(client.updated, isEmpty);
        expect(client.stopCount, 1);
        expect(ForegroundJobs.isShowingLine, isFalse);
      });
    });

    test('stopAll leaves no line behind', () {
      fakeAsync((async) {
        _resolve(async, ForegroundJobs.start(_job('A', 'a')));
        _resolve(async, ForegroundJobs.start(_job('B', 'b')));

        _settle(async, ForegroundJobs.stopAll());

        expect(client.stopCount, 1);
        expect(ForegroundJobs.runningCount, 0);
        expect(ForegroundJobs.isShowingLine, isFalse);
      });
    });
  });

  test('with no platform installed, starting a line is a silent no-op', () {
    fakeAsync((async) {
      MediaCoreNotify.disable();
      ForegroundJobs.resetForTest();

      final handle = _resolve(async, ForegroundJobs.start(_job('正在下载', '30%')));

      expect(handle.released, isFalse, reason: 'the job still holds a handle it can release');

      _settle(async, handle.release());

      expect(client.started, isEmpty);
      expect(client.stopCount, 0);
    });
  });
}
