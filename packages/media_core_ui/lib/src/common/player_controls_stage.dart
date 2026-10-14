import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_core/media_core.dart' show MediaPlayerView;
import 'package:media_core_ui/src/common/player_controls_controller.dart';
import 'package:media_core_ui/src/common/player_controls_style.dart';

/// Keyboard shortcuts a desktop player answers to.
///
/// Held separately so a host can show them in a help panel, and so the mapping
/// is testable without a widget tree.
///
/// Conventions followed (they are what mpv, VLC and YouTube all agree on):
///
/// | Key | Action |
/// | --- | --- |
/// | space, k | play / pause |
/// | left, right | seek ∓5 s |
/// | j, l | seek ∓10 s |
/// | up, down | volume ±5 % |
/// | m | mute |
/// | f | fullscreen |
/// | l | (with shift) loop |
/// | escape | leave fullscreen |
final class PlayerShortcuts {
  /// Creates a mapping.
  const PlayerShortcuts({
    this.seekStep = const Duration(seconds: 5),
    this.largeSeekStep = const Duration(seconds: 10),
    this.volumeStep = 0.05,
  });

  /// Step of `left`/`right`.
  final Duration seekStep;

  /// Step of `j`/`l`.
  final Duration largeSeekStep;

  /// Step of `up`/`down`.
  final double volumeStep;

  /// The bindings, keyed by the shortcut.
  Map<ShortcutActivator, VoidCallback> bindings(PlayerControlsController controller) {
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): () => controller.togglePlayPause(),
      const SingleActivator(LogicalKeyboardKey.keyK): () => controller.togglePlayPause(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => controller.seekBy(-seekStep),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => controller.seekBy(seekStep),
      const SingleActivator(LogicalKeyboardKey.keyJ): () => controller.seekBy(-largeSeekStep),
      const SingleActivator(LogicalKeyboardKey.keyL): () => controller.seekBy(largeSeekStep),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => controller.setVolume(controller.volume + volumeStep),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => controller.setVolume(controller.volume - volumeStep),
      const SingleActivator(LogicalKeyboardKey.keyM): () => controller.toggleMute(),
      const SingleActivator(LogicalKeyboardKey.keyF): () => controller.enterFullscreen(),
      const SingleActivator(LogicalKeyboardKey.escape): () => controller.exitFullscreen(),
    };
  }
}

/// Video plus controls, with the visibility policy of the style.
///
/// This is the shell the bars plug into. It owns what every style would
/// otherwise reimplement: when the controls appear, when they hide, what a tap
/// on the video means, and which keys the player answers.
///
/// Responsibilities:
///
/// - stack the controls over the video
/// - reveal on tap or pointer, hide on idle
/// - forward keyboard shortcuts when asked
///
/// It does not:
///
/// - build the bars (the styles do)
/// - own playback state (the controller does)
/// - render video ([MediaPlayerView] does)
final class PlayerControlsStage extends StatefulWidget {
  /// Creates a stage.
  const PlayerControlsStage({
    required this.controller,
    required this.video,
    required this.controls,
    super.key,
    this.style,
    this.onDoubleTap,
    this.keyboardShortcuts = false,
    this.shortcuts = const PlayerShortcuts(),
    this.animationDuration = const Duration(milliseconds: 180),
    this.onTapVideo,
  });

  /// Controller that owns visibility and playback state.
  final PlayerControlsController controller;

  /// The video surface below the controls.
  final Widget video;

  /// The control set above the video.
  final Widget controls;

  /// Style the stage adapts to; defaults to the controller's.
  final PlayerControlsStyle? style;

  /// Double tap / double click on the video.
  ///
  /// Desktop conventions make this fullscreen; touch styles often leave it to
  /// the picture (the zoom gesture lives on the video widget itself).
  final VoidCallback? onDoubleTap;

  /// Whether the player answers keyboard shortcuts.
  final bool keyboardShortcuts;

  /// Shortcut mapping.
  final PlayerShortcuts shortcuts;

  /// Fade duration of the controls.
  final Duration animationDuration;

  /// Called on every tap on the video area, before the visibility toggles.
  final VoidCallback? onTapVideo;

  @override
  State<PlayerControlsStage> createState() => _PlayerControlsStageState();
}

final class _PlayerControlsStageState extends State<PlayerControlsStage> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'PlayerControlsStage');

  PlayerControlsStyle get _style => widget.style ?? widget.controller.style ?? PlayerControlsStyle.resolve();

  @override
  void dispose() {
    _focusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final visible = widget.controller.controlsVisible;

        Widget content = Stack(
          fit: StackFit.expand,
          children: <Widget>[
            widget.video,
            // The controls never eat a drag meant for the video: pointer events
            // only reach them while they are shown.
            IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: widget.animationDuration,
                curve: Curves.easeOut,
                child: widget.controls,
              ),
            ),
          ],
        );

        content = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.onTapVideo?.call();
            widget.controller.toggleControls();
          },
          onDoubleTap: widget.onDoubleTap,
          child: content,
        );

        if (_style.revealsOnHover) {
          content = MouseRegion(onHover: (_) => widget.controller.revealControls(), child: content);
        }

        if (widget.keyboardShortcuts) {
          content = CallbackShortcuts(
            bindings: widget.shortcuts.bindings(widget.controller),
            child: Focus(focusNode: _focusNode, autofocus: true, child: content),
          );
        }

        return content;
      },
    );
  }
}
