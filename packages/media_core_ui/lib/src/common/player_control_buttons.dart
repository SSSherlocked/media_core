import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:media_core_ui/src/common/player_controls_theme.dart';

/// A control glyph that answers the pointer the way its design language does.
///
/// One implementation, six reactions: Material ripples, Apple dips in opacity,
/// Fluent and Yaru highlight, and soft UI extrudes the button out of the
/// surface at rest and presses it inwards on tap. Keeping that here means a bar
/// composes buttons instead of re-implementing feedback six times.
///
/// Responsibilities:
///
/// - draw one glyph
/// - answer hover, press and disabled states per [PlayerControlButtonSkin]
///
/// It does not:
///
/// - know what the button does (the caller passes the callback)
/// - hold playback state
final class PlayerIconButton extends StatefulWidget {
  /// Creates a control button.
  const PlayerIconButton({
    required this.icon,
    required this.theme,
    super.key,
    this.onPressed,
    this.size,
    this.color,
    this.tooltip,
    this.semanticLabel,
    this.active = false,
    this.prominent = false,
    this.padding,
  });

  /// Glyph to draw.
  final IconData icon;

  /// Colors, metrics and the button skin.
  final PlayerControlsTheme theme;

  /// Action; null renders the button disabled.
  final VoidCallback? onPressed;

  /// Glyph size; defaults to the theme's regular icon size.
  final double? size;

  /// Glyph color; defaults to the theme's foreground.
  final Color? color;

  /// Tooltip text.
  ///
  /// Desktop languages expect one on every control; touch styles usually have
  /// none, and passing null on them is the honest default.
  final String? tooltip;

  /// Accessibility label, when [tooltip] is not enough.
  final String? semanticLabel;

  /// Whether the control reads as "on" (loop enabled, muted, …).
  final bool active;

  /// Whether this is the primary control (play/pause).
  ///
  /// A prominent button is painted as a filled accent disc in the languages
  /// that have one, and gets a larger soft pad in neumorphism.
  final bool prominent;

  /// Padding around the glyph; defaults to the theme's.
  final EdgeInsets? padding;

  @override
  State<PlayerIconButton> createState() => _PlayerIconButtonState();
}

final class _PlayerIconButtonState extends State<PlayerIconButton> {
  bool _hovering = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  PlayerControlsTheme get _theme => widget.theme;

  Color get _glyphColor {
    if (!_enabled) {
      return _theme.foregroundMuted.withValues(alpha: 0.5);
    }

    if (widget.prominent && _theme.buttonSkin == PlayerControlButtonSkin.ripple) {
      return _theme.foreground;
    }

    if (widget.active) {
      return _theme.accent;
    }

    return widget.color ?? _theme.foreground;
  }

  EdgeInsets get _padding {
    if (widget.padding != null) {
      return widget.padding!;
    }

    return switch (_theme.buttonSkin) {
      PlayerControlButtonSkin.soft => const EdgeInsets.all(12),
      PlayerControlButtonSkin.flat => const EdgeInsets.all(8),
      _ => const EdgeInsets.all(6),
    };
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size ?? _theme.iconSize;

    Widget glyph = Icon(widget.icon, size: size, color: _glyphColor);

    if (widget.semanticLabel != null) {
      glyph = Semantics(label: widget.semanticLabel, button: true, child: glyph);
    }

    Widget button = MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: _decorate(glyph),
      ),
    );

    if (_theme.buttonSkin == PlayerControlButtonSkin.ripple) {
      // A ripple needs a Material ancestor; any widget can provide one without
      // affecting the layout it sits in.
      button = Material(type: MaterialType.transparency, child: button);
    }

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip, child: button);
    }

    return button;
  }

  /// Paints the button's reaction to state, per design language.
  Widget _decorate(Widget glyph) {
    final radius = BorderRadius.circular(_theme.controlButtonRadius);
    final highlight = _theme.hoverHighlight;

    switch (_theme.buttonSkin) {
      case PlayerControlButtonSkin.ripple:
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: _padding,
          decoration: BoxDecoration(
            color: widget.prominent ? _theme.accent : const Color(0x00000000),
            borderRadius: BorderRadius.circular(_theme.controlButtonRadius * 0.9),
          ),
          child: _enabled && _pressed ? Opacity(opacity: 0.7, child: glyph) : glyph,
        );

      case PlayerControlButtonSkin.translucent:
        // Apple's reaction is the glyph itself changing, not a box appearing
        // behind it.
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: !_enabled ? 0.4 : (_pressed ? 0.5 : (_hovering ? 0.75 : 1.0)),
          child: Padding(padding: _padding, child: glyph),
        );

      case PlayerControlButtonSkin.hover:
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: _padding,
          decoration: BoxDecoration(
            color: _enabled && (_hovering || _pressed) && highlight != null ? highlight : const Color(0x00000000),
            borderRadius: radius,
          ),
          child: glyph,
        );

      case PlayerControlButtonSkin.flat:
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: _padding,
          decoration: BoxDecoration(
            color: _enabled && (_hovering || _pressed) && highlight != null ? highlight : const Color(0x00000000),
            borderRadius: BorderRadius.circular(_theme.controlButtonRadius),
            border: Border.all(color: _theme.border ?? const Color(0x33FFFFFF)),
          ),
          child: glyph,
        );

      case PlayerControlButtonSkin.soft:
        return SoftSurface(theme: _theme, pressed: _enabled && _pressed, padding: _padding, child: glyph);
    }
  }
}

/// The spinner a bar shows while the stream is loading.
///
/// Shared because every design language shows *something* in the same place —
/// where the play glyph would be — and only the ring's weight and mounting
/// differ: bare over the picture for Material and Cupertino, on a soft pad for
/// soft UI.
final class PlayerBufferingIndicator extends StatelessWidget {
  /// Creates a buffering indicator.
  const PlayerBufferingIndicator({required this.theme, super.key, this.size, this.strokeWidth});

  /// Colors and metrics.
  final PlayerControlsTheme theme;

  /// Diameter of the ring; defaults to the theme's primary glyph size.
  final double? size;

  /// Ring weight; defaults to a weight that suits the theme's icon sizes.
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final diameter = size ?? theme.primaryIconSize;

    final ring = SizedBox(
      width: diameter,
      height: diameter,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth ?? (theme.iconSize <= 16 ? 2 : 3),
        valueColor: AlwaysStoppedAnimation<Color>(theme.accent),
        backgroundColor: theme.progressTrack,
      ),
    );

    if (theme.buttonSkin == PlayerControlButtonSkin.soft) {
      return SoftSurface(theme: theme, padding: const EdgeInsets.all(14), child: ring);
    }

    return ring;
  }
}

/// A surface extruded from the background by two opposing shadows.
///
/// This is the whole of neumorphism: one background color, a light shadow from
/// the top-left and a dark one from the bottom-right at rest, swapped into a
/// tight sunken shadow while pressed. It lives here because bars use it for
/// more than buttons — a pill, a groove, a badge.
final class SoftSurface extends StatelessWidget {
  /// Creates an extruded surface.
  const SoftSurface({
    required this.theme,
    required this.child,
    super.key,
    this.pressed = false,
    this.radius,
    this.padding = EdgeInsets.zero,
    this.inset = false,
  });

  /// Theme carrying the surface color and the two shadows.
  final PlayerControlsTheme theme;

  /// Content drawn on the surface.
  final Widget child;

  /// Whether the surface is pressed into the background.
  final bool pressed;

  /// Corner radius; defaults to the theme's control radius.
  final double? radius;

  /// Padding inside the surface.
  final EdgeInsets padding;

  /// Whether the surface is a groove rather than a pad (progress track).
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final depth = theme.shadowDepth;
    final light = theme.shadowLight ?? const Color(0xFFFFFFFF);
    final dark = theme.shadowDark ?? const Color(0xFFC5C8D0);
    final sunk = pressed || inset;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.surface ?? const Color(0xFFEDEFF4),
        borderRadius: BorderRadius.circular(radius ?? theme.controlButtonRadius),
        boxShadow: sunk
            // True inner shadows would need a custom painter; a tight shadow
            // offset opposite the light one reads the same at these sizes.
            ? <BoxShadow>[
                BoxShadow(
                  color: dark.withValues(alpha: 0.55),
                  offset: Offset(depth * 0.35, depth * 0.35),
                  blurRadius: depth,
                ),
              ]
            : <BoxShadow>[
                BoxShadow(color: light, offset: Offset(-depth * 0.6, -depth * 0.6), blurRadius: depth),
                BoxShadow(color: dark, offset: Offset(depth * 0.6, depth * 0.6), blurRadius: depth),
              ],
      ),
      child: child,
    );
  }
}

/// The panel Fluent, macOS and Cupertino chrome sits on.
///
/// Blur is what separates those languages from a plain dark rectangle, and it
/// has to be applied by the panel rather than by every control inside it.
final class PlayerControlsPanel extends StatelessWidget {
  /// Creates a panel.
  const PlayerControlsPanel({
    required this.theme,
    required this.child,
    super.key,
    this.padding,
    this.radius,
    this.fullWidth = false,
    this.border = true,
  });

  /// Theme carrying the surface color, border and blur.
  final PlayerControlsTheme theme;

  /// Content of the panel.
  final Widget child;

  /// Padding inside the panel; defaults to the theme's pill padding.
  final EdgeInsets? padding;

  /// Corner radius; full-width panels default to square corners.
  final double? radius;

  /// Whether the panel spans the picture or floats inside it.
  final bool fullWidth;

  /// Whether a hairline border is drawn.
  final bool border;

  @override
  Widget build(BuildContext context) {
    final blur = theme.blur;
    final corner = radius ?? (fullWidth ? 0 : 12);
    final edge = theme.border;

    Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface ?? theme.scrim,
        borderRadius: BorderRadius.circular(corner),
        border: border && edge != null ? Border.all(color: edge) : null,
      ),
      child: Padding(padding: padding ?? (fullWidth ? theme.contentPadding : theme.pillPadding), child: child),
    );

    if (blur != null) {
      panel = ClipRRect(
        borderRadius: BorderRadius.circular(corner),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: panel,
        ),
      );
    }

    return panel;
  }
}
