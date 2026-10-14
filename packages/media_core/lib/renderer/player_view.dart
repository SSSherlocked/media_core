import 'package:flutter/widgets.dart';
import 'package:media_core/renderer/player_surface.dart';

/// Public widget boundary for displaying a player rendering surface.
///
/// `PlayerView` is intentionally a thin composition layer.
///
/// It does not:
///
/// - own playback state
/// - control the renderer
/// - create platform rendering resources
/// - calculate video geometry
///
/// The actual rendering surface is delegated to [PlayerSurface].
final class PlayerView extends StatelessWidget {
  /// Shows the backend's [child] through a [PlayerSurface] framed as asked.
  const PlayerView({
    required this.child,
    super.key,
    this.alignment = Alignment.center,
    this.fit = BoxFit.contain,
    this.mirror = false,
    this.backgroundColor,
  });

  /// Widget produced by the active rendering backend.
  final Widget child;

  /// Alignment of the rendered content.
  final AlignmentGeometry alignment;

  /// How the rendered content is fitted into the view.
  final BoxFit fit;

  /// Whether to mirror the rendered image horizontally.
  final bool mirror;

  /// Background color of the player view.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return PlayerSurface(
      alignment: alignment,
      fit: fit,
      mirror: mirror,
      backgroundColor: backgroundColor,
      child: child,
    );
  }
}
