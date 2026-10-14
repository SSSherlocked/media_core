import 'package:flutter/material.dart';

import 'package:media_core_ui/src/common/player_control_buttons.dart';
import 'package:media_core_ui/src/common/player_controls_controller.dart';
import 'package:media_core_ui/src/common/player_controls_theme.dart';
import 'package:media_core_ui/src/common/player_progress_bar.dart';

/// Control set in the Neumorphism (soft UI) idiom.
///
/// Neumorphism is not a platform convention, it is a surface treatment: one
/// background color for everything, and every element extruded out of it with a
/// light shadow from one side and a dark one from the other. The rules that
/// follow from that, and that this set obeys:
///
/// - **one surface color.** There is no scrim and no panel; the host paints the
///   page in `theme.surface` and the controls are the same color, so the
///   background behind the video has to match or the effect falls apart — see
///   [PlayerControlsTheme.neumorphic] and `surface`.
/// - **no blur, no hard borders.** Depth comes from shadows, never from lines.
/// - **an inset groove for the track.** The progress bar is pressed *into* the
///   surface instead of lying on it, which is the one place soft UI inverts its
///   own rule.
/// - **pads, not buttons.** Every control is a circular pad that looks raised at
///   rest and sinks while pressed.
/// - **muted contrast.** Text and glyphs are mid-gray rather than white;
///   neumorphism has no pure black and no pure white.
///
/// Because soft UI needs room for its shadows, this set is roomier than the
/// others: bigger pads, wider gaps, and a bottom row that keeps the transport
/// apart from the secondary actions.
///
/// ```dart
/// MediaCorePlayerView(
///   handle: handle,
///   style: PlayerControlsStyle.neumorphic,
///   theme: PlayerControlsTheme.neumorphic().copyWith(surface: myPageColor),
/// )
/// ```
final class NeumorphicPlayerControls extends StatelessWidget {
  /// Creates the soft-UI control set.
  const NeumorphicPlayerControls({
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

  /// Colors and metrics; defaults to [PlayerControlsTheme.neumorphic].
  final PlayerControlsTheme? theme;

  /// Whether the title is shown on a raised plate.
  final bool showTitle;

  /// Whether ±15 s pads flank the play pad.
  final bool showSkipButtons;

  /// Amount the skip pads jump.
  final Duration skipStep;

  /// Padding around the whole set.
  final EdgeInsets padding;

  PlayerControlsTheme get _theme => theme ?? const PlayerControlsTheme.neumorphic();

  @override
  Widget build(BuildContext context) {
    final theme = _theme;

    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Padding(
            padding: padding,
            child: Column(
              children: <Widget>[
                if (showTitle && controller.title != null)
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.all(theme.contentPadding.horizontal / 2),
                      child: SoftSurface(
                        theme: theme,
                        radius: theme.controlButtonRadius + 4,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Text(
                            controller.title!,
                            style: theme.titleTextStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: _CenterPads(
                    controller: controller,
                    theme: theme,
                    showSkipButtons: showSkipButtons,
                    skipStep: skipStep,
                  ),
                ),
                _BottomPlate(controller: controller, theme: theme),
              ],
            ),
          );
        },
      ),
    );
  }
}

final class _CenterPads extends StatelessWidget {
  const _CenterPads({
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
      return PlayerBufferingIndicator(theme: theme, size: theme.primaryIconSize + 8);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (showSkipButtons)
          PlayerIconButton(
            icon: icons.rewind,
            theme: theme,
            size: theme.iconSize + 2,
            tooltip: 'Back ${skipStep.inSeconds}s',
            onPressed: () => controller.seekBy(-skipStep),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: PlayerIconButton(
            icon: icons.transportFor(playing: controller.isPlaying),
            theme: theme,
            size: theme.primaryIconSize,
            tooltip: controller.isPlaying ? 'Pause' : 'Play',
            prominent: true,
            padding: const EdgeInsets.all(18),
            onPressed: controller.togglePlayPause,
          ),
        ),
        if (showSkipButtons)
          PlayerIconButton(
            icon: icons.forward,
            theme: theme,
            size: theme.iconSize + 2,
            tooltip: 'Forward ${skipStep.inSeconds}s',
            onPressed: () => controller.seekBy(skipStep),
          ),
      ],
    );
  }
}

final class _BottomPlate extends StatelessWidget {
  const _BottomPlate({required this.controller, required this.theme});

  final PlayerControlsController controller;
  final PlayerControlsTheme theme;

  @override
  Widget build(BuildContext context) {
    final icons = theme.icons;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: theme.contentPadding.horizontal,
        vertical: theme.contentPadding.vertical / 2,
      ),
      child: SoftSurface(
        theme: theme,
        // The plate is intentionally roomier than the other sets: soft UI needs
        // the gap for its shadows to read as depth.
        radius: theme.controlButtonRadius + 6,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (controller.canSeek)
              PlayerTimeline(controller: controller, theme: theme, barHeight: 26)
            else if (controller.isLive)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('LIVE', style: theme.timeTextStyle.copyWith(fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                PlayerIconButton(
                  icon: icons.volumeFor(muted: controller.isMuted),
                  theme: theme,
                  tooltip: controller.isMuted ? 'Unmute' : 'Mute',
                  onPressed: controller.toggleMute,
                ),
                PlayerIconButton(
                  icon: icons.loop,
                  theme: theme,
                  active: controller.isLooping,
                  tooltip: 'Loop',
                  onPressed: controller.toggleLoop,
                ),
                PlayerIconButton(
                  icon: icons.speed,
                  theme: theme,
                  tooltip: 'Playback speed',
                  onPressed: controller.cycleRate,
                ),
                Text('${controller.rate}x', style: theme.timeTextStyle),
                const SizedBox(width: 8),
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
                PlayerIconButton(
                  icon: icons.fullscreenFor(active: controller.actions.canExitFullscreen),
                  theme: theme,
                  tooltip: controller.actions.canExitFullscreen ? 'Leave fullscreen' : 'Fullscreen',
                  onPressed: controller.actions.canExitFullscreen
                      ? controller.exitFullscreen
                      : (controller.actions.canEnterFullscreen ? controller.enterFullscreen : null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
