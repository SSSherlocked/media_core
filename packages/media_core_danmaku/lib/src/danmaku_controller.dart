import 'dart:async';

import 'package:media_core/media_core.dart';
import 'package:media_core_danmaku/src/danmaku_config.dart';
import 'package:media_core_danmaku/src/danmaku_failure.dart';
import 'package:media_core_danmaku/src/danmaku_filter_policy.dart';
import 'package:media_core_danmaku/src/danmaku_message.dart';
import 'package:media_core_danmaku/src/danmaku_message_gate.dart';
import 'package:media_core_danmaku/src/danmaku_repeated_filter.dart';
import 'package:media_core_danmaku/src/danmaku_session_state.dart';
import 'package:media_core_danmaku/src/danmaku_similarity_filter.dart';
import 'package:media_core_danmaku/src/danmaku_sink.dart';
import 'package:media_core_danmaku/src/danmaku_transport.dart';
import 'package:rxdart/rxdart.dart';

/// Owns exactly one room-bound danmaku session.
///
/// Responsibilities:
///
/// - install and replace the transport for a room
/// - serialize every connect/stop transition
/// - guard callbacks so an old socket can never append to a new room
/// - run the message pipeline (gate, policy, repeated filter, similarity)
/// - expose session state and failures
///
/// It does not:
///
/// - speak any platform protocol
/// - render, queue or store messages
/// - translate notices
/// - decide whether danmaku should be enabled at all
///
/// Those responsibilities belong to:
///
/// - DanmakuTransport (protocol)
/// - DanmakuSink (presentation)
/// - the host application (settings policy)
///
/// ## Why every transition is serialized
///
/// Room switches, setting changes, player reloads and floating-window teardown
/// can arrive in the same event-loop turn. Two unsequenced handshakes would
/// race to own the room, and the loser's socket would keep delivering packets
/// that look current. Every public transition therefore appends to a single
/// operation tail, and every operation re-checks a request epoch before it
/// acts.
///
/// ## Why every callback carries a token
///
/// A transport that is being replaced may still deliver a farewell packet
/// after the new room is live. Each accepted session increments
/// [_sessionToken]; the listener handed to a transport captures the token it
/// was started with, and any callback whose token, transport identity or room
/// key no longer matches the current session is dropped. This is deliberately
/// the same shape as the framework's generation guard for playback: identity
/// plus generation, never a bare "is connected" boolean.
final class DanmakuController {
  /// Creates a controller for one room, writing accepted messages to [sink]
  /// and reading credentials through [authProvider] when a handshake needs
  /// them.
  DanmakuController({
    DanmakuSink sink = const DanmakuNullSink(),
    DanmakuConfig config = DanmakuConfig.defaults,
    this.policy = DanmakuFilterPolicy.none,
    DanmakuAuth Function(DanmakuRoomRef room)? authProvider,
  }) : _sink = sink,
       _config = config,
       _authProvider = authProvider,
       _gate = DanmakuMessageGate(
         fallbackDuplicateWindow: config.fallbackDuplicateWindow,
         stableIdWindow: config.stableIdWindow,
         maxMessageAge: config.maxMessageAge,
         maxEntries: config.maxGateEntries,
       ),
       _repeatedFilter = DanmakuRepeatedFilter(maxEntries: config.maxRepeatedEntries),
       _similarityFilter = DanmakuSimilarityFilter(
         similarityThreshold: config.similarityThreshold,
         cacheDuration: config.similarityCacheDuration,
         maxCacheSize: config.similarityMaxCacheSize,
         maxComparisons: config.similarityMaxComparisons,
       );

  final DanmakuSink _sink;
  final DanmakuAuth Function(DanmakuRoomRef room)? _authProvider;

  DanmakuConfig _config;

  /// The viewer block policy applied to incoming chat.
  ///
  /// Not retained in any cache, so assigning a new one takes effect on the next
  /// message without touching the session.
  DanmakuFilterPolicy policy;

  final DanmakuMessageGate _gate;
  final DanmakuRepeatedFilter _repeatedFilter;
  final DanmakuSimilarityFilter _similarityFilter;

  final BehaviorSubject<DanmakuSessionState> _stateSubject = BehaviorSubject<DanmakuSessionState>.seeded(
    const DanmakuSessionState(),
  );
  final PublishSubject<DanmakuFailure> _failureSubject = PublishSubject<DanmakuFailure>();

  DanmakuTransport? _transport;

  /// Serializes connect/stop/replace with the core's serial executor.
  ///
  /// A failed transition is reported to its caller and to the failure stream,
  /// and the executor keeps going: one bad transition must not stall the next.
  final SerialExecutor _operations = SerialExecutor();

  /// Invalidates every queued operation. Incremented before each request.
  int _requestEpoch = 0;

  /// Identity of the current session. Incremented whenever a session is
  /// accepted or torn down.
  int _sessionToken = 0;

  /// Room key of the accepted session, or `null` when nothing owns the room.
  String? _sessionKey;

  /// Room key of an in-flight handshake.
  String? _connectingKey;

  /// Room of the in-flight handshake, kept for the room id reported on ready.
  DanmakuRoomRef? _connectingRoom;

  /// Room key the filters' current windows belong to.
  String? _gateRoomKey;

  Timer? _heartbeatTimer;

  /// Whether the accepted session has declared itself up.
  ///
  /// Distinct from the socket state: a platform with no chat integration
  /// settles locally by reporting readiness without opening anything, and that
  /// session must stop being retried exactly like a connected one.
  bool _sessionReady = false;

  String? _lastNoticeKey;
  DateTime? _lastNoticeAt;
  bool _maskedNameNoticed = false;

  bool _disposed = false;

  /// Current session snapshot.
  DanmakuSessionState get state => _stateSubject.value;

  /// Session snapshots, starting with the current one.
  Stream<DanmakuSessionState> get onStateChanged => _stateSubject.stream;

  /// Failures, in arrival order.
  Stream<DanmakuFailure> get onFailure => _failureSubject.stream;

  /// Installed transport, or `null`.
  DanmakuTransport? get transport => _transport;

  /// Whether a transport is installed.
  bool get isInstalled => _transport != null;

  /// Whether the current session is attached and delivering.
  ///
  /// False for a locally settled session (no socket) — use
  /// [isSessionEstablished] for "the session is up, whatever its transport".
  bool get isConnected => _sessionReady && (_transport?.isConnected ?? false);

  /// Whether the current session declared itself up, socket or not.
  bool get isSessionEstablished => _sessionReady;

  /// Whether a session is being established.
  bool get isConnecting => _connectingKey != null;

  /// Session key currently owned, or `null`.
  String? get sessionKey => _sessionKey;

  /// Installs [transport].
  ///
  /// The first installation is synchronous by design: room initialization must
  /// not race ahead of dependency setup, so a caller that installs and then
  /// immediately connects sees the transport in place. Replacing an installed
  /// transport is asynchronous — it has to tear the old session down first —
  /// and is reported through [onStateChanged] and [onFailure].
  void installTransport(DanmakuTransport transport) {
    final current = _transport;
    if (current == null) {
      _transport = transport;
      _emit(state.copyWith(installed: true, transportId: transport.id));
      return;
    }
    unawaited(replaceTransport(transport));
  }

  /// Replaces the installed transport, tearing down the current session.
  ///
  /// Filters are cleared because their windows describe the previous
  /// transport's traffic; carrying them over would suppress the new session's
  /// first messages based on ids and texts that no longer apply.
  Future<void> replaceTransport(DanmakuTransport transport) {
    final request = ++_requestEpoch;
    return _serialize(() async {
      if (request != _requestEpoch) return;
      await _disconnectInternal(clearRenderer: true);
      if (request != _requestEpoch) return;
      _transport = transport;
      _clearFilters();
      _gateRoomKey = null;
      _emit(state.copyWith(installed: true, transportId: transport.id));
    });
  }

  /// Whether [room] needs a (re)connect.
  ///
  /// A matching, settled session does not. A matching session that is still
  /// connecting does not either — the caller's intent is already being served.
  bool needReconnect(DanmakuRoomRef room) {
    if (!isInstalled) return true;
    final key = room.key;
    if (_connectingKey == key) return false;
    return _sessionKey != key || !_sessionSettled;
  }

  /// Attaches to [room].
  ///
  /// A matching, connected session survives a presentation-only change such as
  /// entering picture-in-picture: tearing down a healthy socket there would
  /// create a guaranteed gap. A matching but disconnected session is rebuilt
  /// without clearing the rendered history. Pass [force] to rebuild regardless.
  Future<void> connect(DanmakuRoomRef room, {bool force = false}) {
    final key = room.key;
    if (!isInstalled || _disposed) return Future<void>.value();

    // The fast path is deliberately before the epoch increment: a duplicate
    // lifecycle request must not invalidate an in-flight handshake merely to
    // rediscover the same key inside the serialized body.
    if (!force && ((_sessionKey == key && _sessionSettled) || _connectingKey == key)) {
      return Future<void>.value();
    }

    final request = ++_requestEpoch;
    return _serialize(() async {
      if (request != _requestEpoch || !isInstalled) return;

      final stillHealthy = _sessionKey == key && _sessionSettled;
      if (!force && (stillHealthy || _connectingKey == key)) return;

      final previousKey = _sessionKey ?? _connectingKey;
      // Rendered history is only dropped when the room actually changes: a
      // reconnect inside one room keeps what is already on screen.
      await _disconnectInternal(
        clearRenderer: previousKey != null && previousKey != key,
        tearDownTransport: previousKey != null,
      );
      if (request != _requestEpoch || !isInstalled) return;

      if (_gateRoomKey != key) {
        _clearFilters();
        _gateRoomKey = key;
      }

      final transport = _transport;
      if (transport == null) return;

      final token = ++_sessionToken;
      _maskedNameNoticed = false;
      _connectingKey = key;
      _connectingRoom = room;
      _emit(
        state.copyWith(
          phase: DanmakuSessionPhase.connecting,
          roomKey: key,
          roomId: room.roomId,
          platform: room.platform,
          transportId: transport.id,
          generation: token,
          clearFailure: true,
        ),
      );
      _notice(DanmakuNotice.connecting);

      try {
        await transport
            .start(
              request: DanmakuTransportRequest(room: room, auth: _authProvider?.call(room) ?? const DanmakuAuth.none()),
              listener: _SessionListener(this, transport, key, token),
            )
            .timeout(_config.startTimeout);
      } on Object catch (error, stackTrace) {
        final timedOut = error is TimeoutException;
        _reportFailure(
          kind: timedOut ? DanmakuFailureKind.startTimeout : DanmakuFailureKind.startRejected,
          message: timedOut
              ? 'Transport did not confirm readiness within ${_config.startTimeout.inSeconds}s'
              : 'Transport rejected the start request',
          roomKey: key,
          transportId: transport.id,
          cause: error,
          stackTrace: stackTrace,
        );
        if (_accepts(transport, key, token)) {
          _connectingKey = null;
          _connectingRoom = null;
          _sessionKey = null;
          _sink.onRoomChanged(null);
          _emit(state.copyWith(phase: DanmakuSessionPhase.failed, clearRoom: true, generation: token));
        }
        await _stopTransport(transport);
        if (timedOut) _notice(DanmakuNotice.connectionTimeout);
        return;
      }

      if (request != _requestEpoch || !_accepts(transport, key, token)) {
        // A newer transition won while the handshake was in flight. The socket
        // this operation opened is nobody's now, so it is released here rather
        // than left running behind the new session's back.
        await _stopTransport(transport);
      }
    });
  }

  /// Detaches the current session.
  ///
  /// [clearRenderer] drops the rendered history; it is false for a same-room
  /// reconnect, where the visible messages are still valid.
  Future<void> stop({bool clearRenderer = true}) {
    final request = ++_requestEpoch;
    return _serialize(() async {
      if (request != _requestEpoch) return;
      await _disconnectInternal(clearRenderer: clearRenderer);
    });
  }

  /// Re-attaches a room after a presentation or lifecycle change.
  ///
  /// Host enablement policy stays authoritative: a host that paused danmaku
  /// calls [stop] instead, so recovery can never open a socket the viewer
  /// turned off.
  Future<void> recover(DanmakuRoomRef room, {bool enabled = true}) {
    if (_disposed) return Future<void>.value();
    if (!enabled) return stop();
    return connect(room);
  }

  /// Applies a new configuration.
  ///
  /// Gate windows are rebuilt: an entry's window is fixed at the time it is
  /// stored, so changing the windows in place would leave previously accepted
  /// entries judged by the old rule. Filter caches are preserved — their
  /// contents describe traffic, not policy — and are reconfigured in place.
  void updateConfig(DanmakuConfig config) {
    _config = config;
    _gate.applyWindows(
      fallbackDuplicateWindow: config.fallbackDuplicateWindow,
      stableIdWindow: config.stableIdWindow,
      maxMessageAge: config.maxMessageAge,
      maxEntries: config.maxGateEntries,
    );
    _similarityFilter.updateConfig(
      similarityThreshold: config.similarityThreshold,
      cacheDuration: config.similarityCacheDuration,
      maxCacheSize: config.similarityMaxCacheSize,
    );
    if (!config.similarityFilterEnabled) _similarityFilter.clear();
  }

  /// Releases the controller: stops the session, then closes its streams.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final request = ++_requestEpoch;
    await _serialize(() async {
      if (request != _requestEpoch) return;
      await _disconnectInternal(clearRenderer: true);
    });
    _clearFilters();
    await DisposeUtils.close(_failureSubject);
    await DisposeUtils.close(_stateSubject);
  }

  // ---------------------------------------------------------------------------
  // Transport callbacks
  // ---------------------------------------------------------------------------

  /// Whether a callback from [transport] still belongs to the current session.
  ///
  /// Three checks, all required: the token the session was started with, the
  /// identity of the transport that is installed now, and the room key being
  /// either the accepted one or the one currently connecting. An old socket
  /// fails at least one of them.
  bool _accepts(DanmakuTransport transport, String key, int token) {
    return token == _sessionToken && identical(_transport, transport) && (_sessionKey == key || _connectingKey == key);
  }

  void _handleReady(DanmakuTransport transport, String key, int token) {
    if (!_accepts(transport, key, token)) return;
    final room = _connectingRoom;
    _connectingKey = null;
    _connectingRoom = null;
    _sessionKey = key;
    _sessionReady = true;
    _sink.onRoomChanged(room?.roomId);
    _notice(DanmakuNotice.connected);
    _emit(
      state.copyWith(
        phase: DanmakuSessionPhase.connected,
        roomKey: key,
        roomId: room?.roomId,
        platform: room?.platform,
        transportId: transport.id,
        generation: token,
        clearFailure: true,
      ),
    );
    _startHeartbeat(transport, key, token);
  }

  void _handleMessage(DanmakuMessage message) {
    switch (message.type) {
      case DanmakuMessageType.chat:
        // Order matters and is the reference pipeline's order: cheapest and
        // most decisive first. The gate rejects what already arrived, the
        // policy rejects what the viewer never wants to see, and only then do
        // the two content filters look at the text.
        if (!_gate.accepts(message)) return;
        if (!policy.allows(message)) return;
        if (!_repeatedFilter.accepts(
          message,
          enabled: _config.repeatedFilterEnabled,
          window: _config.repeatedFilterWindow,
        )) {
          return;
        }
        // Similarity is a viewer-facing nicety, so the viewer's own echo is
        // exempt: they must always see what they sent.
        if (!message.isLocal && _config.similarityFilterEnabled && !_similarityFilter.shouldDisplay(message.text)) {
          return;
        }
        _reportMaskedNameOnce(message);
        _sink.onDanmaku(message);

      case DanmakuMessageType.audience:
        final update = message.audience;
        if (update != null) _sink.onAudienceUpdate(update);

      case DanmakuMessageType.superChat:
        final card = message.superChat;
        if (card != null) _sink.onSuperChat(card);

      case DanmakuMessageType.system:
        // Locally composed text. It bypasses the filters: it was not sent by
        // the platform and must not be suppressed by rules aimed at viewers.
        _sink.onDanmaku(message, immediate: true);

      case DanmakuMessageType.gift:
        // Not routed. The reference pipeline renders no gift line, and
        // inventing a sink hook with no consumer would only be a promise the
        // module cannot keep. A host that needs gifts adds the hook here and
        // forwards to its own surface.
        break;
    }
  }

  void _handleReconnecting(DanmakuTransport transport, String key, int token, String message) {
    if (!_accepts(transport, key, token)) return;
    _emit(state.copyWith(phase: DanmakuSessionPhase.reconnecting, roomKey: key));
    _reportTransportNotice(message);
  }

  void _handleClosed(DanmakuTransport transport, String key, int token, String message) {
    if (!_accepts(transport, key, token)) return;
    // A terminal close releases the room key so a later connect builds a fresh
    // transport instead of reusing a dead socket.
    _sessionKey = null;
    _sessionReady = false;
    _connectingKey = null;
    _connectingRoom = null;
    _stopHeartbeat();
    _sink.onRoomChanged(null);
    _emit(state.copyWith(phase: DanmakuSessionPhase.closed, clearRoom: true, generation: token));
    _reportTransportNotice(message);
    _reportFailure(kind: DanmakuFailureKind.transportClosed, message: message, roomKey: key, transportId: transport.id);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// A session that declared itself up counts as settled. A transport that
  /// reports readiness without a socket (platform with no chat integration) is
  /// as settled as a connected one, and must not be retried forever.
  bool get _sessionSettled => _sessionReady;

  /// Ends the current session, releasing the installed transport.
  ///
  /// [tearDownTransport] is false only when the caller knows no session was
  /// established — the first connect after an install. Stopping a transport
  /// that was never started is allowed by its contract but is still work the
  /// transport did not ask for, and a transport with a meaningful teardown
  /// (dropping a token, logging a close) should not be told a session ended
  /// when none began.
  Future<void> _disconnectInternal({required bool clearRenderer, bool tearDownTransport = true}) async {
    final transport = _transport;
    // Increment first: every outstanding callback guard fails immediately,
    // before teardown awaits anything.
    _sessionToken++;
    _sessionKey = null;
    _sessionReady = false;
    _connectingKey = null;
    _connectingRoom = null;
    _stopHeartbeat();
    _sink.onRoomChanged(null);
    if (clearRenderer) _sink.clearRendered();
    _emit(state.copyWith(phase: DanmakuSessionPhase.closed, clearRoom: true, generation: _sessionToken));
    if (transport == null || !tearDownTransport) return;
    await _stopTransport(transport);
  }

  /// Teardown is never cancelled on timeout: a transport that is slow to
  /// release is still releasing, and abandoning it would leak the socket. The
  /// caller stops waiting; the transport keeps going.
  Future<void> _stopTransport(DanmakuTransport transport) async {
    try {
      await transport.stop().timeout(_config.stopTimeout);
    } on Object catch (error, stackTrace) {
      MediaCoreLog.warning(
        LogCategory.danmaku,
        'Transport teardown did not confirm within ${_config.stopTimeout.inSeconds}s',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'transport': transport.id},
      );
    }
  }

  /// The session schedules keep-alives so a transport does not need its own
  /// timer, which would keep running while the host is paused or backgrounded.
  /// A transport that manages its own heartbeat reports [Duration.zero] and is
  /// left alone.
  void _startHeartbeat(DanmakuTransport transport, String key, int token) {
    _stopHeartbeat();
    final interval = transport.heartbeatInterval;
    if (interval <= Duration.zero) return;
    _heartbeatTimer = Timer.periodic(interval, (_) {
      if (!_accepts(transport, key, token)) {
        _stopHeartbeat();
        return;
      }
      try {
        transport.heartbeat();
      } on Object catch (error, stackTrace) {
        // A failed keep-alive is not a session failure: the platform will
        // either answer the next one or close the socket, and the close is
        // what the session acts on.
        MediaCoreLog.warning(
          LogCategory.danmaku,
          'Danmaku heartbeat failed',
          error: error,
          stackTrace: stackTrace,
          fields: <String, Object?>{'transport': transport.id},
        );
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _clearFilters() {
    _gate.clear();
    _repeatedFilter.clear();
    _similarityFilter.clear();
  }

  /// Reports a masked platform display name once per session.
  ///
  /// The mask pattern itself is platform-independent, but whether it is worth
  /// telling the viewer depends on the platform — so the module only reports
  /// the observation and the host decides. The original implementation
  /// hard-coded this to one platform inside the session.
  void _reportMaskedNameOnce(DanmakuMessage message) {
    if (_maskedNameNoticed) return;
    if (!RegExp(r'\*{2,}|＊{2,}').hasMatch(message.userName)) return;
    _maskedNameNoticed = true;
    _notice(DanmakuNotice.maskedUserName);
  }

  /// Emits a notice, collapsing an immediate repeat.
  ///
  /// A reconnect storm would otherwise push the same line dozens of times; the
  /// window keeps one instance of a repeating notice while still allowing it
  /// again after the room has been quiet.
  void _notice(DanmakuNotice notice) {
    final now = DateTime.now();
    final key = notice.name;
    if (_lastNoticeKey == key && _lastNoticeAt != null && now.difference(_lastNoticeAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastNoticeKey = key;
    _lastNoticeAt = now;
    _sink.onNotice(notice);
  }

  /// Forwards transport text, collapsing an immediate repeat. See [_notice].
  void _reportTransportNotice(String message) {
    if (message.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastNoticeKey == message &&
        _lastNoticeAt != null &&
        now.difference(_lastNoticeAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastNoticeKey = message;
    _lastNoticeAt = now;
    _sink.onTransportNotice(message);
  }

  void _reportFailure({
    required DanmakuFailureKind kind,
    required String message,
    String? roomKey,
    String? transportId,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    if (_disposed) return;
    MediaCoreLog.warning(
      LogCategory.danmaku,
      message,
      error: cause,
      stackTrace: stackTrace,
      fields: <String, Object?>{'kind': kind.name, 'room': ?roomKey, 'transport': ?transportId},
    );
    final failure = DanmakuFailure(
      kind: kind,
      message: message,
      roomKey: roomKey,
      transportId: transportId,
      isRecoverable: kind != DanmakuFailureKind.startRejected,
      cause: cause,
    );
    if (!_failureSubject.isClosed) _failureSubject.add(failure);
  }

  void _emit(DanmakuSessionState next) {
    if (_stateSubject.isClosed) return;
    _stateSubject.add(next);
  }

  /// Appends [operation] to the serialized tail.
  ///
  /// The returned future carries the operation's own errors to its caller,
  /// while the tail itself absorbs them so a failed transition cannot stall
  /// every following one.
  Future<void> _serialize(Future<void> Function() operation) async {
    try {
      await _operations.execute(operation);
    } catch (error, stackTrace) {
      MediaCoreLog.error(LogCategory.danmaku, 'Danmaku session operation failed', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }
}

/// Listener handed to one transport start.
///
/// It captures the session identity at the moment of the start and forwards
/// only while that identity is still current. This is what replaces the
/// original's mutable callback fields: a transport cannot detach or replace
/// the listener, and a stale socket cannot address the controller at all.
final class _SessionListener implements DanmakuTransportListener {
  _SessionListener(this._owner, this._transport, this._key, this._token);

  final DanmakuController _owner;
  final DanmakuTransport _transport;
  final String _key;
  final int _token;

  @override
  void onDanmakuMessage(DanmakuMessage message) {
    if (!_owner._accepts(_transport, _key, _token)) return;
    _owner._handleMessage(message);
  }

  @override
  void onTransportReady() => _owner._handleReady(_transport, _key, _token);

  @override
  void onTransportReconnecting(String message) => _owner._handleReconnecting(_transport, _key, _token, message);

  @override
  void onTransportClosed(String message) => _owner._handleClosed(_transport, _key, _token, message);
}
