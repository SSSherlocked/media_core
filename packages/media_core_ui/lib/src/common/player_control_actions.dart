import 'package:media_core/media_core.dart';

/// What a control bar can trigger but cannot perform itself.
///
/// Playback, seeking, volume, rate, looping and screenshots belong to
/// [PlayerHandle] and the controller calls them directly. Everything that
/// leaves the widget — fullscreen, picture-in-picture, the floating window,
/// opening a settings page — depends on how the *host* is built: a kernel with
/// a presentation driver, a navigator route, a window plugin. Those arrive
/// here as callbacks.
///
/// A callback that is null is not shown: a bar never offers a button that
/// cannot work, which is why "does this host support PiP" is answered by
/// presence rather than by a capability flag that could disagree with reality.
///
/// Responsibilities:
///
/// - carry host callbacks
/// - report which of them are available
///
/// It does not:
///
/// - perform playback (the handle does)
/// - know about kernels, routes or windows
/// - hold state
final class PlayerControlActions {
  /// Creates the callbacks.
  const PlayerControlActions({
    this.enterFullscreen,
    this.exitFullscreen,
    this.enterPip,
    this.enterFloating,
    this.onScreenshot,
  });

  /// A host with no extra capabilities: playback only.
  static const PlayerControlActions none = PlayerControlActions();

  /// Enters fullscreen, when this host can.
  final Future<void> Function()? enterFullscreen;

  /// Leaves fullscreen, when this host can.
  final Future<void> Function()? exitFullscreen;

  /// Enters picture-in-picture, when this host can.
  final Future<void> Function()? enterPip;

  /// Enters the floating window, when this host can.
  final Future<void> Function()? enterFloating;

  /// Called with every captured frame.
  ///
  /// The frame has already been captured by the time this runs — saving it,
  /// sharing it or showing a thumbnail is the host's decision, which is why it
  /// is a callback and not a directory setting.
  final Future<void> Function(PlayerScreenshot screenshot)? onScreenshot;

  /// Whether a fullscreen button can be offered.
  bool get canEnterFullscreen => enterFullscreen != null;

  /// Whether a "leave fullscreen" button can be offered.
  bool get canExitFullscreen => exitFullscreen != null;

  /// Whether a picture-in-picture button can be offered.
  bool get canEnterPip => enterPip != null;

  /// Whether a floating-window button can be offered.
  bool get canEnterFloating => enterFloating != null;

  /// Whether a screenshot button can be offered by the host's side.
  bool get canHandleScreenshot => onScreenshot != null;

  /// Whether any presentation action is available.
  bool get hasPresentation => canEnterFullscreen || canEnterPip || canEnterFloating;

  /// Creates modified callbacks.
  PlayerControlActions copyWith({
    Future<void> Function()? enterFullscreen,
    Future<void> Function()? exitFullscreen,
    Future<void> Function()? enterPip,
    Future<void> Function()? enterFloating,
    Future<void> Function(PlayerScreenshot screenshot)? onScreenshot,
  }) {
    return PlayerControlActions(
      enterFullscreen: enterFullscreen ?? this.enterFullscreen,
      exitFullscreen: exitFullscreen ?? this.exitFullscreen,
      enterPip: enterPip ?? this.enterPip,
      enterFloating: enterFloating ?? this.enterFloating,
      onScreenshot: onScreenshot ?? this.onScreenshot,
    );
  }

  @override
  String toString() {
    return 'PlayerControlActions('
        'fullscreen: $canEnterFullscreen, '
        'exitFullscreen: $canExitFullscreen, '
        'pip: $canEnterPip, '
        'floating: $canEnterFloating, '
        'screenshot: $canHandleScreenshot'
        ')';
  }
}

/// [PlayerControlActions] over a [PlayerKernel].
///
/// The kernel is where fullscreen, PiP and the floating window live: a driver
/// is attached to it (`attachPresentation`) and the actions are addressed by
/// player id. Wrapping that here means a host that already owns a kernel wires
/// its control bars with one line:
///
/// ```dart
/// final view = MediaCorePlayerView(
///   handle: handle,
///   actions: KernelPlayerControlActions(kernel: kernel, playerId: handle.id),
/// );
/// ```
///
/// Availability is read from the kernel *and* from the driver: a kernel with
/// no presentation driver attached reports "no" instead of throwing when a
/// button is pressed.
final class KernelPlayerControlActions extends PlayerControlActions {
  /// Creates actions for [playerId] on [kernel].
  KernelPlayerControlActions({required this.kernel, required this.playerId, super.onScreenshot})
    : super(
        enterFullscreen: () => kernel.enterFullscreen(playerId),
        exitFullscreen: () => kernel.exitFullscreen(playerId),
        enterPip: () => kernel.enterPip(playerId),
        enterFloating: () => kernel.enterFloating(playerId),
      );

  /// Kernel holding the presentation driver.
  final PlayerKernel kernel;

  /// PlayerIdentity the actions address.
  final PlayerId playerId;

  /// Whether a presentation driver is attached to the kernel.
  ///
  /// Without one, every presentation call throws; the bars must not offer
  /// buttons that would.
  bool get hasDriver => kernel.presentationDriver != null;

  @override
  bool get canEnterFullscreen => hasDriver && super.canEnterFullscreen;

  @override
  bool get canExitFullscreen => hasDriver && super.canExitFullscreen;

  @override
  bool get canEnterPip => hasDriver && super.canEnterPip;

  @override
  bool get canEnterFloating => hasDriver && super.canEnterFloating;
}
