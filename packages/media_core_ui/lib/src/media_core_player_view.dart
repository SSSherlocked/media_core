import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_ui/media_core_ui.dart' show PlayerControlsStyle;

import 'package:media_core_ui/src/common/player_control_actions.dart';
import 'package:media_core_ui/src/common/player_controls_controller.dart';
import 'package:media_core_ui/src/common/player_controls_stage.dart';
import 'package:media_core_ui/src/common/player_controls_style.dart';
import 'package:media_core_ui/src/common/player_controls_theme.dart';
import 'package:media_core_ui/src/cupertino/cupertino_player_controls.dart';
import 'package:media_core_ui/src/fluent/fluent_player_controls.dart';
import 'package:media_core_ui/src/macos/macos_player_controls.dart';
import 'package:media_core_ui/src/material/material_player_controls.dart';
import 'package:media_core_ui/src/neumorphic/neumorphic_player_controls.dart';
import 'package:media_core_ui/src/yaru/yaru_player_controls.dart';

/// What a double tap on the video does.
///
/// The platforms disagree, and the disagreement is the point:
///
/// - [zoom] — iOS and Instagram-style viewers magnify the picture.
/// - [fullscreen] — desktop players toggle the window on a double click.
/// - [none] — a feed that owns the tap (skip ±10 s, like, pause) leaves it
///   alone.
enum PlayerDoubleTapAction {
  /// Magnify around the tapped point.
  zoom,

  /// Enter fullscreen, when the host supports it.
  fullscreen,

  /// Do nothing; the host handles it.
  none;

  /// What a design language does by default.
  ///
  /// Touch languages magnify — the gesture is already in the viewer's muscle
  /// memory from every photo app; pointer languages toggle the window, which is
  /// what a double click means on a desktop.
  static PlayerDoubleTapAction forStyle(PlayerControlsStyle style) {
    return style.isTouch ? PlayerDoubleTapAction.zoom : PlayerDoubleTapAction.fullscreen;
  }
}

/// A player: video, controls, gestures and keyboard, in one widget.
///
/// This is the assembly a host drops on screen. It composes
///
/// - [MediaPlayerView] for the picture (aspect-correct box, zoom, screenshots),
/// - the control set the style asks for,
/// - [PlayerControlsStage] for visibility, tap, hover and keyboard behaviour.
///
/// ```dart
/// MediaCorePlayerView(
///   handle: handle,                                    // style per platform
///   actions: KernelPlayerControlActions(kernel: kernel, playerId: handle.id),
/// )
/// ```
///
/// Everything is overridable: the style can be forced on a platform that would
/// not pick it, the theme swapped, the controller supplied, or the bar replaced
/// entirely with [controls].
final class MediaCorePlayerView extends StatefulWidget {
  /// Creates the composed player view.
  const MediaCorePlayerView({
    required this.handle,
    super.key,
    this.style,
    this.styleResolver,
    this.actions = PlayerControlActions.none,
    this.theme,
    this.zoom,
    this.pinchToZoom = true,
    this.doubleTapAction,
    this.autoHideDelay,
    this.autoHideControls = true,
    this.keepControlsWhilePaused = true,
    this.keyboardShortcuts = true,
    this.showControls = true,
    this.showTopBar = true,
    this.showOverflowMenu = true,
    this.showSkipButtons = false,
    this.skipStep = const Duration(seconds: 10),
    this.controls,
    this.controller,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.mirror = false,
    this.backgroundColor,
    this.captureBoundary = true,
    this.onTapVideo,
    this.shortcuts = const PlayerShortcuts(),
  });

  /// PlayerIdentity to render and drive.
  final PlayerHandle handle;

  /// Control set to force; null picks the one the platform expects.
  ///
  /// Forcing a style is a real use case, not a workaround: a host that wants
  /// its iOS look on Android passes [PlayerControlsStyle.cupertino] and gets it.
  final PlayerControlsStyle? style;

  /// Picks the style per platform when [style] is null.
  final PlayerControlsStyle Function(TargetPlatform platform)? styleResolver;

  /// Host callbacks: fullscreen, PiP, floating window, screenshot handling.
  final PlayerControlActions actions;

  /// Colors and metrics; defaults to the chosen style's theme.
  final PlayerControlsTheme? theme;

  /// Zoom controller for the picture.
  ///
  /// Pass one to read or reset the magnification, or to share it with a small
  /// window; omit it and the view owns one whenever a zoom gesture is enabled.
  final VideoZoomController? zoom;

  /// Whether two fingers magnify the picture.
  final bool pinchToZoom;

  /// What a double tap does; defaults to the style's convention.
  final PlayerDoubleTapAction? doubleTapAction;

  /// How long the controls stay after the last interaction.
  ///
  /// Defaults to the theme's own delay: 4 s on iOS, 3 s on Android, 2 s on
  /// desktop.
  final Duration? autoHideDelay;

  /// Whether the controls hide themselves while playing.
  final bool autoHideControls;

  /// Whether the controls stay on screen while paused.
  final bool keepControlsWhilePaused;

  /// Whether the player answers keyboard shortcuts.
  final bool keyboardShortcuts;

  /// Whether the control bars are rendered at all.
  ///
  /// False leaves the video and its gestures — for a thumbnail, a grid cell, or
  /// a host with its own chrome.
  final bool showControls;

  /// Whether the style's own top bar rides over the picture.
  ///
  /// False hands the top of the picture to the host page; the transport bar
  /// below the picture is unaffected. Only the Material style honours this
  /// today; other styles always render their top bar.
  final bool showTopBar;

  /// Whether the bar's overflow menu is offered.
  ///
  /// False drops the ⋮ entry: a host that already exposes the same abilities
  /// through its own chrome (speed chips, PiP, floating) would otherwise ship
  /// two entrances for one action, in the library's fixed copy.
  final bool showOverflowMenu;

  /// Whether skip buttons flank the play button in the transport bar.
  ///
  /// Off by default — Android apps usually leave those to gestures — but a
  /// recording player wants visible ±[skipStep] jumps.
  final bool showSkipButtons;

  /// Amount the skip buttons jump.
  final Duration skipStep;

  /// Replaces the style's own bar.
  final Widget Function(BuildContext context, PlayerControlsController controller)? controls;

  /// Controller to use; the view creates and owns one when omitted.
  final PlayerControlsController? controller;

  /// How the video is fitted into the box.
  final BoxFit fit;

  /// Alignment of the fitted video.
  final AlignmentGeometry alignment;

  /// Whether to mirror the picture horizontally.
  final bool mirror;

  /// Background color while no video widget is available.
  final Color? backgroundColor;

  /// Whether the video layer offers itself for screenshots.
  final bool captureBoundary;

  /// Called on every tap on the video, before the controls toggle.
  final VoidCallback? onTapVideo;

  /// Keyboard mapping used when [keyboardShortcuts] is on.
  final PlayerShortcuts shortcuts;

  @override
  State<MediaCorePlayerView> createState() => _MediaCorePlayerViewState();
}

final class _MediaCorePlayerViewState extends State<MediaCorePlayerView> {
  PlayerControlsController? _owned;
  VideoZoomController? _ownedZoom;

  PlayerControlsController get _controller {
    return widget.controller ?? (_owned ??= _createController());
  }

  /// Style in use: the forced one, the resolved one, or the platform's.
  PlayerControlsStyle get _style {
    final forced = widget.style;

    if (forced != null) {
      return forced;
    }

    return widget.styleResolver?.call(defaultTargetPlatform) ?? PlayerControlsStyle.forPlatform(defaultTargetPlatform);
  }

  /// Theme in use: the host's override, or the style's convention.
  PlayerControlsTheme get _theme => widget.theme ?? PlayerControlsTheme.of(_style);

  /// Double tap behaviour, defaulted per style.
  PlayerDoubleTapAction get _doubleTapAction {
    return widget.doubleTapAction ?? PlayerDoubleTapAction.forStyle(_style);
  }

  /// Zoom controller, created only when a gesture needs one.
  VideoZoomController? get _zoom {
    if (!widget.pinchToZoom && _doubleTapAction != PlayerDoubleTapAction.zoom) {
      return widget.zoom;
    }

    return widget.zoom ?? (_ownedZoom ??= VideoZoomController());
  }

  PlayerControlsController _createController() {
    return PlayerControlsController(
      handle: widget.handle,
      actions: widget.actions,
      theme: _theme,
      style: _style,
      hideDelay: widget.autoHideDelay ?? _theme.hideDelay,
      keepVisibleWhenPaused: widget.keepControlsWhilePaused,
      autoHide: widget.autoHideControls,
    );
  }

  @override
  void initState() {
    super.initState();

    // An externally supplied controller still has to know which style and
    // theme this view renders, or its `theme` getter would disagree with the
    // bars on screen.
    widget.controller?.configure(
      style: _style,
      theme: _theme,
      hideDelay: widget.autoHideDelay ?? _theme.hideDelay,
      autoHide: widget.autoHideControls,
      keepVisibleWhenPaused: widget.keepControlsWhilePaused,
      actions: widget.actions,
    );
  }

  @override
  void didUpdateWidget(MediaCorePlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A controller created for the old handle must not keep driving it.
    if (!identical(oldWidget.handle, widget.handle)) {
      _owned?.dispose();
      _owned = null;
    }

    _controller.configure(
      style: _style,
      theme: _theme,
      hideDelay: widget.autoHideDelay ?? _theme.hideDelay,
      autoHide: widget.autoHideControls,
      keepVisibleWhenPaused: widget.keepControlsWhilePaused,
      actions: widget.actions,
    );
  }

  @override
  void dispose() {
    _owned?.dispose();
    _owned = null;

    _ownedZoom?.dispose();
    _ownedZoom = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final style = _style;
    final doubleTap = _doubleTapAction;

    final video = MediaPlayerView(
      handle: widget.handle,
      fit: widget.fit,
      alignment: widget.alignment,
      mirror: widget.mirror,
      // Soft UI is invisible without a page that shares its surface color, so
      // the composed view seeds the background from the theme; every other
      // language keeps the neutral black.
      backgroundColor: widget.backgroundColor ?? (style == PlayerControlsStyle.neumorphic ? _theme.surface : null),
      captureBoundary: widget.captureBoundary,
      zoom: _zoom,
      enablePinchZoom: widget.pinchToZoom,
      enableDoubleTapZoom: doubleTap == PlayerDoubleTapAction.zoom,
    );

    return PlayerControlsStage(
      controller: controller,
      style: style,
      video: video,
      keyboardShortcuts: widget.keyboardShortcuts,
      shortcuts: widget.shortcuts,
      onTapVideo: widget.onTapVideo,
      onDoubleTap: doubleTap == PlayerDoubleTapAction.fullscreen ? controller.enterFullscreen : null,
      controls: widget.showControls ? _buildControls(controller, style) : const SizedBox.shrink(),
    );
  }

  Widget _buildControls(PlayerControlsController controller, PlayerControlsStyle style) {
    final custom = widget.controls;

    if (custom != null) {
      return custom(context, controller);
    }

    final theme = _theme;

    return switch (style) {
      PlayerControlsStyle.material => MaterialPlayerControls(
        controller: controller,
        theme: theme,
        showTopBar: widget.showTopBar,
        showOverflowMenu: widget.showOverflowMenu,
        showSkipButtons: widget.showSkipButtons,
        skipStep: widget.skipStep,
      ),
      PlayerControlsStyle.cupertino => CupertinoPlayerControls(controller: controller, theme: theme),
      PlayerControlsStyle.fluent => FluentPlayerControls(controller: controller, theme: theme),
      PlayerControlsStyle.macos => MacosPlayerControls(controller: controller, theme: theme),
      PlayerControlsStyle.yaru => YaruPlayerControls(controller: controller, theme: theme),
      PlayerControlsStyle.neumorphic => NeumorphicPlayerControls(controller: controller, theme: theme),
    };
  }
}
