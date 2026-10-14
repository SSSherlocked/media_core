import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_danmaku/media_core_danmaku.dart';

final class _FakeTransport implements DanmakuTransport {
  _FakeTransport({this.id = 'fake', this.heartbeatInterval = Duration.zero});

  @override
  final String id;

  @override
  final Duration heartbeatInterval;

  int startCount = 0;
  int stopCount = 0;
  int heartbeatCount = 0;
  Error? startError;
  Completer<void>? startGate;
  DanmakuTransportListener? listener;
  DanmakuTransportRequest? request;

  @override
  bool isConnected = false;

  @override
  Future<void> start({required DanmakuTransportRequest request, required DanmakuTransportListener listener}) async {
    startCount++;
    this.request = request;
    this.listener = listener;
    final gate = startGate;
    if (gate != null) await gate.future;
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    isConnected = false;
  }

  @override
  void heartbeat() => heartbeatCount++;
}

final class _RecordingSink implements DanmakuSink {
  final List<DanmakuMessage> messages = <DanmakuMessage>[];
  final List<DanmakuNotice> notices = <DanmakuNotice>[];
  final List<String> transportNotices = <String>[];
  final List<DanmakuSuperChat> superChats = <DanmakuSuperChat>[];
  final List<DanmakuAudienceUpdate> audienceUpdates = <DanmakuAudienceUpdate>[];
  final List<String?> roomIds = <String?>[];
  int clearCount = 0;

  @override
  void onDanmaku(DanmakuMessage message, {bool immediate = false}) => messages.add(message);

  @override
  void onAudienceUpdate(DanmakuAudienceUpdate update) => audienceUpdates.add(update);

  @override
  void onSuperChat(DanmakuSuperChat message) => superChats.add(message);

  @override
  void onNotice(DanmakuNotice notice) => notices.add(notice);

  @override
  void onTransportNotice(String message) => transportNotices.add(message);

  @override
  void onRoomChanged(String? roomId) => roomIds.add(roomId);

  @override
  void clearRendered() => clearCount++;
}

DanmakuMessage chat({String text = 'hello', String user = 'viewer', String id = '', bool isLocal = false}) {
  return DanmakuMessage(type: DanmakuMessageType.chat, userName: user, text: text, messageId: id, isLocal: isLocal);
}

const _roomA = DanmakuRoomRef(platform: 'siteA', roomId: '100');
const _roomB = DanmakuRoomRef(platform: 'siteB', roomId: '200');

void main() {
  group('DanmakuController', () {
    late _RecordingSink sink;
    late _FakeTransport transport;
    late DanmakuController controller;

    setUp(() {
      sink = _RecordingSink();
      transport = _FakeTransport();
      controller = DanmakuController(sink: sink);
    });

    tearDown(() => controller.dispose());

    Future<void> connectAndReady(DanmakuRoomRef room, _FakeTransport source) async {
      await controller.connect(room);
      source.isConnected = true;
      source.listener!.onTransportReady();
    }

    test('starts idle and installs no transport by default', () {
      expect(controller.isInstalled, isFalse);
      expect(controller.state.phase, DanmakuSessionPhase.idle);
      expect(controller.needReconnect(_roomA), isTrue);
    });

    test('installTransport is synchronous for the first transport', () {
      controller.installTransport(transport);

      expect(controller.isInstalled, isTrue);
      expect(controller.state.installed, isTrue);
      expect(controller.state.transportId, 'fake');
    });

    test('connect without a transport is a no-op', () async {
      await controller.connect(_roomA);

      expect(transport.startCount, 0);
      expect(controller.state.roomKey, isNull);
    });

    test('a settled session reports ready and publishes the room id', () async {
      controller.installTransport(transport);

      await connectAndReady(_roomA, transport);

      expect(controller.state.phase, DanmakuSessionPhase.connected);
      expect(controller.isSessionEstablished, isTrue);
      expect(controller.isConnected, isTrue);
      expect(sink.roomIds.contains('100'), isTrue);
      expect(sink.notices, contains(DanmakuNotice.connected));
      expect(controller.needReconnect(_roomA), isFalse);
    });

    test('a locally settled transport counts as settled without a socket', () async {
      // A platform with no chat integration reports readiness and never opens
      // anything; that session must not be retried forever.
      controller.installTransport(transport);

      await controller.connect(_roomA);
      transport.listener!.onTransportReady();

      expect(controller.isSessionEstablished, isTrue);
      expect(controller.isConnected, isFalse);
      expect(controller.needReconnect(_roomA), isFalse);
      expect(transport.startCount, 1);
    });

    test('a duplicate connect on a settled room does not restart the transport', () async {
      controller.installTransport(transport);
      await connectAndReady(_roomA, transport);

      await controller.connect(_roomA);

      expect(transport.startCount, 1);
      expect(transport.stopCount, 0);
      expect(sink.clearCount, 0);
    });

    test('switching rooms tears the old session down and keeps one owner', () async {
      controller.installTransport(transport);
      await connectAndReady(_roomA, transport);

      final second = _FakeTransport(id: 'second');
      await controller.replaceTransport(second);
      await connectAndReady(_roomB, second);

      expect(transport.stopCount, greaterThanOrEqualTo(1));
      expect(controller.state.roomKey, _roomB.key);
      expect(controller.state.transportId, 'second');
      expect(sink.clearCount, greaterThanOrEqualTo(1));
    });

    test('a superseded session cannot deliver into the new room', () async {
      controller.installTransport(transport);
      await connectAndReady(_roomA, transport);
      final staleListener = transport.listener!;

      final second = _FakeTransport(id: 'second');
      await controller.replaceTransport(second);
      await connectAndReady(_roomB, second);

      final deliveredBefore = sink.messages.length;
      staleListener.onDanmakuMessage(chat(text: 'from the dead socket'));
      second.listener!.onDanmakuMessage(chat(text: 'from the live socket'));

      expect(sink.messages.length, deliveredBefore + 1);
      expect(sink.messages.last.text, 'from the live socket');
    });

    test('a superseded transport cannot report readiness for the new room', () async {
      controller.installTransport(transport);
      await connectAndReady(_roomA, transport);
      final staleListener = transport.listener!;

      final second = _FakeTransport(id: 'second');
      await controller.replaceTransport(second);
      await controller.connect(_roomB);

      staleListener.onTransportReady();

      // The connecting session reports the room it is for, but it has not
      // established anything yet — and the stale ready must not establish it.
      expect(controller.isSessionEstablished, isFalse, reason: 'the stale ready must not establish the new session');
      expect(controller.state.phase, DanmakuSessionPhase.connecting);

      second.isConnected = true;
      second.listener!.onTransportReady();
      expect(controller.state.roomKey, _roomB.key);
      expect(controller.isSessionEstablished, isTrue);
    });

    test('a terminal close releases the room so a later connect is fresh', () async {
      controller.installTransport(transport);
      await connectAndReady(_roomA, transport);

      transport.listener!.onTransportClosed('socket gone');

      expect(controller.state.phase, DanmakuSessionPhase.closed);
      expect(controller.state.roomKey, isNull);
      expect(controller.needReconnect(_roomA), isTrue);
      expect(sink.transportNotices, contains('socket gone'));
    });

    test('a start timeout fails the session and reports a recoverable failure', () async {
      final timeouts = <DanmakuFailure>[];
      controller.onFailure.listen(timeouts.add);
      controller.installTransport(transport);
      transport.startGate = Completer<void>();

      await controller.connect(_roomA);

      expect(controller.state.phase, DanmakuSessionPhase.failed);
      expect(controller.state.roomKey, isNull);
      expect(sink.notices, contains(DanmakuNotice.connectionTimeout));
      expect(timeouts.map((failure) => failure.kind), contains(DanmakuFailureKind.startTimeout));
    });

    test('a rejected start reports a non-recoverable failure', () async {
      final failures = <DanmakuFailure>[];
      controller.onFailure.listen(failures.add);
      controller.installTransport(transport);
      transport.startError = StateError('handshake refused');

      await controller.connect(_roomA);

      expect(controller.state.phase, DanmakuSessionPhase.failed);
      expect(failures.single.kind, DanmakuFailureKind.startRejected);
      expect(failures.single.isRecoverable, isFalse);
    });

    test('stop clears the rendered history and releases the room', () async {
      controller.installTransport(transport);
      await connectAndReady(_roomA, transport);

      await controller.stop();

      expect(controller.state.roomKey, isNull);
      expect(transport.stopCount, 1);
      expect(sink.clearCount, greaterThanOrEqualTo(1));
      expect(sink.roomIds.last, isNull);
    });

    test('recover with danmaku disabled stops instead of reconnecting', () async {
      controller.installTransport(transport);
      await connectAndReady(_roomA, transport);

      await controller.recover(_roomA, enabled: false);

      expect(transport.startCount, 1, reason: 'no new handshake while disabled');
      expect(controller.state.roomKey, isNull);
    });
  });

  group('DanmakuController pipeline', () {
    late _RecordingSink sink;
    late _FakeTransport transport;
    late DanmakuController controller;

    setUp(() {
      sink = _RecordingSink();
      transport = _FakeTransport();
      controller = DanmakuController(sink: sink)..installTransport(transport);
    });

    tearDown(() => controller.dispose());

    Future<void> ready() async {
      await controller.connect(_roomA);
      transport.isConnected = true;
      transport.listener!.onTransportReady();
    }

    test('delivers accepted chat', () async {
      await ready();

      transport.listener!.onDanmakuMessage(chat());

      expect(sink.messages.single.text, 'hello');
    });

    test('suppresses blocked keywords before anything reaches the sink', () async {
      await ready();
      controller.policy = DanmakuFilterPolicy(blockedKeywords: <String>['spoiler']);

      transport.listener!.onDanmakuMessage(chat(text: 'this is a SPOILER'));
      transport.listener!.onDanmakuMessage(chat(text: 'this is fine'));

      expect(sink.messages.single.text, 'this is fine');
    });

    test('suppresses blocked viewers case-insensitively', () async {
      await ready();
      controller.policy = DanmakuFilterPolicy(blockedUsers: <String>['  Troll ']);

      transport.listener!.onDanmakuMessage(chat(user: 'troll'));
      transport.listener!.onDanmakuMessage(chat(user: 'friend'));

      expect(sink.messages.single.userName, 'friend');
    });

    test('routes audience updates and paid messages separately', () async {
      await ready();

      transport.listener!.onDanmakuMessage(
        const DanmakuMessage(
          type: DanmakuMessageType.audience,
          userName: '',
          text: '',
          audience: DanmakuAudienceUpdate(kind: DanmakuAudienceKind.concurrentViewers, value: 4321),
        ),
      );
      transport.listener!.onDanmakuMessage(
        DanmakuMessage(
          type: DanmakuMessageType.superChat,
          userName: 'sponsor',
          text: 'keep it up',
          superChat: DanmakuSuperChat(
            userName: 'sponsor',
            text: 'keep it up',
            price: 30,
            startTime: DateTime(2026, 9, 26, 12),
            endTime: DateTime(2026, 9, 26, 12, 1),
            backgroundColor: '#FF0000',
            backgroundBottomColor: '#AA0000',
          ),
        ),
      );

      expect(sink.messages, isEmpty, reason: 'neither is a chat line');
      expect(sink.audienceUpdates.single.value, 4321);
      expect(sink.superChats.single.price, 30);
    });

    test('the viewer’s own echo bypasses similarity suppression', () async {
      await ready();

      // The gate and the exact-repeat filter both key on the text, so the echo
      // is tested with a *near* duplicate: only the similarity filter would
      // have rejected it, and it must not for the viewer's own send.
      transport.listener!.onDanmakuMessage(chat(text: 'same words'));
      transport.listener!.onDanmakuMessage(chat(text: 'same words!', isLocal: true));
      transport.listener!.onDanmakuMessage(chat(text: 'same words!'));

      expect(sink.messages.map((message) => message.text).toList(), <String>['same words', 'same words!']);
      expect(sink.messages.last.isLocal, isTrue);
    });

    test('a heartbeat is scheduled only when the transport asks for one', () async {
      await ready();
      expect(transport.heartbeatCount, 0, reason: 'interval zero means the transport self-schedules');

      final pulsing = _FakeTransport(id: 'pulsing', heartbeatInterval: const Duration(milliseconds: 5));
      final second = DanmakuController(sink: _RecordingSink());
      addTearDown(second.dispose);
      second.installTransport(pulsing);
      await second.connect(_roomB);
      pulsing.isConnected = true;
      pulsing.listener!.onTransportReady();

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(pulsing.heartbeatCount, greaterThan(0));
      await second.stop();
    });

    test('configuration changes keep the session attached', () async {
      await ready();

      controller.updateConfig(
        DanmakuConfig.defaults.copyWith(repeatedFilterEnabled: false, similarityFilterEnabled: false),
      );

      expect(controller.state.phase, DanmakuSessionPhase.connected);
      expect(transport.stopCount, 0);
    });
  });
}
