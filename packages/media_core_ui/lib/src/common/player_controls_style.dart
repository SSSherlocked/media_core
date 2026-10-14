import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:media_core_ui/src/common/player_control_icons.dart' show PlayerControlIcons;

/// Visual language of a control set.
///
/// These are design languages, not devices: a host picks the look it wants and
/// gets it on every platform (`style: PlayerControlsStyle.neumorphic` on
/// Android is a legitimate choice), while [forPlatform] picks the one a
/// platform's users expect by default.
///
/// The sets share one control layer — state, actions, visibility, keyboard —
/// and differ in the parts a viewer actually perceives:
///
/// | style | surface | progress | buttons | notes |
/// | --- | --- | --- | --- | --- |
/// | [material] | solid scrim, top app bar, overflow menu | thick track, always-visible thumb | ripple | Material 3 accent |
/// | [cupertino] | top/bottom gradient over the picture | hairline that thickens while dragging | opacity dip | counts the time *down* |
/// | [fluent] | acrylic-like translucent panel, thin dividers | thin track, dot that grows | hover reveal + tooltips | volume slider, top-right menu |
/// | [macos] | floating translucent pill | thin track with a small knob | hover, very compact | title in the pill, no full-width bars |
/// | [yaru] | header bar + flat bottom bar | thick track with a round thumb | flat, bordered | Ubuntu orange accent |
/// | [neumorphic] | soft, extruded from one background color | inset groove | soft circular pads, dual shadows | no blur, no pure black |
///
/// Each set is implemented with Flutter primitives rather than the upstream
/// packages (`fluent_ui`, `macos_ui`, `yaru`, …): one dependency-light package
/// that renders the same inside any host tree beats four widget kits that each
/// want their own theme wrapper. Geometry, color, weight and motion follow the
/// language; the glyphs come from [PlayerControlIcons], which a host that
/// already depends on one of those kits can replace with its own icon set.
enum PlayerControlsStyle {
  /// Material Design (Android, ChromeOS, web).
  material,

  /// Apple's Cupertino / Human Interface Guidelines (iOS).
  cupertino,

  /// Fluent Design (Windows 11).
  fluent,

  /// macOS desktop conventions (Big Sur and later).
  macos,

  /// Yaru, Ubuntu's GTK theme.
  yaru,

  /// Soft UI: monochrome surfaces extruded by opposing shadows.
  ///
  /// Never selected automatically: it is a stylistic statement, not a platform
  /// convention.
  neumorphic;

  /// Style a platform's users expect.
  ///
  /// Linux maps to [yaru] because Ubuntu is what ships Yaru; a host on another
  /// distribution passes [material] or [fluent] explicitly.
  static PlayerControlsStyle forPlatform(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android || TargetPlatform.fuchsia => PlayerControlsStyle.material,
      TargetPlatform.iOS => PlayerControlsStyle.cupertino,
      TargetPlatform.macOS => PlayerControlsStyle.macos,
      TargetPlatform.windows => PlayerControlsStyle.fluent,
      TargetPlatform.linux => PlayerControlsStyle.yaru,
    };
  }

  /// Style for the current platform.
  ///
  /// Web is reported as [fluent]: a browser is driven by a pointer and a
  /// keyboard even when the device under it is a phone.
  static PlayerControlsStyle resolve([TargetPlatform? platform]) {
    if (kIsWeb && platform == null) {
      return PlayerControlsStyle.fluent;
    }

    return forPlatform(platform ?? defaultTargetPlatform);
  }

  /// Whether the style is designed for fingers.
  bool get isTouch {
    return switch (this) {
      PlayerControlsStyle.material || PlayerControlsStyle.cupertino || PlayerControlsStyle.neumorphic => true,
      PlayerControlsStyle.fluent || PlayerControlsStyle.macos || PlayerControlsStyle.yaru => false,
    };
  }

  /// Whether the pointer is what reveals the controls.
  ///
  /// Desktop languages hide their chrome while the viewer is just watching; a
  /// touch style keeps it until the timer or a tap hides it.
  bool get revealsOnHover {
    return switch (this) {
      PlayerControlsStyle.fluent || PlayerControlsStyle.macos || PlayerControlsStyle.yaru => true,
      _ => false,
    };
  }

  /// Whether the style offers a volume slider.
  ///
  /// Touch platforms do not: their volume belongs to the hardware buttons, and
  /// a slider inside the player would fight the system panel. Neumorphism is
  /// touch-first by nature, so it mutes instead.
  bool get showsVolumeSlider {
    return switch (this) {
      PlayerControlsStyle.fluent || PlayerControlsStyle.macos || PlayerControlsStyle.yaru => true,
      _ => false,
    };
  }

  /// Whether the style lays its controls out over the whole picture.
  ///
  /// False for [macos], whose controls live in a floating pill at the bottom
  /// rather than in full-width bars.
  bool get usesFullWidthBars => this != PlayerControlsStyle.macos;

  /// Whether the style keeps controls on screen while playback is paused.
  bool get keepsControlsWhilePaused => true;

  /// Whether the style paints a scrim behind its bars.
  ///
  /// False for [neumorphic], which relies on a single background color and
  /// shadows instead of darkening the picture.
  bool get paintsScrim => this != PlayerControlsStyle.neumorphic;
}
