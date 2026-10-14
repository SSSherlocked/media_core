import 'package:media_core/presentation/presentation_mode.dart';
import 'package:meta/meta.dart';

/// Defines player presentation policies.
///
/// [PresentationPolicy] controls how the player
/// can be presented on different platforms.
///
/// Responsibilities:
///
/// - fullscreen permission
/// - picture-in-picture permission
/// - floating window permission
/// - orientation behavior
/// - system UI behavior
///
/// It does not:
///
/// - enter fullscreen
/// - create PiP window
/// - manage overlays
///
/// Those belong to:
///
/// - PresentationController
/// - FullscreenController
/// - PipController
@immutable
final class PresentationPolicy {
  /// Creates presentation policy.
  const PresentationPolicy({
    this.enabled = true,

    this.allowFullscreen = true,
    this.allowWindowFullscreen = true,

    this.allowPictureInPicture = true,

    this.allowFloatingWindow = true,

    this.autoFullscreenOnLandscape = false,

    this.autoExitFullscreenOnPortrait = false,

    this.lockOrientationInFullscreen = true,

    this.hideSystemUiInFullscreen = true,

    this.restoreSystemUiAfterExit = true,
  });

  /// Mobile default policy.
  const PresentationPolicy.mobile()
    : enabled = true,
      allowFullscreen = true,
      allowWindowFullscreen = true,
      allowPictureInPicture = true,
      allowFloatingWindow = false,
      autoFullscreenOnLandscape = true,
      autoExitFullscreenOnPortrait = true,
      lockOrientationInFullscreen = true,
      hideSystemUiInFullscreen = true,
      restoreSystemUiAfterExit = true;

  /// Desktop default policy.
  const PresentationPolicy.desktop()
    : enabled = true,
      allowFullscreen = true,
      allowWindowFullscreen = true,
      allowPictureInPicture = false,
      allowFloatingWindow = true,
      autoFullscreenOnLandscape = false,
      autoExitFullscreenOnPortrait = false,
      lockOrientationInFullscreen = false,
      hideSystemUiInFullscreen = false,
      restoreSystemUiAfterExit = true;

  /// TV default policy.
  const PresentationPolicy.tv()
    : enabled = true,
      allowFullscreen = true,
      allowWindowFullscreen = true,
      allowPictureInPicture = false,
      allowFloatingWindow = false,
      autoFullscreenOnLandscape = false,
      autoExitFullscreenOnPortrait = false,
      lockOrientationInFullscreen = false,
      hideSystemUiInFullscreen = false,
      restoreSystemUiAfterExit = false;

  /// Allows every presentation mode.
  const PresentationPolicy.unrestricted()
    : enabled = true,
      allowFullscreen = true,
      allowWindowFullscreen = true,
      allowPictureInPicture = true,
      allowFloatingWindow = true,
      autoFullscreenOnLandscape = true,
      autoExitFullscreenOnPortrait = true,
      lockOrientationInFullscreen = true,
      hideSystemUiInFullscreen = true,
      restoreSystemUiAfterExit = true;

  /// Whether presentation management is enabled.
  final bool enabled;

  /// Allow fullscreen mode.
  final bool allowFullscreen;

  /// Whether window-level fullscreen may be entered.
  ///
  /// Separate from [allowFullscreen] so a host can offer "fill the window"
  /// without offering "take over the screen".
  final bool allowWindowFullscreen;

  /// Allow picture-in-picture mode.
  final bool allowPictureInPicture;

  /// Allow floating player window.
  final bool allowFloatingWindow;

  /// Automatically enter fullscreen when
  /// device rotates landscape.
  final bool autoFullscreenOnLandscape;

  /// Automatically exit fullscreen when
  /// device rotates portrait.
  final bool autoExitFullscreenOnPortrait;

  /// Lock orientation while fullscreen.
  final bool lockOrientationInFullscreen;

  /// Hide system UI in fullscreen.
  final bool hideSystemUiInFullscreen;

  /// Restore system UI after exiting fullscreen.
  final bool restoreSystemUiAfterExit;

  /// Whether fullscreen is available.
  bool canFullscreen() {
    return enabled && allowFullscreen;
  }

  /// Whether window-level fullscreen is available.
  bool canWindowFullscreen() {
    return enabled && allowWindowFullscreen;
  }

  /// Whether PiP is available.
  bool canPictureInPicture() {
    return enabled && allowPictureInPicture;
  }

  /// Whether floating mode is available.
  bool canFloating() {
    return enabled && allowFloatingWindow;
  }

  /// Whether requested presentation mode is allowed.
  bool canEnter(PresentationMode mode) {
    switch (mode) {
      case PresentationMode.normal:
        return true;

      case PresentationMode.fullscreen:
        return canFullscreen();

      case PresentationMode.windowFullscreen:
        return canWindowFullscreen();

      case PresentationMode.pip:
        return canPictureInPicture();

      case PresentationMode.floating:
        return canFloating();
    }
  }

  /// Whether transition between two modes is allowed.
  bool canTransition({required PresentationMode current, required PresentationMode target}) {
    if (!enabled) {
      return false;
    }

    if (current == target) {
      return true;
    }

    return canEnter(target);
  }

  /// Whether orientation should lock.
  bool shouldLockOrientation() {
    return enabled && lockOrientationInFullscreen;
  }

  /// Whether system UI should hide.
  bool shouldHideSystemUi() {
    return enabled && hideSystemUiInFullscreen;
  }

  /// Whether system UI should restore.
  bool shouldRestoreSystemUi() {
    return enabled && restoreSystemUiAfterExit;
  }

  /// Whether landscape should trigger fullscreen.
  bool shouldAutoFullscreenOnLandscape() {
    return enabled && autoFullscreenOnLandscape;
  }

  /// Whether portrait should exit fullscreen.
  bool shouldAutoExitFullscreenOnPortrait() {
    return enabled && autoExitFullscreenOnPortrait;
  }

  /// Creates modified policy.
  PresentationPolicy copyWith({
    bool? enabled,

    bool? allowFullscreen,
    bool? allowWindowFullscreen,

    bool? allowPictureInPicture,

    bool? allowFloatingWindow,

    bool? autoFullscreenOnLandscape,

    bool? autoExitFullscreenOnPortrait,

    bool? lockOrientationInFullscreen,

    bool? hideSystemUiInFullscreen,

    bool? restoreSystemUiAfterExit,
  }) {
    return PresentationPolicy(
      enabled: enabled ?? this.enabled,

      allowFullscreen: allowFullscreen ?? this.allowFullscreen,
      allowWindowFullscreen: allowWindowFullscreen ?? this.allowWindowFullscreen,

      allowPictureInPicture: allowPictureInPicture ?? this.allowPictureInPicture,

      allowFloatingWindow: allowFloatingWindow ?? this.allowFloatingWindow,

      autoFullscreenOnLandscape: autoFullscreenOnLandscape ?? this.autoFullscreenOnLandscape,

      autoExitFullscreenOnPortrait: autoExitFullscreenOnPortrait ?? this.autoExitFullscreenOnPortrait,

      lockOrientationInFullscreen: lockOrientationInFullscreen ?? this.lockOrientationInFullscreen,

      hideSystemUiInFullscreen: hideSystemUiInFullscreen ?? this.hideSystemUiInFullscreen,

      restoreSystemUiAfterExit: restoreSystemUiAfterExit ?? this.restoreSystemUiAfterExit,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PresentationPolicy &&
        other.enabled == enabled &&
        other.allowFullscreen == allowFullscreen &&
        other.allowWindowFullscreen == allowWindowFullscreen &&
        other.allowPictureInPicture == allowPictureInPicture &&
        other.allowFloatingWindow == allowFloatingWindow &&
        other.autoFullscreenOnLandscape == autoFullscreenOnLandscape &&
        other.autoExitFullscreenOnPortrait == autoExitFullscreenOnPortrait &&
        other.lockOrientationInFullscreen == lockOrientationInFullscreen &&
        other.hideSystemUiInFullscreen == hideSystemUiInFullscreen &&
        other.restoreSystemUiAfterExit == restoreSystemUiAfterExit;
  }

  @override
  int get hashCode {
    return Object.hash(
      enabled,
      allowFullscreen,
      allowWindowFullscreen,
      allowPictureInPicture,
      allowFloatingWindow,
      autoFullscreenOnLandscape,
      autoExitFullscreenOnPortrait,
      lockOrientationInFullscreen,
      hideSystemUiInFullscreen,
      restoreSystemUiAfterExit,
    );
  }

  @override
  String toString() {
    return 'PresentationPolicy('
        'enabled=$enabled, '
        'fullscreen=$allowFullscreen, '
        'pip=$allowPictureInPicture, '
        'floating=$allowFloatingWindow'
        ')';
  }
}
