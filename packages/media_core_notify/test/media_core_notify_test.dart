import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart' show MediaJobKind, MediaJobOutcome, MediaJobReporter, MediaJobReporting;
import 'package:media_core_native/media_core_native.dart' show BackgroundJobKind, BackgroundNotification;
import 'package:media_core_notify/media_core_notify.dart';

/// A reporter a host wrote itself, to show `disable` leaves what it did not install.
final class _HostReporter implements MediaJobReporter {
  final List<MediaJobOutcome> seen = <MediaJobOutcome>[];

  @override
  void report(MediaJobOutcome outcome) => seen.add(outcome);
}

/// A client that records what would have been shown.
///
/// The package's promise is that a notification can never break the job it
/// reports for, and that is only checkable against something that can refuse.
final class _RecordingClient implements LocalNotificationClient {
  final List<NotifyEvent> posted = <NotifyEvent>[];
  final List<int> dismissed = <int>[];
  final List<NotifyEvent> foregroundStarted = <NotifyEvent>[];
  final List<NotifyEvent> foregroundUpdated = <NotifyEvent>[];
  final List<String> calls = <String>[];

  NotifySetup? configuredWith;
  bool configureResult = true;
  bool permissionResult = true;
  Object? throwOn;

  bool get foregroundStopped => calls.contains('stopForeground');
  int get stopCount => calls.where((call) => call == 'stopForeground').length;

  void _maybeThrow(String what) {
    if (throwOn == what) {
      throw _Refused(what);
    }
  }

  @override
  Future<bool> configure(NotifySetup setup) async {
    calls.add('configure');
    _maybeThrow('configure');

    configuredWith = setup;

    return configureResult;
  }

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    _maybeThrow('requestPermission');

    return permissionResult;
  }

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Future<void> post(NotifyEvent event) async {
    calls.add('post');
    _maybeThrow('post');

    posted.add(event);
  }

  @override
  Future<void> dismiss(int id) async {
    calls.add('dismiss');
    _maybeThrow('dismiss');

    dismissed.add(id);
  }

  @override
  Future<void> startForeground(NotifyEvent event) async {
    calls.add('startForeground');
    _maybeThrow('startForeground');

    foregroundStarted.add(event);
  }

  @override
  Future<void> updateForeground(NotifyEvent event) async {
    calls.add('updateForeground');

    foregroundUpdated.add(event);
  }

  @override
  Future<void> stopForeground() async {
    calls.add('stopForeground');
  }
}

final class _Refused implements Exception {
  _Refused(this.what);

  final String what;
}

void main() {
  late _RecordingClient client;

  setUp(() {
    client = _RecordingClient();
    ForegroundJobs.resetForTest();
    MediaJobReporting.reset();
  });

  tearDown(() {
    MediaCoreNotify.disable();
    ForegroundJobs.resetForTest();
    MediaJobReporting.reset();
  });

  group('the facade refuses politely rather than loudly', () {
    test('nothing is posted before enable, and saying so is false', () async {
      final posted = await MediaCoreNotify.post(const NotifyEvent(title: '下载完成', body: 'room-42.ts'));

      expect(MediaCoreNotify.enabled, isFalse);
      expect(posted, isFalse);
      expect(client.posted, isEmpty);
    });

    test('enable installs the client and hands it the setup', () async {
      const setup = NotifySetup(androidSmallIcon: '@drawable/ic_stat_media_core_record');

      final ready = await MediaCoreNotify.enable(client: client, setup: setup);

      expect(ready, isTrue);
      expect(client.configuredWith, same(setup));
    });

    test('a platform that refuses configuration still leaves a usable facade', () async {
      client.configureResult = false;

      final ready = await MediaCoreNotify.enable(client: client);

      expect(ready, isFalse);
      expect(MediaCoreNotify.enabled, isTrue, reason: 'the client is installed; the platform is not there');

      // The job this event describes is unaffected by the missing notification.
      expect(client.calls, contains('configure'));
    });

    test('a client that throws is not allowed to reach the caller', () async {
      await MediaCoreNotify.enable(client: client);
      client.throwOn = 'post';

      final result = await MediaCoreNotify.post(const NotifyEvent(title: 'x'));

      expect(result, isFalse, reason: 'a refused notification is reported, not raised');
    });

    test('permission questions only run after enable', () async {
      expect(await MediaCoreNotify.requestPermission(), isFalse);

      await MediaCoreNotify.enable(client: client);

      expect(await MediaCoreNotify.requestPermission(), isTrue);
      expect(client.calls, contains('requestPermission'));
    });
  });

  group('events keep their meaning on the way through', () {
    test('a tone and a job kind survive to the client', () async {
      await MediaCoreNotify.enable(client: client);

      await MediaCoreNotify.post(
        const NotifyEvent(
          title: '录制中断',
          body: 'room-42 · 网络断开',
          tone: NotifyTone.failure,
          kind: BackgroundJobKind.record,
        ),
      );

      final event = client.posted.single;

      expect(event.tone, NotifyTone.failure);
      expect(event.kind, BackgroundJobKind.record);
      expect(event.channel.id, kNotifyChannelResults.id);
    });

    test('events without an id get distinct ones', () async {
      await MediaCoreNotify.enable(client: client);

      await MediaCoreNotify.post(const NotifyEvent(title: 'a'));
      await MediaCoreNotify.post(const NotifyEvent(title: 'b'));

      expect(client.posted.map((event) => event.id), hasLength(2));
      expect(client.posted[0].id, isNot(equals(client.posted[1].id)));
    });

    test('an id given by the caller is honoured, so progress becomes a result in place', () async {
      await MediaCoreNotify.enable(client: client);

      await MediaCoreNotify.post(const NotifyEvent(title: '下载中', id: 4242, tone: NotifyTone.progress));
      await MediaCoreNotify.post(const NotifyEvent(title: '下载完成', id: 4242, tone: NotifyTone.success));

      expect(client.posted.map((event) => event.id), <int?>[4242, 4242]);
      expect(client.posted.last.tone, NotifyTone.success);
    });

    test('dismiss addresses the id it is given', () async {
      await MediaCoreNotify.enable(client: client);

      await MediaCoreNotify.dismiss(99);

      expect(client.dismissed, <int>[99]);
    });
  });

  group('NotifyOn is the policy a host hands a module', () {
    test('nothing filters everything out', () async {
      await MediaCoreNotify.enable(client: client);

      final posted = await MediaCoreNotify.postOutcome(const NotifyEvent(title: '完成'), policy: NotifyOn.nothing);

      expect(posted, isFalse);
      expect(client.posted, isEmpty);
    });

    test('results filters out the start of a job', () async {
      await MediaCoreNotify.enable(client: client);

      expect(
        await MediaCoreNotify.postOutcome(const NotifyEvent(title: '开始下载'), policy: NotifyOn.results, isStart: true),
        isFalse,
      );

      expect(await MediaCoreNotify.postOutcome(const NotifyEvent(title: '下载完成'), policy: NotifyOn.results), isTrue);

      expect(client.posted.map((event) => event.title), <String>['下载完成']);
    });

    test('startsAndResults lets both through', () async {
      await MediaCoreNotify.enable(client: client);

      await MediaCoreNotify.postOutcome(
        const NotifyEvent(title: '开始下载'),
        policy: NotifyOn.startsAndResults,
        isStart: true,
      );
      await MediaCoreNotify.postOutcome(const NotifyEvent(title: '下载完成'), policy: NotifyOn.startsAndResults);

      expect(client.posted, hasLength(2));
    });
  });

  group('the job packages report through the core slot', () {
    test('enable installs a reporter and disable takes it back out', () async {
      expect(MediaJobReporting.reporter, isNull, reason: 'nothing is wired before the host says yes');

      await MediaCoreNotify.enable(client: client);

      expect(MediaJobReporting.reporter, isA<JobNotifications>());

      MediaCoreNotify.disable();

      expect(MediaJobReporting.reporter, isNull, reason: 'a host that tore down must not keep posting');
    });

    test('a reporter the host wrote is left where the host put it', () async {
      await MediaCoreNotify.enable(client: client);

      final own = _HostReporter();
      MediaJobReporting.reporter = own;
      MediaCoreNotify.disable();

      expect(MediaJobReporting.reporter, same(own), reason: "disable removes its own reporter, not the host's");
    });

    test('a finished download reaches the tray with the file it wrote', () async {
      await MediaCoreNotify.enable(client: client);

      MediaJobReporting.reporter!.report(
        const MediaJobOutcome(
          kind: MediaJobKind.download,
          label: 'room-42.mp4',
          success: true,
          bytesWritten: 3 * 1024 * 1024,
        ),
      );
      await pumpEventQueue();

      expect(client.posted, hasLength(1));
      expect(client.posted.single.title, '下载完成');
      expect(client.posted.single.body, 'room-42.mp4 · 3.0 MB');
      expect(client.posted.single.tone, NotifyTone.success);
      expect(client.posted.single.kind, BackgroundJobKind.download);
    });

    test('a recording that stopped early says so, and says how much it kept', () async {
      await MediaCoreNotify.enable(client: client);

      MediaJobReporting.reporter!.report(
        MediaJobOutcome(
          kind: MediaJobKind.recording,
          label: '主播8891',
          success: false,
          bytesWritten: 512 * 1024,
          elapsed: const Duration(minutes: 1, seconds: 5),
          error: StateError('the stream ended'),
        ),
      );
      await pumpEventQueue();

      expect(client.posted.single.title, '录制中断');
      expect(client.posted.single.tone, NotifyTone.failure);
      expect(client.posted.single.kind, BackgroundJobKind.record);
      expect(client.posted.single.body, contains('1:05'));
      expect(client.posted.single.body, contains('the stream ended'));
    });

    test('a host that muted job results still gets the running line', () async {
      await MediaCoreNotify.enable(client: client, jobOutcomes: NotifyOn.nothing);

      MediaJobReporting.reporter!.report(
        const MediaJobOutcome(kind: MediaJobKind.download, label: 'room-42.mp4', success: true),
      );
      await pumpEventQueue();

      expect(client.posted, isEmpty);

      final started = await ForegroundJobs.start(
        const BackgroundNotification(title: '正在下载', text: 'room-42', kind: BackgroundJobKind.download),
      );
      expect(started, isNotNull);
      expect(client.foregroundStarted, hasLength(1));
    });
  });
}
