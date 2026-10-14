import 'package:flutter/widgets.dart';

/// Base surface used by the renderer to host video output.
///
/// `PlayerSurface` intentionally does not know about any concrete
/// media-player backend or platform rendering implementation.
///
/// A platform-specific renderer can provide its rendering widget through
/// [child].
///
/// Responsibilities:
///
/// - provide a stable rendering surface boundary
/// - apply basic renderer presentation options
/// - host the actual rendering widget
///
/// Does not:
///
/// - create a native texture or platform view
/// - control playback
/// - calculate video geometry
/// - manage renderer lifecycle
final class PlayerSurface extends StatelessWidget {
  /// Wraps the backend's [child] in the surface framing: fit, alignment,
  /// optional mirroring and a background for the time before frames arrive.
  const PlayerSurface({
    required this.child,
    super.key,
    this.alignment = Alignment.center,
    this.fit = BoxFit.contain,
    this.mirror = false,
    this.backgroundColor,
  });

  /// Actual video rendering widget.
  ///
  /// This is normally supplied by a media backend or platform adapter.
  final Widget child;

  /// Alignment of the rendering content.
  final AlignmentGeometry alignment;

  /// How the rendering content is fitted into the available surface.
  final BoxFit fit;

  /// Whether the rendered image should be mirrored horizontally.
  final bool mirror;

  /// Background color of the surface.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    Widget content = FittedBox(fit: fit, alignment: alignment, clipBehavior: Clip.hardEdge, child: child);

    if (mirror) {
      content = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scaleByDouble(-1, 1, 1, 1),
        child: content,
      );
    }

    return ColoredBox(
      color: backgroundColor ?? const Color(0xFF000000),
      child: SizedBox.expand(child: content),
    );
  }
}
