import 'dart:async';

import 'package:flutter/material.dart';

import 'package:media_core_ui/src/common/player_control_buttons.dart';
import 'package:media_core_ui/src/common/player_controls_controller.dart';
import 'package:media_core_ui/src/common/player_controls_theme.dart';
import 'package:media_core_ui/src/common/player_progress_bar.dart';

/// Control set in the Material Design idiom.
///
/// What makes it read as Material rather than as "dark buttons":
///
/// - a solid scrim bar at the top carrying the title and an overflow menu,
///   because Android put the actions there since the first YouTube app;
/// - a filled circular play button in the middle, sized for a thumb;
/// - a thick slider with a visible thumb, always, not only while dragging;
/// - the elapsed time and the duration on either side of the slider, with the
///   mute and fullscreen glyphs at the ends of the same row;
/// - ripple feedback on every control;
/// - no volume slider: Android volume belongs to the hardware keys, and an
///   in-app slider would fight the system panel.
///
/// ```dart
/// MediaCorePlayerView(handle: handle, style: PlayerControlsStyle.material)
/// ```
final class MaterialPlayerControls extends StatelessWidget {
  /// Creates the Material control set.
  const MaterialPlayerControls({
    required this.controller,
    super.key,
    this.theme,
    this.showTitle = true,
    this.showTopBar = true,
    this.showOverflowMenu = true,
    this.showSkipButtons = false,
    this.skipStep = const Duration(seconds: 10),
    this.padding = EdgeInsets.zero,
  });

  /// Playback state and actions.
  final PlayerControlsController controller;

  /// Colors and metrics; defaults to [PlayerControlsTheme.material].
  final PlayerControlsTheme? theme;

  /// Whether the title rides in the top bar.
  final bool showTitle;

  /// Whether the top bar is rendered at all.
  ///
  /// False leaves the top of the picture to the host — a page that draws its
  /// own header (back button, speed chip, overflow) over the video would
  /// otherwise stack two bars in the same corner.
  final bool showTopBar;

  /// Whether the overflow menu is offered.
  ///
  /// Holds what does not deserve a permanent button: rate, loop, audio-only,
  /// floating window.
  final bool showOverflowMenu;

  /// Whether skip buttons flank the play button.
  ///
  /// Off by default — Android apps usually leave those to gestures — but the
  /// buttons exist for hosts that want YouTube's tap-to-skip pair visible.
  final bool showSkipButtons;

  /// Amount the skip buttons jump.
  final Duration skipStep;

  /// Padding around the whole set.
  final EdgeInsets padding;

  PlayerControlsTheme get _theme => theme ?? const PlayerControlsTheme.material();

  @override
  Widget build(BuildContext context) {
    final theme = _theme;

    return Material(
      // Transparent, but present: Material widgets assert without a Material
      // ancestor, and a host may be a Cupertino app.
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Padding(
            padding: padding,
            child: Column(
              children: <Widget>[
                if (showTopBar)
                  _TopBar(controller: controller, theme: theme, showTitle: showTitle, showMenu: showOverflowMenu),
                Expanded(
                  child: _CenterControls(
                    controller: controller,
                    theme: theme,
                    showSkipButtons: showSkipButtons,
                    skipStep: skipStep,
                  ),
                ),
                _BottomBar(controller: controller, theme: theme),
              ],
            ),
          );
        },
      ),
    );
  }
}

final class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.theme, required this.showTitle, required this.showMenu});

  final PlayerControlsController controller;
  final PlayerControlsTheme theme;
  final bool showTitle;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final title = controller.title;
    final icons = theme.icons;

    return ColoredBox(
      color: theme.scrim,
      child: Padding(
        padding: theme.contentPadding,
        child: Row(
          children: <Widget>[
            if (showTitle && title != null)
              Expanded(
                child: Text(title, style: theme.titleTextStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
              )
            else
              const Spacer(),
            if (controller.canCaptureScreenshot)
              PlayerIconButton(
                icon: icons.screenshot,
                theme: theme,
                tooltip: 'Save frame',
                onPressed: controller.captureScreenshot,
              ),
            if (controller.actions.canEnterPip)
              PlayerIconButton(
                icon: icons.pictureInPicture,
                theme: theme,
                tooltip: 'Picture in picture',
                onPressed: controller.enterPip,
              ),
            if (showMenu) _OverflowMenu(controller: controller, theme: theme),
          ],
        ),
      ),
    );
  }
}

final class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.controller, required this.theme});

  final PlayerControlsController controller;
  final PlayerControlsTheme theme;

  @override
  Widget build(BuildContext context) {
    final icons = theme.icons;

    return PopupMenuButton<String>(
      tooltip: 'More',
      color: const Color(0xFF212121),
      icon: Icon(icons.more, size: 22, color: theme.foreground),
      onSelected: (value) {
        switch (value) {
          case 'rate':
            unawaited(controller.cycleRate());
          case 'loop':
            unawaited(controller.toggleLoop());
          case 'floating':
            unawaited(controller.enterFloating());
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        if (controller.canSeek)
          PopupMenuItem<String>(
            value: 'rate',
            child: Row(
              children: <Widget>[
                Icon(icons.speed, size: 20),
                const SizedBox(width: 12),
                const Text('Playback speed'),
                const Spacer(),
                Text('${controller.rate.toStringAsFixed(2)}x', style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'loop',
          child: Row(
            children: <Widget>[
              Icon(icons.loop, size: 20),
              const SizedBox(width: 12),
              const Text('Loop'),
              if (controller.isLooping) const Spacer(),
              if (controller.isLooping) const Icon(Icons.check, size: 18),
            ],
          ),
        ),
        if (controller.actions.canEnterFloating)
          PopupMenuItem<String>(
            value: 'floating',
            child: Row(
              children: <Widget>[
                Icon(icons.floatingWindow, size: 20),
                const SizedBox(width: 12),
                const Text('Floating window'),
              ],
            ),
          ),
      ],
    );
  }
}

final class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.controller,
    required this.theme,
    required this.showSkipButtons,
    required this.skipStep,
  });

  final PlayerControlsController controller;
  final PlayerControlsTheme theme;
  final bool showSkipButtons;
  final Duration skipStep;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasSource) {
      return const SizedBox.shrink();
    }

    final icons = theme.icons;

    if (controller.isBuffering) {
      return PlayerBufferingIndicator(theme: theme);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (showSkipButtons)
          IconButton(
            iconSize: theme.iconSize + 8,
            color: theme.foreground,
            tooltip: 'Back ${skipStep.inSeconds}s',
            icon: Icon(icons.rewind),
            onPressed: () => controller.seekBy(-skipStep),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: IconButton.filled(
            iconSize: theme.primaryIconSize * 0.7,
            style: IconButton.styleFrom(
              backgroundColor: theme.accent,
              foregroundColor: theme.foreground,
              padding: const EdgeInsets.all(12),
            ),
            tooltip: controller.isPlaying ? 'Pause' : 'Play',
            icon: Icon(icons.transportFor(playing: controller.isPlaying)),
            onPressed: controller.togglePlayPause,
          ),
        ),
        if (showSkipButtons)
          IconButton(
            iconSize: theme.iconSize + 8,
            color: theme.foreground,
            tooltip: 'Forward ${skipStep.inSeconds}s',
            icon: Icon(icons.forward),
            onPressed: () => controller.seekBy(skipStep),
          ),
      ],
    );
  }
}

final class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller, required this.theme});

  final PlayerControlsController controller;
  final PlayerControlsTheme theme;

  @override
  Widget build(BuildContext context) {
    final icons = theme.icons;

    return ColoredBox(
      color: theme.scrim,
      child: Padding(
        padding: theme.contentPadding,
        child: controller.canSeek
            ? Row(
                children: <Widget>[
                  // YouTube-Android order: elapsed, slider, duration, then the
                  // glyphs at the end of the same row.
                  Expanded(
                    child: PlayerTimeline(controller: controller, theme: theme, barHeight: 26),
                  ),
                  PlayerIconButton(
                    icon: icons.volumeFor(muted: controller.isMuted),
                    theme: theme,
                    tooltip: controller.isMuted ? 'Unmute' : 'Mute',
                    onPressed: controller.toggleMute,
                  ),
                  PlayerIconButton(
                    icon: icons.fullscreenFor(active: controller.actions.canExitFullscreen),
                    theme: theme,
                    tooltip: 'Fullscreen',
                    onPressed: controller.actions.canExitFullscreen
                        ? controller.exitFullscreen
                        : (controller.actions.canEnterFullscreen ? controller.enterFullscreen : null),
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  if (controller.isLive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: theme.accent, borderRadius: BorderRadius.circular(3)),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFFFFFF)),
                      ),
                    ),
                  const Spacer(),
                  PlayerIconButton(
                    icon: icons.volumeFor(muted: controller.isMuted),
                    theme: theme,
                    tooltip: controller.isMuted ? 'Unmute' : 'Mute',
                    onPressed: controller.toggleMute,
                  ),
                  if (controller.actions.canEnterFullscreen)
                    PlayerIconButton(
                      icon: icons.fullscreen,
                      theme: theme,
                      tooltip: 'Fullscreen',
                      onPressed: controller.enterFullscreen,
                    ),
                ],
              ),
      ),
    );
  }
}
