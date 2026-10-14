import 'package:media_core_danmaku/src/danmaku_message.dart';

/// Notices this module originates.
///
/// They are codes, not sentences: the module has no locale and no business
/// choosing wording. A host maps each code onto its own translation, ignores
/// the ones it has no UI for, and is free to suppress all of them.
enum DanmakuNotice {
  /// A handshake was started for the room.
  connecting,

  /// The transport reported readiness.
  connected,

  /// No readiness inside the configured start timeout.
  connectionTimeout,

  /// The platform has no chat integration, so a local session was settled
  /// without opening anything.
  unsupportedPlatform,

  /// The room is being viewed in recording mode, where chat is not attached.
  recordingMode,

  /// A viewer name arrived masked by the platform (guest/anonymous display
  /// names). Reported generically: whether this is worth telling the viewer
  /// depends on the platform, which the host knows and this module does not.
  maskedUserName,
}

/// Output port of a danmaku session.
///
/// The module decodes, deduplicates and filters; the host decides what a
/// message becomes on screen. Keeping the two apart is what lets the same
/// session feed a full player page, a picture-in-picture surface and a
/// floating window without the module knowing any of them exist.
///
/// Implementations must be cheap and must not throw: they are called from the
/// transport's callback path, and an exception there would be attributed to
/// the transport instead of the host. A host that needs to do something
/// expensive (network, disk) should queue instead.
abstract interface class DanmakuSink {
  /// One message that passed every filter.
  ///
  /// [immediate] asks the host to render synchronously rather than through its
  /// queue — used for messages the viewer is waiting on, such as the echo of
  /// their own send.
  void onDanmaku(DanmakuMessage message, {bool immediate = false});

  /// A viewer metric that arrived on the chat socket.
  ///
  /// Carried here because single-socket platforms deliver it on the same
  /// connection; the host forwards it to whatever owns audience numbers.
  void onAudienceUpdate(DanmakuAudienceUpdate update);

  /// A paid message. Separate from [onDanmaku] because a paid message is a
  /// card with a lifetime, not a line of chat.
  void onSuperChat(DanmakuSuperChat message);

  /// A notice this module originated. See [DanmakuNotice].
  void onNotice(DanmakuNotice notice);

  /// Free-form text from the transport itself (reconnect and close reasons).
  ///
  /// Not a code: only the transport knows what the platform said, and
  /// inventing a closed set of codes for 48 platforms' error strings would be
  /// a worse lie than passing the text through.
  void onTransportNotice(String message);

  /// The room identity the host should display, or `null` when no room is
  /// owned.
  ///
  /// Distinct from the session key: this is the platform's own room id, which
  /// is what a user-facing label shows.
  void onRoomChanged(String? roomId);

  /// Drops every rendered message.
  ///
  /// Called on room switch and teardown so the next room never inherits the
  /// previous one's backlog.
  void clearRendered();
}

/// Sink that discards everything.
///
/// Useful as a default before a host registers its own, and in tests that only
/// care about session state.
final class DanmakuNullSink implements DanmakuSink {
  /// A sink that discards every message, notice and metric.
  const DanmakuNullSink();

  @override
  void onDanmaku(DanmakuMessage message, {bool immediate = false}) {}

  @override
  void onAudienceUpdate(DanmakuAudienceUpdate update) {}

  @override
  void onSuperChat(DanmakuSuperChat message) {}

  @override
  void onNotice(DanmakuNotice notice) {}

  @override
  void onTransportNotice(String message) {}

  @override
  void onRoomChanged(String? roomId) {}

  @override
  void clearRendered() {}
}
