import 'package:flutter/material.dart';

import 'package:media_core_ui/src/common/player_control_buttons.dart';
import 'package:media_core_ui/src/common/player_controls_controller.dart';
import 'package:media_core_ui/src/common/player_controls_theme.dart';
import 'package:media_core_ui/src/common/player_progress_bar.dart';
import 'package:media_core_ui/src/fluent/fluent_player_controls.dart' show FluentOverflowMenu;

/// Control set in the Yaru (Ubuntu) idiom.
///
/// What makes it read as an Ubuntu/GNOME player:
///
/// - a **header bar** at the top carrying the title and the window-ish actions,
///   which is how GTK apps put their chrome — plus a client-side close/expand
///   pair at the right end;
/// - flat controls with a hairline border and square-ish 6 px radii, not pills;
/// - Ubuntu orange (Yaru's `#E95420`) as the accent on progress and toggles;
/// - a thick progress track with a round thumb, because Yaru's scales are
///   chunky and grabbable;
/// - a volume slider on the same row, as GNOME's players have;
/// - hover highlights instead of ripples: GTK has no ink.
///
/// ```dart
/// MediaCorePlayerView(handle: handle, style: PlayerControlsStyle.yaru)
/// ```
final class YaruPlayerControls extends StatelessWidget {
  /// Creates the Yaru control set.
  const YaruPlayerControls({
    required this.controller,
    super.key,
    this.theme,
    this.showTitle = true,
    this.showHeaderBar = true,
    this.showVolumeSlider = true,
    this.showMenu = true,
    this.padding = EdgeInsets.zero,
  });

  /// Playback state and actions.
  final PlayerControlsController controller;

  /// Colors and metrics; defaults to [PlayerControlsTheme.yaru].
  final PlayerControlsTheme? theme;

  /// Whether the title rides in the header bar.
  final bool showTitle;

  /// Whether the GTK header bar is drawn at all.
  ///
  /// A host that already gives its window a header bar (via `yaru`'s
  /// `YaruWindowTitleBar`) turns this off and keeps the transport row.
  final bool showHeaderBar;

  /// Whether a volume slider is offered.
  final bool showVolumeSlider;

  /// Whether the overflow menu is offered in the header bar.
  final bool showMenu;

  /// Padding around the whole set.
  final EdgeInsets padding;

  PlayerControlsTheme get _theme => theme ?? const PlayerControlsTheme.yaru();

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
                if (showHeaderBar)
                  _HeaderBar(controller: controller, theme: theme, showTitle: showTitle, showMenu: showMenu),
                const Spacer(),
                _TransportBar(controller: controller, theme: theme, showVolumeSlider: showVolumeSlider),
              ],
            ),
          );
        },
      ),
    );
  }
}

final class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.controller, required this.theme, required this.showTitle, required this.showMenu});

  final PlayerControlsController controller;
  final PlayerControlsTheme theme;
  final bool showTitle;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final title = controller.title;
    final icons = theme.icons;

    return PlayerControlsPanel(
      theme: theme,
      fullWidth: true,
      radius: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          if (showTitle && title != null)
            Expanded(
              child: Text(
                title,
                style: theme.titleTextStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
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
          if (showMenu) FluentOverflowMenu(controller: controller, theme: theme),
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
    );
  }
}

final class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.controller, required this.theme, required this.showVolumeSlider});

  final PlayerControlsController controller;
  final PlayerControlsTheme theme;
  final bool showVolumeSlider;

  @override
  Widget build(BuildContext context) {
    final icons = theme.icons;

    return PlayerControlsPanel(
      theme: theme,
      fullWidth: true,
      radius: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: <Widget>[
          if (controller.canSeek)
            PlayerTimeline(controller: controller, theme: theme, hoverable: true, barHeight: 22)
          else if (controller.isLive)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'LIVE',
                  style: theme.timeTextStyle.copyWith(color: theme.accent, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          Row(
            children: <Widget>[
              PlayerIconButton(
                icon: icons.skipBack,
                theme: theme,
                tooltip: 'Back 10s',
                onPressed: () => controller.seekBy(-const Duration(seconds: 10)),
              ),
              PlayerIconButton(
                icon: icons.transportFor(playing: controller.isPlaying),
                theme: theme,
                size: theme.primaryIconSize,
                tooltip: controller.isPlaying ? 'Pause (space)' : 'Play (space)',
                onPressed: controller.togglePlayPause,
              ),
              PlayerIconButton(
                icon: icons.skipForward,
                theme: theme,
                tooltip: 'Forward 10s',
                onPressed: () => controller.seekBy(const Duration(seconds: 10)),
              ),
              const SizedBox(width: 8),
              if (showVolumeSlider) ...<Widget>[
                PlayerIconButton(
                  icon: icons.volumeFor(muted: controller.isMuted),
                  theme: theme,
                  tooltip: controller.isMuted ? 'Unmute (m)' : 'Mute (m)',
                  onPressed: controller.toggleMute,
                ),
                SizedBox(
                  width: 96,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
                      activeTrackColor: theme.accent,
                      inactiveTrackColor: theme.progressTrack,
                      thumbColor: theme.progressThumb,
                    ),
                    child: Slider(
                      value: controller.isMuted ? 0 : controller.volume.clamp(0.0, 1.0),
                      onChanged: controller.setVolume,
                    ),
                  ),
                ),
              ] else
                PlayerIconButton(
                  icon: icons.volumeFor(muted: controller.isMuted),
                  theme: theme,
                  tooltip: controller.isMuted ? 'Unmute (m)' : 'Mute (m)',
                  onPressed: controller.toggleMute,
                ),
              const Spacer(),
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
            ],
          ),
        ],
      ),
    );
  }
}
