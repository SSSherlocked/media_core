import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/presentation/presentation_mode.dart';

part 'presentation_capabilities.freezed.dart';

/// Describes supported presentation capabilities.
///
/// Capability describes what the current platform supports.
///
/// It does not represent current presentation state.
///
/// Responsibilities:
///
/// - fullscreen support
/// - PiP support
/// - floating support
///
/// Does not:
///
/// - perform transitions
/// - call platform APIs
/// - manage lifecycle
@freezed
abstract class PresentationCapabilities with _$PresentationCapabilities {
  /// Creates a capability set from its individual support flags.
  const factory PresentationCapabilities({
    /// Fullscreen support.
    @Default(true) bool fullscreen,

    /// Window-level fullscreen support.
    ///
    /// Separate from [fullscreen] because they are separate abilities: filling
    /// the application window needs nothing from the platform, while covering
    /// the screen does. A phone reports window fullscreen but not system
    /// fullscreen; a desktop window reports both.
    @Default(true) bool windowFullscreen,

    /// Picture-in-picture support.
    @Default(false) bool pip,

    /// Floating window support.
    @Default(false) bool floating,
  }) = _PresentationCapabilities;

  const PresentationCapabilities._();

  /// Default capability.
  factory PresentationCapabilities.initial() {
    return const PresentationCapabilities();
  }

  /// Whether any presentation mode is supported.
  bool get any => fullscreen || windowFullscreen || pip || floating;

  /// Whether no presentation mode is supported.
  bool get none => !any;

  /// Whether fullscreen is supported.
  bool get canFullscreen => fullscreen;

  /// Whether the platform can fill the window without going fullscreen.
  bool get canWindowFullscreen => windowFullscreen;

  /// Whether PiP is supported.
  bool get canPip => pip;

  /// Whether floating is supported.
  bool get canFloating => floating;

  /// Checks whether mode is supported.
  bool supports(PresentationMode mode) {
    switch (mode) {
      case PresentationMode.normal:
        return true;

      case PresentationMode.fullscreen:
        return fullscreen;

      case PresentationMode.windowFullscreen:
        return windowFullscreen;

      case PresentationMode.pip:
        return pip;

      case PresentationMode.floating:
        return floating;
    }
  }

  /// Supported modes.
  List<PresentationMode> get supportedModes {
    return [
      if (fullscreen) PresentationMode.fullscreen,
      if (windowFullscreen) PresentationMode.windowFullscreen,

      if (pip) PresentationMode.pip,

      if (floating) PresentationMode.floating,
    ];
  }
}
