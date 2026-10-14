import 'package:flutter/foundation.dart' show immutable;

import 'package:media_core_danmaku/src/danmaku_message.dart';

/// Identifies the room a transport attaches to.
///
/// [platform] is the caller's own platform identifier (a site key), not a
/// value this module interprets: the module never branches on it. It exists so
/// a session key can be formed and so a transport registry can pick the
/// implementation that handles that platform.
@immutable
final class DanmakuRoomRef {
  /// A room on a [platform], identified by its [roomId].
  const DanmakuRoomRef({required this.platform, required this.roomId});

  /// The caller's own platform identifier; this module never branches on it.
  final String platform;

  /// The platform's room id.
  final String roomId;

  /// Session key: two refs with the same key describe the same room.
  ///
  /// Room ids are compared trimmed and case-insensitively because platforms
  /// disagree on the casing of the same id across their API surfaces.
  String get key => '${platform.trim().toLowerCase()}:${roomId.trim().toLowerCase()}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DanmakuRoomRef && other.platform == platform && other.roomId == roomId);

  @override
  int get hashCode => Object.hash(platform, roomId);

  @override
  String toString() => 'DanmakuRoomRef($platform:$roomId)';
}

/// Viewer credentials a transport may need to send or to receive privileged
/// messages.
///
/// Everything is optional: many platforms serve anonymous read-only chat, and
/// a transport that needs more must say so by failing its `start`, not by
/// requiring the caller to guess.
final class DanmakuAuth {
  /// Credentials for a room, every field optional; an empty one is anonymous.
  const DanmakuAuth({this.userId = '', this.token = '', this.cookies = const <String, String>{}});

  /// No credentials: anonymous read-only chat.
  const DanmakuAuth.none() : userId = '', token = '', cookies = const <String, String>{};

  /// The sending viewer's id, empty for anonymous access.
  final String userId;

  /// Auth token the platform's send API requires, empty when none.
  final String token;

  /// Named cookies for platforms that authenticate through a session cookie.
  final Map<String, String> cookies;

  /// Whether no credential is present: an anonymous, read-only session.
  bool get isEmpty => userId.isEmpty && token.isEmpty && cookies.isEmpty;
}

/// Everything a transport needs to attach to one room.
///
/// [extras] is a deliberate escape hatch. Platform handshakes differ per site —
/// an app id, a device fingerprint, a signed timestamp — and this module cannot
/// enumerate them without becoming a catalog of platforms it promises never to
/// know about. The transport owns decoding [extras]; the module only carries it
/// so a caller can pass credentials without the framework inventing an
/// abstraction for each one.
final class DanmakuTransportRequest {
  /// Everything one transport needs to attach to [room]; [extras] is owned by
  /// the transport and never interpreted by this module.
  DanmakuTransportRequest({
    required this.room,
    this.auth = const DanmakuAuth.none(),
    Map<String, Object?> extras = const <String, Object?>{},
  }) : extras = Map<String, Object?>.unmodifiable(extras);

  /// The room to attach to.
  final DanmakuRoomRef room;

  /// Credentials to send with, when the platform needs any.
  final DanmakuAuth auth;

  /// Platform-specific handshake material, decoded by the transport itself.
  final Map<String, Object?> extras;

  @override
  String toString() => 'DanmakuTransportRequest($room)';
}

/// Receives transport events.
///
/// Implemented by the session that owns the transport, never by a transport
/// itself: a transport reports what happened and the session decides what it
/// means. Callbacks are plain methods rather than bare function fields so a
/// transport cannot half-replace a listener, and so an implementation can be
/// typed instead of built from closures.
abstract interface class DanmakuTransportListener {
  /// A decoded platform message.
  void onDanmakuMessage(DanmakuMessage message);

  /// The socket is attached and ready to deliver messages.
  ///
  /// A transport for a platform that has no chat support reports readiness
  /// without opening anything: it settled locally, and the session is
  /// considered established. This keeps "unsupported platform" out of the
  /// connection state machine instead of giving it a state of its own.
  void onTransportReady();

  /// A transient interruption while the transport still owns the room and is
  /// scheduling its own recovery. Not terminal.
  void onTransportReconnecting(String message);

  /// A terminal failure: the transport gave up on the room.
  void onTransportClosed(String message);
}

/// One platform's danmaku connection.
///
/// A transport is single-room and single-use: it is created for one [start]
/// and released by [stop]. Reusing one instance across rooms would let a late
/// packet from the previous socket be attributed to the new room, which is
/// exactly what the session's token guard exists to prevent — so the contract
/// does not allow it.
///
/// A transport does not decide when to reconnect, when to stop retrying or
/// which room to attach to; the session owns those decisions and the transport
/// only reports what happened.
abstract interface class DanmakuTransport {
  /// Stable identifier used in diagnostics and session snapshots.
  String get id;

  /// Whether the socket is currently attached.
  bool get isConnected;

  /// Interval between keep-alive calls, or [Duration.zero] when the platform
  /// does not need one.
  ///
  /// The session schedules [heartbeat]; the transport does not run its own
  /// timer, so a paused or backgrounded app does not accumulate parallel
  /// keep-alive work.
  Duration get heartbeatInterval;

  /// Attaches to [request]'s room and reports through [listener].
  ///
  /// Throws when the handshake cannot be started at all. A failure *after*
  /// start reports [DanmakuTransportListener.onTransportClosed] instead —
  /// the difference is whether the caller can still expect events.
  Future<void> start({required DanmakuTransportRequest request, required DanmakuTransportListener listener});

  /// Releases the connection.
  ///
  /// Must be safe to call when never started, when already stopped, and while
  /// a start is still in flight; a transport that raced its own start still
  /// owns the resources it opened.
  Future<void> stop();

  /// Sends one keep-alive. Called only when [heartbeatInterval] is non-zero.
  void heartbeat();
}
