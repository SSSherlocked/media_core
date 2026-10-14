import 'package:flutter/cupertino.dart';

import 'package:media_core_ui/src/common/player_control_buttons.dart';
import 'package:media_core_ui/src/common/player_controls_controller.dart';
import 'package:media_core_ui/src/common/player_controls_theme.dart';
import 'package:media_core_ui/src/common/player_progress_bar.dart';

/// Control set in the Cupertino / Human Interface Guidelines idiom.
///
/// What makes it read as iOS rather than as "dark buttons":
///
/// - a single large glyph in the middle, where the thumb already is, instead of
///   a row of small buttons;
/// - the right-hand time counts *down* and is prefixed with a minus, so the
///   viewer reads "how much is left", not "how long it was";
/// - a hairline progress bar with no thumb at all, which thickens only while it
///   is being dragged;
/// - a buffering spinner in place of the play glyph, not on top of it;
/// - gradient scrims instead of panels, so the picture stays visible behind the
///   controls;
/// - no volume slider: iOS volume is the hardware buttons, and a second control
///   for it would be a lie.
///
/// ```dart
/// MediaCorePlayerView(handle: handle, style: PlayerControlsStyle.cupertino)
/// ```
final class CupertinoPlayerControls extends StatelessWidget {
  /// Creates the Cupertino control set.
  const CupertinoPlayerControls({
    required this.controller,
    super.key,
    this.theme,
    this.showTitle = true,
    this.showSkipButtons = true,
    this.skipStep = const Duration(seconds: 15),
    this.padding = EdgeInsets.zero,
  });

  /// Playback state and actions.
  final PlayerControlsController controller;

  /// Colors and metrics; defaults to [PlayerControlsTheme.cupertino].
  final PlayerControlsTheme? theme;

  /// Whether the title rides in the top bar.
  final bool showTitle;

  /// Whether the ±15 s buttons flank the play button.
  final bool showSkipButtons;

  /// Amount the skip buttons jump.
  final Duration skipStep;

  /// Padding around the whole set.
  final EdgeInsets padding;

  PlayerControlsTheme get _theme => theme ?? const PlayerControlsTheme.cupertino();

  @override
  Widget build(BuildContext context) {
    final theme = _theme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Padding(
          padding: padding,
          child: Column(
            children: <Widget>[
              _TopBar(controller: controller, theme: theme, showTitle: showTitle),
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
    );
  }
}

final class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.theme, required this.showTitle});

  final PlayerControlsController controller;
  final PlayerControlsTheme theme;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final title = controller.title;
    final icons = theme.icons;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x99000000), Color(0x00000000)],
        ),
      ),
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
            if (controller.actions.canEnterPip)
              PlayerIconButton(
                icon: icons.pictureInPicture,
                theme: theme,
                tooltip: 'Picture in picture',
                onPressed: controller.enterPip,
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
        ),
      ),
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
      // The spinner *replaces* the glyph: a play button that does nothing while
      // the stream loads is the classic way to make a viewer tap twice.
      return CupertinoActivityIndicator(radius: theme.primaryIconSize / 3, color: theme.foreground);
    }

    final seconds = skipStep.inSeconds;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (showSkipButtons)
          PlayerIconButton(
            icon: seconds <= 10
                ? CupertinoIcons.gobackward_10
                : (seconds >= 45 ? CupertinoIcons.gobackward_45 : icons.rewind),
            theme: theme,
            size: theme.primaryIconSize * 0.6,
            tooltip: 'Back ${seconds}s',
            onPressed: () => controller.seekBy(-skipStep),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: PlayerIconButton(
            icon: icons.transportFor(playing: controller.isPlaying),
            theme: theme,
            size: theme.primaryIconSize,
            tooltip: controller.isPlaying ? 'Pause' : 'Play',
            onPressed: controller.togglePlayPause,
          ),
        ),
        if (showSkipButtons)
          PlayerIconButton(
            icon: seconds <= 10
                ? CupertinoIcons.goforward_10
                : (seconds >= 45 ? CupertinoIcons.goforward_45 : icons.forward),
            theme: theme,
            size: theme.primaryIconSize * 0.6,
            tooltip: 'Forward ${seconds}s',
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

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Color(0x99000000), Color(0x00000000)],
        ),
      ),
      child: Padding(
        padding: theme.contentPadding,
        child: Column(
          children: <Widget>[
            if (controller.canSeek)
              // Remaining time on the right is the iOS convention.
              PlayerTimeline(controller: controller, theme: theme, showRemaining: true, barHeight: 22),
            Row(
              children: <Widget>[
                PlayerIconButton(
                  icon: icons.volumeFor(muted: controller.isMuted),
                  theme: theme,
                  tooltip: controller.isMuted ? 'Unmute' : 'Mute',
                  onPressed: controller.toggleMute,
                ),
                if (controller.canCaptureScreenshot)
                  PlayerIconButton(
                    icon: icons.screenshot,
                    theme: theme,
                    tooltip: 'Save frame',
                    onPressed: controller.captureScreenshot,
                  ),
                const Spacer(),
                if (controller.actions.canEnterFullscreen && !controller.actions.canExitFullscreen)
                  PlayerIconButton(
                    icon: icons.fullscreen,
                    theme: theme,
                    tooltip: 'Fullscreen',
                    onPressed: controller.enterFullscreen,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
