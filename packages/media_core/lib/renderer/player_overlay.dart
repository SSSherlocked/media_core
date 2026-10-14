import 'package:flutter/widgets.dart';

/// Overlay layer displayed above the player rendering surface.
///
/// `PlayerOverlay` is a presentation-only widget.
///
/// It does not:
///
/// - control playback
/// - own renderer state
/// - create rendering resources
/// - handle platform-specific player APIs
///
/// The overlay can contain controls, loading indicators, gestures,
/// danmaku, debug information, or other UI supplied by the caller.
final class PlayerOverlay extends StatelessWidget {
  /// Fills the enclosing stack with [child], aligned and pointer-transparent as
  /// asked.
  ///
  /// [ignorePointer] is for content that must not steal touches from what is
  /// underneath it — danmaku, debug text — while controls stay hit-testable.
  const PlayerOverlay({required this.child, super.key, this.alignment = Alignment.center, this.ignorePointer = false});

  /// Overlay content.
  final Widget child;

  /// Alignment of the overlay content.
  final AlignmentGeometry alignment;

  /// Whether the overlay should ignore pointer events.
  final bool ignorePointer;

  @override
  Widget build(BuildContext context) {
    Widget content = Align(alignment: alignment, child: child);

    if (ignorePointer) {
      content = IgnorePointer(child: content);
    }

    return Positioned.fill(child: content);
  }
}
