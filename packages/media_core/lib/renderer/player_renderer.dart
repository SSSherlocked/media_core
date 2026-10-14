import 'package:flutter/widgets.dart';
import 'package:media_core/renderer/player_overlay.dart';
import 'package:media_core/renderer/player_surface.dart';

/// Root composition widget for the renderer.
///
/// `PlayerRenderer` combines the rendering surface with an optional
/// overlay layer.
///
/// It is intentionally a UI composition boundary and does not own
/// renderer lifecycle or playback state.
///
/// Responsibilities:
///
/// - compose the rendering surface
/// - compose the optional overlay
/// - provide a stable widget boundary for renderer consumers
///
/// Does not:
///
/// - control playback
/// - create platform rendering resources
/// - manage renderer state
/// - calculate video geometry
final class PlayerRenderer extends StatelessWidget {
  /// Stacks [overlay] above the surface that renders [child].
  ///
  /// The overlay is optional so a host that composes its own controls above the
  /// renderer pays nothing for a second layer.
  const PlayerRenderer({
    required this.child,
    super.key,
    this.overlay,
    this.alignment = Alignment.center,
    this.fit = BoxFit.contain,
    this.mirror = false,
    this.backgroundColor,
  });

  /// Actual video rendering widget.
  final Widget child;

  /// Optional content displayed above the rendering surface.
  final Widget? overlay;

  /// Alignment of the rendered content.
  final AlignmentGeometry alignment;

  /// How the rendered content is fitted into the available space.
  final BoxFit fit;

  /// Whether the rendered image should be mirrored horizontally.
  final bool mirror;

  /// Background color of the rendering surface.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PlayerSurface(alignment: alignment, fit: fit, mirror: mirror, backgroundColor: backgroundColor, child: child),
        if (overlay != null) PlayerOverlay(child: overlay!),
      ],
    );
  }
}
