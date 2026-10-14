import 'dart:async';

import 'package:flutter/widgets.dart';

/// Where an overlay layer sits above the video.
enum PlayerOverlaySlot {
  /// Top strip of the video area.
  top,

  /// Bottom strip of the video area.
  bottom,

  /// Entire video area (e.g. gesture catcher, letterbox art).
  center,

  /// Top-left corner (e.g. a back affordance or live badge).
  topLeft,

  /// Top-right corner (e.g. a resolution or settings tag).
  topRight,

  /// Bottom-left corner (e.g. a subtitle or caption track label).
  bottomLeft,

  /// Bottom-right corner (e.g. a picture-in-picture entry button).
  bottomRight,
}

/// How an overlay layer reacts to pointer visibility.
enum PlayerOverlayVisibility {
  /// Always rendered. Independent of hover state.
  ///
  /// Use for persistent content: subtitles, watermark, badge.
  always,

  /// Revealed together with the controls.
  ///
  /// Follows hover reveal on desktop and stays visible on touch
  /// devices. Use for control bars, titles, progress.
  withControls,

  /// Revealed together with the controls, but does not extend the
  /// hover area itself (input-transparent when hidden).
  withControlsPassthrough,
}

/// One layer above the video surface.
final class PlayerOverlayLayer {
  /// Creates a layer.
  const PlayerOverlayLayer({
    required this.slot,
    required this.builder,
    this.visibility = PlayerOverlayVisibility.always,
    this.padding,
    this.ignorePointer = false,
  });

  /// Where this layer sits.
  final PlayerOverlaySlot slot;

  /// Builds the layer content.
  final WidgetBuilder builder;

  /// When this layer is visible.
  final PlayerOverlayVisibility visibility;

  /// Padding inside the slot.
  final EdgeInsetsGeometry? padding;

  /// Whether this layer never receives pointer events.
  ///
  /// Use for purely visual layers (watermarks, subtitles) so they
  /// never block the video gestures.
  final bool ignorePointer;
}

/// Generic overlay stage above a video surface.
///
/// [MediaPlayerOverlay] composes arbitrary [PlayerOverlayLayer]s —
/// danmaku, subtitles, control bars, badges, watermarks — without
/// knowing what any of them is:
///
/// ```text
/// ┌──────────────────────────────┐
/// │ top strip        (topRight…) │  badge / title / countdown
/// │ ────────────────────────────│
/// │ center (whole area)          │  danmaku / subtitles / art
/// │ ────────────────────────────│
/// │ bottom strip     (controls)  │  control bar / progress
/// └──────────────────────────────┘
/// ```
///
/// Visibility adapts to the device:
///
/// - hover-capable devices (desktop): layers with
///   [PlayerOverlayVisibility.withControls] appear on pointer
///   hover and auto-hide after [hoverAutoHideDelay]; moving the
///   pointer restarts the countdown
/// - touch devices (no hover events): those layers are always
///   visible
/// - [PlayerOverlayVisibility.always] layers never hide
///
/// ```dart
/// MediaPlayerOverlay(
///   hoverMode: presentation.overlayHoverMode,
///   child: videoSurface,
///   layers: [
///     PlayerOverlayLayer(
///       slot: PlayerOverlaySlot.center,
///       ignorePointer: true,
///       builder: (_) => DanmakuView(...),       // or anything
///     ),
///     PlayerOverlayLayer(
///       slot: PlayerOverlaySlot.bottom,
///       visibility: PlayerOverlayVisibility.withControls,
///       builder: (_) => MyControlBar(),
///     ),
///   ],
/// )
/// ```
class MediaPlayerOverlay extends StatefulWidget {
  /// Creates the overlay.
  const MediaPlayerOverlay({
    required this.child,
    super.key,
    this.layers = const <PlayerOverlayLayer>[],
    this.hoverMode = true,
    this.hoverAutoHideDelay = const Duration(seconds: 3),
    this.topStripHeight,
    this.bottomStripHeight,
    this.visible,
    this.onTap,
  });

  /// The video surface below the overlay.
  final Widget child;

  /// Layers above the video, stacked in order.
  final List<PlayerOverlayLayer> layers;

  /// Whether hover show/hide is enabled.
  ///
  /// From `MediaCorePresentation.overlayHoverMode` on desktop,
  /// false on touch devices.
  final bool hoverMode;

  /// Idle delay before hover-revealed layers hide again.
  final Duration hoverAutoHideDelay;

  /// Height of the top strip. Defaults to 15% of the stage.
  final double? topStripHeight;

  /// Height of the bottom strip. Defaults to 22% of the stage.
  final double? bottomStripHeight;

  /// Force visibility of the withControls layers.
  ///
  /// Non-null overrides hover logic (e.g. app-level toggle).
  /// Null lets the adaptive behaviour decide.
  final bool? visible;

  /// Tap callback on the video area.
  final VoidCallback? onTap;

  @override
  State<MediaPlayerOverlay> createState() => _MediaPlayerOverlayState();
}

class _MediaPlayerOverlayState extends State<MediaPlayerOverlay> {
  bool _hovering = false;
  Timer? _hideTimer;

  bool get _controlsShown {
    final forced = widget.visible;
    if (forced != null) {
      return forced;
    }
    if (!widget.hoverMode) {
      return true; // touch: always visible
    }
    return _hovering;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onHover(bool hovering) {
    // Clear as well as cancel: a cancelled-but-set timer reads as "a countdown
    // is already running" to [_scheduleHide], which would then never arm one
    // again and the layers would stay up for the rest of the session.
    _hideTimer?.cancel();
    _hideTimer = null;

    if (_hovering == hovering) {
      return;
    }

    setState(() => _hovering = hovering);
    _scheduleHide();
  }

  /// A pointer move inside the region.
  ///
  /// Movement is activity - the layers stay up while the mouse is being moved -
  /// and it is also the only signal that the viewer is still here after an idle
  /// fade, because a pointer that never left the region cannot send another
  /// enter event. Moving therefore brings the layers back, but only that
  /// transition calls [setState]: a desktop mouse reports a hundred times a
  /// second, and rebuilding the whole overlay on each report is a stutter the
  /// host would feel while reaching for a control.
  void _onPointerMove() {
    if (!_hovering) {
      _onHover(true);

      return;
    }

    _scheduleHide();
  }

  /// Whether the pointer moved while the current countdown was running.
  ///
  /// `onHover` fires on every move - a hundred or more times a second on a
  /// desktop - and each one used to cancel the countdown and build a new Timer.
  /// What the viewer expects is only "the layers stay up while I am moving, and
  /// fall after a quiet stretch", so the running countdown now notes the
  /// movement and re-arms once when it expires: same behaviour, one timer per
  /// window instead of one per pointer event.
  bool _movedWhileCounting = false;

  /// Starts the idle auto-hide countdown, or marks the running one as touched.
  void _scheduleHide() {
    if (!(_hovering && widget.hoverMode)) {
      return;
    }

    if (_hideTimer != null) {
      _movedWhileCounting = true;

      return;
    }

    _movedWhileCounting = false;
    _hideTimer = Timer(widget.hoverAutoHideDelay, _onHideDeadline);
  }

  void _onHideDeadline() {
    _hideTimer = null;

    if (!mounted) {
      return;
    }

    if (_movedWhileCounting) {
      // Still moving: give the viewer another full window.
      _scheduleHide();

      return;
    }

    setState(() => _hovering = false);
  }

  @override
  Widget build(BuildContext context) {
    final showControls = _controlsShown;
    final stageHeight = MediaQuery.of(context).size.height;
    final topStrip = widget.topStripHeight ?? (stageHeight * 0.15);
    final bottomStrip = widget.bottomStripHeight ?? (stageHeight * 0.22);

    return MouseRegion(
      opaque: false,
      onEnter: widget.hoverMode ? (_) => _onHover(true) : null,
      onExit: widget.hoverMode ? (_) => _onHover(false) : null,
      onHover: widget.hoverMode ? (_) => _onPointerMove() : null,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // Video surface.
            Positioned.fill(child: widget.child),

            // Layer slots.
            for (final (index, layer) in widget.layers.indexed)
              _buildSlot(layer, index: index, showControls: showControls, topStrip: topStrip, bottomStrip: bottomStrip),
          ],
        ),
      ),
    );
  }

  Widget _buildSlot(
    PlayerOverlayLayer layer, {
    required int index,
    required bool showControls,
    required double topStrip,
    required double bottomStrip,
  }) {
    final shown = switch (layer.visibility) {
      PlayerOverlayVisibility.always => true,
      PlayerOverlayVisibility.withControls || PlayerOverlayVisibility.withControlsPassthrough => showControls,
    };

    Widget content = Padding(padding: layer.padding ?? EdgeInsets.zero, child: layer.builder(context));

    if (layer.visibility != PlayerOverlayVisibility.always) {
      content = AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: shown ? 1.0 : 0.0,
        child: content,
      );
    }

    final ignore =
        layer.ignorePointer || (layer.visibility == PlayerOverlayVisibility.withControlsPassthrough && !shown);

    // Positioned must be the direct child of the Stack; the slot
    // geometry is computed here per layer.slot.
    return switch (layer.slot) {
      PlayerOverlaySlot.top => Positioned(
        key: ValueKey<int>(index),
        top: 0,
        left: 0,
        right: 0,
        height: topStrip,
        child: IgnorePointer(ignoring: ignore, child: content),
      ),
      PlayerOverlaySlot.bottom => Positioned(
        key: ValueKey<int>(index),
        bottom: 0,
        left: 0,
        right: 0,
        height: bottomStrip,
        child: IgnorePointer(ignoring: ignore, child: content),
      ),
      PlayerOverlaySlot.center => Positioned(
        key: ValueKey<int>(index),
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        child: IgnorePointer(ignoring: ignore, child: content),
      ),
      PlayerOverlaySlot.topLeft => Positioned(
        key: ValueKey<int>(index),
        top: 0,
        left: 0,
        height: topStrip,
        child: IgnorePointer(ignoring: ignore, child: content),
      ),
      PlayerOverlaySlot.topRight => Positioned(
        key: ValueKey<int>(index),
        top: 0,
        right: 0,
        height: topStrip,
        child: IgnorePointer(ignoring: ignore, child: content),
      ),
      PlayerOverlaySlot.bottomLeft => Positioned(
        key: ValueKey<int>(index),
        bottom: 0,
        left: 0,
        height: bottomStrip,
        child: IgnorePointer(ignoring: ignore, child: content),
      ),
      PlayerOverlaySlot.bottomRight => Positioned(
        key: ValueKey<int>(index),
        bottom: 0,
        right: 0,
        height: bottomStrip,
        child: IgnorePointer(ignoring: ignore, child: content),
      ),
    };
  }
}
