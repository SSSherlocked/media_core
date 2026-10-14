import 'package:media_core_danmaku/src/danmaku_message.dart';
import 'package:media_core_danmaku/src/danmaku_overlay_session.dart';
import 'package:media_core_danmaku/src/danmaku_sink.dart';

/// Feeds a small-surface overlay alongside the primary sink.
///
/// The overlay is a second consumer of the same accepted messages, not a second
/// session: filters, gating and ordering stay in one place, and the overlay
/// only decides what to keep and how to draw it.
///
/// ```dart
/// final overlay = DanmakuOverlaySession();
/// overlay.bindVisibility(pipDriver.onPipChanged);
///
/// final controller = DanmakuController(
///   sink: DanmakuFanOutSink(primary: myPageSink, overlay: overlay, surfaceWidth: () => pipWidth),
/// );
/// ```
///
/// Every member except [onDanmaku] and [clearRendered] is forwarded unchanged,
/// so the primary sink keeps owning audience metrics, paid messages, notices
/// and room identity.
final class DanmakuFanOutSink implements DanmakuSink {
  /// Fans accepted messages to [primary] and, when present, the small-surface
  /// [overlay]; [surfaceWidth] is read per message so the overlay scales to its
  /// own window.
  DanmakuFanOutSink({required this.primary, this.overlay, this.surfaceWidth});

  /// Sink that owns everything the overlay does not care about.
  final DanmakuSink primary;

  /// Small-surface overlay, or `null` when the host has no small surface.
  final DanmakuOverlaySession? overlay;

  /// Current surface width in logical pixels, read on each message.
  ///
  /// A callback rather than a value because a small window is resized while it
  /// is open, and the font scale has to follow it.
  final double? Function()? surfaceWidth;

  @override
  void onDanmaku(DanmakuMessage message, {bool immediate = false}) {
    primary.onDanmaku(message, immediate: immediate);
    overlay?.enqueue(message, surfaceWidth: surfaceWidth?.call());
  }

  @override
  void onAudienceUpdate(DanmakuAudienceUpdate update) => primary.onAudienceUpdate(update);

  @override
  void onSuperChat(DanmakuSuperChat message) => primary.onSuperChat(message);

  @override
  void onNotice(DanmakuNotice notice) => primary.onNotice(notice);

  @override
  void onTransportNotice(String message) => primary.onTransportNotice(message);

  @override
  void onRoomChanged(String? roomId) => primary.onRoomChanged(roomId);

  /// Clears both surfaces.
  ///
  /// A room switch invalidates the overlay too, and leaving messages behind
  /// there would show the previous room's chat in the small window.
  @override
  void clearRendered() {
    primary.clearRendered();
    overlay?.clear();
  }
}
