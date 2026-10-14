import 'package:flame_barrage/flame_barrage.dart';
import 'package:media_core/media_core.dart';

import 'package:media_core_danmaku/src/barrage_item_mapper.dart';
import 'package:media_core_danmaku/src/danmaku_message.dart';
import 'package:media_core_danmaku/src/danmaku_sink.dart';

/// The [DanmakuSink] that renders through flame_barrage.
///
/// The session hands over messages that already passed the gate, the block
/// list, the repeated filter and the similarity filter; this sink's only job
/// is to turn one into an engine item and give it to the controller. All
/// layout, pacing and painting belong to the engine.
///
/// Two things it deliberately does not pretend to do:
///
/// - **`immediate` is advisory.** The engine paces every message through
///   `BarrageConfig.emitInterval` and has no per-message bypass, so a host
///   that must show the viewer's own echo instantly runs the engine with
///   `realtimeMode: true` rather than relying on this flag.
/// - **A superchat is not a barrage line.** It is a card with its own
///   lifetime, which the engine has no shape for; it goes to
///   [onSuperChatCard] instead. When no handler is supplied the arrival is
///   logged once rather than dropped without a trace.
///
/// Every non-rendering callback is forwarded to [host], so a page can keep
/// its audience counter and its notices while this sink owns the text.
final class FlameBarrageSink implements DanmakuSink {
  /// Creates a sink rendering into [controller].
  FlameBarrageSink(
    this.controller, {
    this.host = const DanmakuNullSink(),
    this.onSuperChatCard,
    int Function(DanmakuMessage message)? priorityOf,
  }) : _priorityOf = priorityOf;

  /// The engine facade this sink feeds.
  final BarrageController controller;

  /// Where the non-rendering callbacks go.
  final DanmakuSink host;

  /// Host hook for paid messages, which are cards rather than lines.
  final void Function(DanmakuSuperChat message)? onSuperChatCard;

  final int Function(DanmakuMessage message)? _priorityOf;

  bool _warnedAboutSuperChat = false;

  @override
  void onDanmaku(DanmakuMessage message, {bool immediate = false}) {
    controller.send(BarrageItemMapper.toItem(message, priority: _priorityOf?.call(message) ?? 0));
  }

  @override
  void onSuperChat(DanmakuSuperChat message) {
    final handler = onSuperChatCard;
    if (handler == null) {
      if (!_warnedAboutSuperChat) {
        _warnedAboutSuperChat = true;
        MediaCoreLog.warning(
          LogCategory.danmaku,
          'a superchat arrived with no card handler; it is not rendered as '
          'barrage text. Pass onSuperChatCard to FlameBarrageSink.',
        );
      }
      host.onSuperChat(message);
      return;
    }
    handler(message);
  }

  @override
  void onAudienceUpdate(DanmakuAudienceUpdate update) => host.onAudienceUpdate(update);

  @override
  void onNotice(DanmakuNotice notice) => host.onNotice(notice);

  @override
  void onTransportNotice(String message) => host.onTransportNotice(message);

  @override
  void onRoomChanged(String? roomId) {
    // A new room must not inherit the previous one's backlog: the session
    // calls this on switch, and the screen is the other half of that.
    controller.clear();
    host.onRoomChanged(roomId);
  }

  @override
  void clearRendered() => controller.clear();

  /// Takes back one message the platform recalled, by its provider id.
  ///
  /// Returns whether anything was on screen or queued to take back.
  bool retract(String messageId) {
    if (messageId.trim().isEmpty) {
      return false;
    }
    return controller.retractWhere((item) => item.id == messageId) > 0;
  }
}
