import 'dart:async';
import 'dart:collection';

import 'package:flame_barrage/flame_barrage.dart';
import 'package:media_core_danmaku/src/danmaku_message.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// One message scheduled on a small surface.
///
/// Every presentation value here comes from the [BarrageConfig] the session
/// was given, so a host that renders this surface with flame_barrage and one
/// that renders it with its own painter read the same numbers from the same
/// place. Nothing is scaled or invented on the way through.
final class DanmakuOverlayItem {
  /// A message queued for a small surface, with every presentation value
  /// already resolved from the session's [BarrageConfig].
  const DanmakuOverlayItem({
    required this.message,
    required this.enqueuedAt,
    required this.lifetime,
    required this.fontSize,
    required this.opacity,
    required this.speed,
    required this.displayAreaFraction,
  });

  /// The message this item draws.
  final DanmakuMessage message;

  /// When the item entered the overlay. The host's renderer animates from here.
  final DateTime enqueuedAt;

  /// How long the item should stay on screen.
  ///
  /// A fixed-placement message carries its own duration; a scrolling one gets
  /// the time it takes to cross the surface at [speed], which is the same
  /// relationship the engine uses.
  final Duration lifetime;

  /// Font size, the message's own override winning over the config's.
  final double fontSize;

  /// Opacity, the message's own multiplied by the config's.
  final double opacity;

  /// Scroll speed in logical pixels per second.
  final double speed;

  /// Fraction of the surface height available to danmaku.
  final double displayAreaFraction;

  /// Whether the item is still on screen at [now].
  bool isLiveAt(DateTime now) => now.difference(enqueuedAt) < lifetime;

  @override
  String toString() => 'DanmakuOverlayItem(${message.userName}: ${message.text})';
}

/// Danmaku on a small surface: its own queue, its own bound, its own lifetime.
///
/// Responsibilities:
///
/// - hold the messages a small surface should draw, separately from the main
///   surface's queue
/// - drop what no longer fits instead of building a backlog
/// - empty itself when the surface goes away
///
/// It does not:
///
/// - decode or filter platform messages (the session does)
/// - draw anything (the host renders [items])
/// - decide when a small surface exists (the host owns the window; this binds
///   to its visibility stream)
/// - own any rendering knob: those are [BarrageConfig]'s, and this class only
///   reads them
///
/// ## Why the queue is separate
///
/// The main surface keeps a long queue on purpose: a viewer reading a busy room
/// wants a backlog. A small window does not — `maxVisibleCount` messages is
/// already more than a 320-pixel window can show before they leave the screen,
/// and a queue that grows while the window is hidden replays stale chat when it
/// returns. Keeping the two apart is what lets both behave correctly.
///
/// ## Why the rendering values are not this class's
///
/// A small window needs smaller text, and the answer to that is a smaller
/// `fontSize` in the [BarrageConfig] handed to this surface — the same answer
/// the engine gives. A second set of knobs here, with its own names and its own
/// scaling rules, is how one surface ends up drawing at a size the other
/// surface's config never mentioned.
///
/// ## Binding instead of depending
///
/// [bindVisibility] takes the visibility stream of whatever surface this
/// overlay belongs to — `PipDriver.onPipChanged`, a host's own
/// floating-mode signal, or any other visibility stream. The danmaku package
/// therefore knows nothing about picture-in-picture, floating windows or
/// their platform drivers, and those packages need no danmaku dependency to
/// be usable.
final class DanmakuOverlaySession {
  /// Creates an overlay driven by [config].
  ///
  /// [enabled] and [clearOnHide] are policy rather than presentation, which is
  /// why they live here and not in [BarrageConfig]: whether a hidden surface
  /// keeps its queue is a decision about this session, not about how a message
  /// looks.
  DanmakuOverlaySession({BarrageConfig config = const BarrageConfig(), this.clearOnHide = true, bool enabled = true})
    : _config = config,
      _enabled = enabled;

  BarrageConfig _config;
  bool _enabled;

  /// Whether the overlay is emptied when its surface is hidden.
  ///
  /// On by default: a danmaku queue that survives the small window would replay
  /// its backlog the next time the window appears, which reads as a glitch.
  final bool clearOnHide;

  /// Insertion-ordered so the oldest message can be dropped in O(1).
  final LinkedHashMap<int, DanmakuOverlayItem> _items = LinkedHashMap<int, DanmakuOverlayItem>();

  /// Ledger of the queued messages.
  ///
  /// An overlay queue is small by design, which is exactly why it is worth
  /// counting: a wall of cells each holding their own queue is where "small by
  /// design" stops being small.
  /// This instance's key in the shared account.
  late final String _memoryKey = memoryContributorKey(this);

  final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.danmaku);

  final StreamController<bool> _activeController = StreamController<bool>.broadcast();

  StreamSubscription<bool>? _visibilitySubscription;

  int _sequence = 0;
  bool _surfaceVisible = false;
  bool _disposed = false;

  /// The rendering configuration this overlay reads.
  BarrageConfig get config => _config;

  /// Whether the overlay accepts messages right now.
  ///
  /// Requires both a visible surface and [setEnabled]: a hidden window keeps
  /// nothing.
  bool get isActive => !_disposed && _surfaceVisible && _enabled;

  /// Whether this overlay is switched on at all.
  bool get isEnabled => _enabled;

  /// Whether the surface this overlay is bound to is currently visible.
  bool get isSurfaceVisible => _surfaceVisible;

  /// Active-state changes.
  Stream<bool> get onActiveChanged => _activeController.stream;

  /// Messages currently on the overlay, oldest first.
  List<DanmakuOverlayItem> get items => List<DanmakuOverlayItem>.unmodifiable(_items.values);

  /// Number of queued messages.
  int get length => _items.length;

  /// Follows [visibility] to know when the surface appears and disappears.
  ///
  /// The first event is treated as authoritative: a stream that starts with
  /// `true` means the surface is already up. Re-binding replaces the previous
  /// subscription so a surface swap cannot leave two feeds running.
  void bindVisibility(Stream<bool> visibility) {
    _ensureNotDisposed();
    // The previous subscription is replaced on the next line, so cancelling it
    // is fire-and-forget: nothing awaits it and the reassignment does not
    // depend on the cancel completing first.
    final previous = _visibilitySubscription;
    if (previous != null) unawaited(previous.cancel());
    _visibilitySubscription = visibility.listen(_handleVisibility, onError: (_) {});
  }

  /// Stops following the bound surface.
  void unbindVisibility() {
    // Same reasoning as [bindVisibility]: the handle is nulled immediately and
    // [_handleVisibility] runs synchronously, so no event can slip in between
    // the cancel and the state update.
    final previous = _visibilitySubscription;
    if (previous != null) unawaited(previous.cancel());
    _visibilitySubscription = null;
    _handleVisibility(false);
  }

  /// Applies a new rendering configuration.
  ///
  /// A smaller `maxVisibleCount` trims immediately: the bound is the reason
  /// this queue exists, and honouring it late is the same as not honouring it.
  void updateConfig(BarrageConfig config) {
    _ensureNotDisposed();
    _config = config;
    _trim();
    _notifyActiveChanged();
  }

  /// Switches the overlay on or off.
  ///
  /// Turning it off empties it: a disabled overlay that keeps messages would
  /// replay them the moment it is enabled again.
  void setEnabled({required bool enabled}) {
    _ensureNotDisposed();
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    if (!enabled) {
      clear();
    }
    _notifyActiveChanged();
  }

  /// Offers [message] to the overlay.
  ///
  /// Returns whether it was queued. A message is refused when the overlay is
  /// inactive (hidden or disabled) — the caller does not need to check first.
  ///
  /// [surfaceWidth] is what a scrolling message's lifetime is measured
  /// against; without it the engine's own dwell time is used.
  bool enqueue(DanmakuMessage message, {double? surfaceWidth, DateTime? now}) {
    _ensureNotDisposed();
    if (!isActive) {
      return false;
    }
    if (message.text.trim().isEmpty) {
      return false;
    }

    final at = now ?? DateTime.now();
    final item = _buildItem(message, surfaceWidth: surfaceWidth, at: at);

    // Evicting the oldest is deliberate: on a small surface the newest message
    // is the one the viewer can still act on, and a full queue means the
    // overlay is behind, not that the incoming message is unwanted.
    while (_items.length >= _config.maxVisibleCount) {
      _items.remove(_items.keys.first);
    }

    _items[_sequence++] = item;
    _reportMemory();
    return true;
  }

  /// Removes items whose lifetime has passed, returning what was removed.
  ///
  /// The host's renderer calls this on its frame tick; nothing here is
  /// time-driven, so a paused app does not accumulate work.
  List<DanmakuOverlayItem> evictExpired({DateTime? now}) {
    _ensureNotDisposed();
    final at = now ?? DateTime.now();
    final expired = <DanmakuOverlayItem>[];
    _items.removeWhere((_, item) {
      if (item.isLiveAt(at)) {
        return false;
      }
      expired.add(item);
      return true;
    });
    if (expired.isNotEmpty) {
      _reportMemory();
    }
    return expired;
  }

  /// Empties the overlay.
  void clear() {
    _items.clear();
    _reportMemory(note: 'overlay cleared');
  }

  /// Display area for a surface of [surfaceHeight], in logical pixels.
  double displayAreaFor(double surfaceHeight) => surfaceHeight * _config.area.clamp(0.1, 1.0);

  /// Releases the overlay.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await _visibilitySubscription?.cancel();
    _visibilitySubscription = null;
    _disposed = true;
    clear();
    _memory.withdraw(_memoryKey);
    await _activeController.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _reportMemory({String? note}) {
    _memory.report(
      _memoryKey,
      items: _items.length,
      bytes: _items.length * MemoryEstimates.danmakuMessage,
      note: note ?? '${_items.length}/${_config.maxVisibleCount} queued',
    );
  }

  void _handleVisibility(bool visible) {
    if (visible == _surfaceVisible) {
      return;
    }
    _surfaceVisible = visible;
    if (!visible && clearOnHide) {
      clear();
    }
    _notifyActiveChanged();
  }

  DanmakuOverlayItem _buildItem(DanmakuMessage message, {required DateTime at, double? surfaceWidth}) {
    final style = message.style;
    final fontSize = style?.fontSize ?? _config.fontSize;
    final speed = _config.baseSpeed <= 0 ? 1.0 : _config.baseSpeed;

    // A scrolling message is on screen for as long as it takes to cross the
    // surface — the same relationship the engine uses. Without a width there
    // is nothing to cross, so the engine's own dwell time stands in.
    final crossing = surfaceWidth != null && surfaceWidth > 0
        ? Duration(milliseconds: ((surfaceWidth / speed) * 1000).round())
        : _config.fixedDuration;
    final lifetime = style != null && style.placement != DanmakuPlacement.scroll
        ? Duration(milliseconds: style.fixedDurationMs)
        : crossing;

    return DanmakuOverlayItem(
      message: message,
      enqueuedAt: at,
      lifetime: lifetime,
      fontSize: fontSize,
      opacity: (style?.opacity ?? 1) * _config.opacity.clamp(0.0, 1.0),
      speed: speed,
      displayAreaFraction: _config.area.clamp(0.1, 1.0),
    );
  }

  void _trim() {
    while (_items.length > _config.maxVisibleCount) {
      _items.remove(_items.keys.first);
    }
  }

  void _notifyActiveChanged() {
    if (!_activeController.isClosed) {
      _activeController.add(isActive);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('DanmakuOverlaySession has been disposed.');
    }
  }
}
