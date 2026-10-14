import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_core_pip/src/overlay_pip.dart';
import 'package:media_core_pip/src/system_pip.dart';
import 'package:pip_kit/pip_kit.dart';

/// Seam over pip_kit's controller singleton (the iOS side), injectable so the
/// sequencing around it can be tested without a device.
abstract interface class PipKitApi {
  /// Whether this device and OS version can present the system window.
  Future<bool> isSupported();

  /// Opens the window, arming [content] with [options].
  Future<bool> enter({required PipContent content, required PipOptions options});

  /// Whether the system window is on screen.
  ValueListenable<bool> get isOpen;

  /// Forgets armed content and turns auto-entry off.
  Future<void> disarm();
}

/// The production seam, over [PipController.instance].
final class PipKitControllerApi implements PipKitApi {
  /// Stateless: every call goes straight to the singleton, so the seam can be
  /// a const.
  const PipKitControllerApi();

  /// Whether pip_kit's platform channel reports the system window as usable.
  @override
  Future<bool> isSupported() => PipController.instance.isSupported();

  @override
  Future<bool> enter({required PipContent content, required PipOptions options}) {
    return PipController.instance.enter(content: content, options: options);
  }

  @override
  ValueListenable<bool> get isOpen {
    _wireStatus();
    return _isOpen;
  }

  @override
  Future<void> disarm() => PipController.instance.disarm();

  // PipController reports a PipStatus enum; mapped once here so the rest of
  // this package deals in plain bools.
  static final ValueNotifier<bool> _isOpen = ValueNotifier<bool>(false);
  static bool _wired = false;

  static void _wireStatus() {
    if (_wired) return;
    _wired = true;
    PipController.instance.status.addListener(_syncStatus);
  }

  static void _syncStatus() {
    _isOpen.value = PipController.instance.isOpen;
  }
}

/// [SystemPip] for the mobile paths that keep the picture in *this app's*
/// Flutter code:
///
/// - **Android** — `flutter_overlay_window` opens a draggable overlay above
///   every app; a second Flutter engine renders it. That engine reopens the
///   source from a URL, so entering is a handoff: the host supplies
///   [SystemPipMedia] through `PipDriver.pipMediaResolver`, pauses its own
///   engine, and resumes from [lastClosedPosition] when the window closes.
///   The overlay UI is whatever the host's `overlayMain` entrypoint builds —
///   see [overlayPipMain] for the package's helper.
/// - **iOS** — `pip_kit` drives the system Picture-in-Picture window around
///   the *live* player layer: no second player and no handoff, the app's own
///   engine keeps playing. The host mounts `PipHost` above the navigator and
///   renders the video through a platform view so AVKit can lift the layer.
///
/// Host setup the two platforms demand:
///
/// - Android: the `SYSTEM_ALERT_WINDOW` permission (requested on the first
///   [enable]); the plugin declares its overlay service through manifest
///   merge, and the host registers the `overlayMain` entrypoint.
/// - iOS: `PipHost` at the app root (`MaterialApp.builder`); the video must
///   play through a real on-screen player layer when the window is armed.
final class OverlayPipSystemPip implements SystemPip {
  /// Creates the implementation.
  ///
  /// [surfaceBuilder] is the widget drawn in the iOS system window; Android
  /// never runs it (the overlay engine draws from `overlayPipMain` instead).
  /// Both platform seams are injectable for tests.
  OverlayPipSystemPip({
    this.surfaceBuilder,
    OverlayWindowApi overlayWindow = const MethodChannelOverlayWindow(),
    PipKitApi pipKit = const PipKitControllerApi(),
    this.overlayTitle = 'media_core PiP',
    this.overlayEnableDrag = true,
    this.overlayShortSide = 180,
  })  : _overlayWindow = overlayWindow,
        _pipKit = pipKit;

  /// Widget drawn in the iOS system window.
  ///
  /// `PipContent.video` on iOS lifts the on-screen `AVPlayerLayer`, so the
  /// builder normally renders the same player view the app shows.
  final WidgetBuilder? surfaceBuilder;

  final OverlayWindowApi _overlayWindow;
  final PipKitApi _pipKit;

  /// Notification title of the Android overlay service.
  final String overlayTitle;

  /// Whether the Android overlay can be dragged around the screen.
  final bool overlayEnableDrag;

  /// Short side of the Android overlay window, in logical pixels; the long
  /// side follows the video's aspect.
  final double overlayShortSide;

  bool _disposed = false;
  bool _listening = false;
  OverlayPipLink? _link;
  final StreamController<SystemPipStatus> _statuses = StreamController<SystemPipStatus>.broadcast();

  /// Where the Android overlay said it was when the viewer closed it, for the
  /// handback. Always null on iOS (nothing was handed off) and before any
  /// close.
  Duration? get lastClosedPosition => _link?.lastClosedPosition;

  @override
  Future<bool> get isAvailable async {
    if (_disposed) {
      return false;
    }
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _overlayWindow.isPermissionGranted();
        case TargetPlatform.iOS:
          return await _pipKit.isSupported();
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
          return false;
      }
    } on Object catch (_) {
      return false;
    }
  }

  @override
  Future<SystemPipStatus> get status async {
    if (_disposed) {
      return SystemPipStatus.unavailable;
    }
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _overlayWindow.isActive() ? SystemPipStatus.enabled : SystemPipStatus.disabled;
        case TargetPlatform.iOS:
          return _pipKit.isOpen.value ? SystemPipStatus.enabled : SystemPipStatus.disabled;
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
          return SystemPipStatus.unavailable;
      }
    } on Object catch (_) {
      return SystemPipStatus.unavailable;
    }
  }

  @override
  Stream<SystemPipStatus> get statusStream {
    _ensureListening();
    return _statuses.stream;
  }

  @override
  Future<SystemPipStatus> enable({
    required int width,
    required int height,
    SystemPipSourceRect? sourceRect,
    SystemPipTrigger trigger = SystemPipTrigger.immediate,
    SystemPipMedia? media,
  }) {
    // Guards deliver through the returned future, the way an async body
    // would: a caller that awaits sees the same failure either way.
    if (_disposed) {
      return Future<SystemPipStatus>.error(StateError('OverlayPipSystemPip has been disposed.'));
    }
    if (width <= 0 || height <= 0) {
      return Future<SystemPipStatus>.error(
        ArgumentError('Picture-in-picture needs a positive video size, got ${width}x$height.'),
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _enableAndroid(width, height, media);
      case TargetPlatform.iOS:
        return _enableIOS(width, height, trigger);
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return Future<SystemPipStatus>.value(SystemPipStatus.unavailable);
    }
  }

  Future<SystemPipStatus> _enableAndroid(int width, int height, SystemPipMedia? media) async {
    // The overlay engine is a second Flutter isolate with empty registries:
    // it can only reopen the source from a URL, never reuse this engine's
    // player. Nothing to hand over means nothing to show.
    if (media == null) {
      throw UnsupportedError(
        'The Android overlay replays the source in a second engine: enable() '
        'needs a SystemPipMedia (url, position) from PipDriver.pipMediaResolver.',
      );
    }

    var granted = false;
    try {
      granted = await _overlayWindow.isPermissionGranted();
      if (!granted) {
        // The first request opens the system settings page and completes when
        // the viewer returns; a refusal is reported, never retried in a loop.
        granted = await _overlayWindow.requestPermission() ?? false;
      }
    } on Object catch (_) {
      granted = false;
    }
    if (!granted) {
      return SystemPipStatus.unavailable;
    }

    // [width] and [height] describe the media; the overlay window is the
    // same shape at a viewer-friendly scale.
    final size = _overlaySize(width, height);
    await _overlayWindow.showOverlay(
      width: size.width,
      height: size.height,
      enableDrag: overlayEnableDrag,
      title: overlayTitle,
    );
    _link = OverlayPipLink(_overlayWindow)..onEvent = _onOverlayEvent;
    await _link!.open(OverlayPipMessages.media(url: media.url, position: media.position, title: overlayTitle));

    _statuses.add(SystemPipStatus.enabled);
    return SystemPipStatus.enabled;
  }

  Future<SystemPipStatus> _enableIOS(int width, int height, SystemPipTrigger trigger) async {
    if (!await _pipKit.isSupported()) {
      return SystemPipStatus.unavailable;
    }
    _ensureListening();
    // The picture stays in this app's player layer, so no media handoff is
    // needed here — the iOS path ignores [media] entirely.
    final accepted = await _pipKit.enter(
      content: PipContent.video(surfaceBuilder ?? _defaultSurface),
      options: PipOptions(
        aspectRatio: _aspectRatioOf(width, height),
        // Arming auto-entry before the navigation is what makes "swipe home
        // keeps the video floating" work.
        autoEnter: trigger == SystemPipTrigger.onLeaveApp,
      ),
    );
    if (!accepted) {
      return SystemPipStatus.unavailable;
    }
    _statuses.add(SystemPipStatus.enabled);
    return SystemPipStatus.enabled;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_listening && defaultTargetPlatform == TargetPlatform.iOS) {
      _pipKit.isOpen.removeListener(_onKitStatus);
    }
    _listening = false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        if (await _overlayWindow.isActive()) {
          await _overlayWindow.closeOverlay();
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _pipKit.disarm();
      }
    } on Object catch (_) {
      // Teardown is best effort: the engine may already be gone with the app.
    }
    await _link?.dispose();
    _link = null;
    await _statuses.close();
  }

  void _ensureListening() {
    if (_disposed || _listening) {
      return;
    }
    _listening = true;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // The system can close the window on its own (the viewer taps it to
      // return); that edge must reach the driver through the stream.
      _pipKit.isOpen.addListener(_onKitStatus);
    }
  }

  void _onKitStatus() {
    if (_disposed) {
      return;
    }
    _statuses.add(_pipKit.isOpen.value ? SystemPipStatus.enabled : SystemPipStatus.disabled);
  }

  void _onOverlayEvent(OverlayPipMessages event) {
    if (_disposed) {
      return;
    }
    if (event.type == 'close') {
      // The overlay engine told the app before tearing its window down; the
      // driver treats this edge as the handback point.
      _statuses.add(SystemPipStatus.disabled);
    }
  }

  /// The video's aspect as a whole-number ratio, reduced to lowest terms:
  /// 1920x1080 travels as the system's familiar 16:9, not a pair it has to
  /// round itself.
  PipAspectRatio _aspectRatioOf(int width, int height) {
    var a = width;
    var b = height;
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    if (a <= 0) {
      return PipAspectRatio.landscape;
    }
    return PipAspectRatio(width ~/ a, height ~/ a);
  }

  /// The overlay window's size in physical pixels: the video's aspect at
  /// [overlayShortSide], clamped to the screen. `flutter_overlay_window`
  /// feeds its numbers straight into `WindowManager.LayoutParams`, which are
  /// physical pixels.
  ({int width, int height}) _overlaySize(int videoWidth, int videoHeight) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final view = views.isEmpty ? null : views.first;
    final dpr = view?.devicePixelRatio ?? 1.0;
    final screen = view == null ? const Size(1080, 1920) : view.physicalSize / view.devicePixelRatio;

    final aspect = videoHeight > 0 ? videoWidth / videoHeight : 16 / 9;
    final shortSide = overlayShortSide.clamp(80.0, screen.shortestSide * 0.6);
    double width;
    double height;
    if (aspect >= 1) {
      width = shortSide * aspect;
      height = shortSide;
    } else {
      width = shortSide;
      height = shortSide / aspect;
    }
    width = width.clamp(80.0, screen.width * 0.9);
    height = height.clamp(80.0, screen.height * 0.9);
    return (width: (width * dpr).round(), height: (height * dpr).round());
  }
}

/// The iOS window shows the picture the system lifts from the player layer;
/// the builder itself is never painted there, so an empty box is honest.
Widget _defaultSurface(BuildContext context) => const ColoredBox(color: Color(0xFF000000));
