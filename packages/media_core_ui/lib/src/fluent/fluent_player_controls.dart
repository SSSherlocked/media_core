import 'package:flutter/material.dart';

import 'package:media_core_ui/src/common/player_control_buttons.dart';
import 'package:media_core_ui/src/common/player_controls_controller.dart';
import 'package:media_core_ui/src/common/player_controls_theme.dart';
import 'package:media_core_ui/src/common/player_progress_bar.dart';

/// Control set in the Fluent Design (Windows 11) idiom.
///
/// What makes it read as Fluent rather than as a dark toolbar:
///
/// - an acrylic panel: translucent, blurred, with a hairline border and 4–8 px
///   radii — the "material" of Fluent;
/// - the panel is inset from the picture instead of spanning it, and the
///   controls are revealed by the pointer rather than by a tap;
/// - a thin progress track whose dot is small at rest and grows under the
///   pointer;
/// - outlined, 16 px glyphs and a hover highlight on every control, with
///   tooltips, because a mouse user points at what they are about to click;
/// - accent-blue for progress and toggled controls, the Fluent light accent;
/// - a volume slider on the same row and a top-right menu for the occasional
///   actions.
///
/// ```dart
/// MediaCorePlayerView(handle: handle, style: PlayerControlsStyle.fluent)
/// ```
final class FluentPlayerControls extends StatelessWidget {
  /// Creates the Fluent control set.
  const FluentPlayerControls({
    required this.controller,
    super.key,
    this.theme,
    this.showTitle = true,
    this.showVolumeSlider = true,
    this.showMenu = true,
    this.padding = EdgeInsets.zero,
  });

  /// Playback state and actions.
  final PlayerControlsController controller;

  /// Colors and metrics; defaults to [PlayerControlsTheme.fluent].
  final PlayerControlsTheme? theme;

  /// Whether the title rides in the top row.
  final bool showTitle;

  /// Whether a volume slider is offered.
  final bool showVolumeSlider;

  /// Whether the top-right menu is offered.
  final bool showMenu;

  /// Padding around the whole set.
  final EdgeInsets padding;

  PlayerControlsTheme get _theme => theme ?? const PlayerControlsTheme.fluent();

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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (showTitle || showMenu)
                  Align(
                    alignment: Alignment.topRight,
                    child: PlayerControlsPanel(
                      theme: theme,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (showTitle && controller.title != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 260),
                                child: Text(
                                  controller.title!,
                                  style: theme.titleTextStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          if (showMenu) FluentOverflowMenu(controller: controller, theme: theme),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: PlayerControlsPanel(
                      theme: theme,
                      radius: 6,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: _TransportRow(controller: controller, theme: theme, showVolumeSlider: showVolumeSlider),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The top-right menu, in Fluent's plain-menu style.
///
/// Public because the macOS and Yaru sets offer the same actions and should
/// look like their own platform while doing it — a host can also place it
/// somewhere else entirely.
final class FluentOverflowMenu extends StatelessWidget {
  /// Creates the menu.
  const FluentOverflowMenu({required this.controller, required this.theme, super.key});

  /// Playback state and actions.
  final PlayerControlsController controller;

  /// Colors and metrics.
  final PlayerControlsTheme theme;

  @override
  Widget build(BuildContext context) {
    final icons = theme.icons;

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll<Color>(Color(0xF21C1C1C)),
        shape: WidgetStatePropertyAll<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
      ),
      menuChildren: <Widget>[
        if (controller.canSeek) ...<Widget>[
          _MenuHeader(text: 'Playback speed', theme: theme),
          for (final rate in PlayerControlsController.defaultRates)
            MenuItemButton(
              leadingIcon: Icon(
                (controller.rate - rate).abs() < 0.001 ? Icons.check : icons.speed,
                size: theme.compactIconSize,
                color: theme.foreground,
              ),
              onPressed: () => controller.setRate(rate),
              child: Text('${rate}x', style: theme.timeTextStyle),
            ),
          const Divider(height: 1, color: Color(0x33FFFFFF)),
        ],
        MenuItemButton(
          leadingIcon: Icon(
            icons.loop,
            size: theme.compactIconSize,
            color: controller.isLooping ? theme.accent : theme.foreground,
          ),
          onPressed: controller.toggleLoop,
          child: Text('Loop', style: theme.timeTextStyle),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            controller.isAudioOnly ? Icons.music_note : Icons.music_note_outlined,
            size: theme.compactIconSize,
            color: controller.isAudioOnly ? theme.accent : theme.foreground,
          ),
          onPressed: () => controller.setAudioOnly(value: !controller.isAudioOnly),
          child: Text('Audio only', style: theme.timeTextStyle),
        ),
        if (controller.canCaptureScreenshot)
          MenuItemButton(
            leadingIcon: Icon(icons.screenshot, size: theme.compactIconSize, color: theme.foreground),
            onPressed: controller.captureScreenshot,
            child: Text('Save frame', style: theme.timeTextStyle),
          ),
        if (controller.actions.canEnterFloating)
          MenuItemButton(
            leadingIcon: Icon(icons.floatingWindow, size: theme.compactIconSize, color: theme.foreground),
            onPressed: controller.enterFloating,
            child: Text('Floating window', style: theme.timeTextStyle),
          ),
      ],
      builder: (context, menuController, child) {
        return PlayerIconButton(
          icon: icons.more,
          theme: theme,
          tooltip: 'More',
          padding: const EdgeInsets.all(4),
          onPressed: () => menuController.isOpen ? menuController.close() : menuController.open(),
        );
      },
    );
  }
}

final class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.text, required this.theme});

  final String text;
  final PlayerControlsTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(text, style: theme.timeTextStyle.copyWith(fontSize: 11, color: theme.foregroundMuted)),
    );
  }
}

final class _TransportRow extends StatelessWidget {
  const _TransportRow({required this.controller, required this.theme, required this.showVolumeSlider});

  final PlayerControlsController controller;
  final PlayerControlsTheme theme;
  final bool showVolumeSlider;

  @override
  Widget build(BuildContext context) {
    final icons = theme.icons;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (controller.canSeek)
          SizedBox(
            width: 420,
            child: PlayerTimeline(controller: controller, theme: theme, hoverable: true, barHeight: 18),
          )
        else if (controller.isLive)
          Text('LIVE', style: theme.timeTextStyle.copyWith(color: theme.accent)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PlayerIconButton(
              icon: icons.transportFor(playing: controller.isPlaying),
              theme: theme,
              size: theme.primaryIconSize,
              tooltip: controller.isPlaying ? 'Pause (space)' : 'Play (space)',
              onPressed: controller.togglePlayPause,
            ),
            PlayerIconButton(
              icon: icons.skipBack,
              theme: theme,
              tooltip: 'Back 10s (j)',
              onPressed: () => controller.seekBy(-const Duration(seconds: 10)),
            ),
            PlayerIconButton(
              icon: icons.skipForward,
              theme: theme,
              tooltip: 'Forward 10s (l)',
              onPressed: () => controller.seekBy(const Duration(seconds: 10)),
            ),
            if (showVolumeSlider) ...<Widget>[
              PlayerIconButton(
                icon: icons.volumeFor(muted: controller.isMuted),
                theme: theme,
                tooltip: controller.isMuted ? 'Unmute (m)' : 'Mute (m)',
                onPressed: controller.toggleMute,
              ),
              SizedBox(
                width: 84,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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
              const SizedBox(width: 6),
            ],
            Text('${controller.rate}x', style: theme.timeTextStyle),
            const SizedBox(width: 10),
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
              tooltip: controller.actions.canExitFullscreen ? 'Leave fullscreen (esc)' : 'Fullscreen (f)',
              onPressed: controller.actions.canExitFullscreen
                  ? controller.exitFullscreen
                  : (controller.actions.canEnterFullscreen ? controller.enterFullscreen : null),
            ),
          ],
        ),
      ],
    );
  }
}
