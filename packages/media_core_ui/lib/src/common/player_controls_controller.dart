import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_core/media_core.dart';

import 'package:media_core_ui/src/common/player_control_actions.dart';
import 'package:media_core_ui/src/common/player_controls_style.dart';
import 'package:media_core_ui/src/common/player_controls_theme.dart';

/// What every control set shares: playback state, actions and visibility.
///
/// One controller drives one player. The bars (iOS, Android, desktop) are
/// stateless views over it, so a host that switches style keeps the position,
/// the volume and the visibility policy, and a host that writes its own bar
/// gets the same behaviour for free.
///
/// Responsibilities:
///
/// - mirror the player's playback state for widgets
/// - expose the actions a bar offers (play, seek, volume, rate, loop,
///   screenshot) and forward them to the handle
/// - own the controls' visibility: idle auto-hide, reveal on interaction,
///   stay visible while paused
///
/// It does not:
///
/// - build widgets
/// - render video ([MediaPlayerView] does)
/// - own the player (the kernel does; a controller borrows a handle)
///
/// ### Two notification paths
///
/// Playback state arrives with every progress tick. Rebuilding a control bar
/// several times a second is fine for the progress bar and wasteful for the
/// rest, so there are two paths:
///
/// - [ChangeNotifier] (this object) fires on *structural* changes: play/pause,
///   volume, rate, loop, source, visibility, capabilities.
/// - [playbackListenable] fires on every tick, for the widgets that show a
///   moving position.
final class PlayerControlsController extends ChangeNotifier {
  /// Creates a controller for [handle].
  PlayerControlsController({
    required this.handle,
    this.actions = PlayerControlActions.none,
    PlayerControlsTheme? theme,
    PlayerControlsStyle? style,
    Duration? hideDelay,
    this.keepVisibleWhenPaused = true,
    bool autoHide = true,
    bool controlsVisible = true,
  }) : _style = style,
       _theme = theme,
       _hideDelay = hideDelay,
       _autoHide = autoHide,
       _controlsVisible = controlsVisible {
    _playback = ValueNotifier<PlayerTransportState>(handle.playback);
    _playbackSubscription = handle.stateChanges.listen(_onPlayback, onError: (Object _) {});
    _sourceSubscription = handle.sourceChanges.listen((_) => _onSourceChanged(), onError: (Object _) {});

    _scheduleHide();
  }

  /// The player this controller drives.
  final PlayerHandle handle;

  /// Host callbacks (fullscreen, PiP, floating, screenshot handling).
  PlayerControlActions actions;

  /// Whether the controls hide themselves after `hideDelay`.
  ///
  /// A host that renders its own chrome — a fullscreen desktop layout, a
  /// kiosk — turns this off and drives [setControlsVisible] instead.
  bool _autoHide;

  /// Whether the controls stay on screen while playback is paused.
  ///
  /// Paused is a state the viewer put the player in and expects to see; hiding
  /// the controls then would leave them guessing.
  bool keepVisibleWhenPaused;

  late final ValueNotifier<PlayerTransportState> _playback;
  StreamSubscription<PlayerTransportState>? _playbackSubscription;
  StreamSubscription<PlayerSource?>? _sourceSubscription;
  Timer? _hideTimer;

  PlayerControlsStyle? _style;
  PlayerControlsTheme? _theme;
  Duration? _hideDelay;

  bool _controlsVisible;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// Every playback tick, for position-driven widgets.
  ///
  /// The progress bar and the time labels listen here; the rest of a bar
  /// listens to the controller itself.
  ValueListenable<PlayerTransportState> get playbackListenable => _playback;

  /// Current playback state.
  PlayerTransportState get playback => handle.playback;

  /// Whether the player is playing.
  bool get isPlaying => handle.playback.isPlaying;

  /// Whether the player is loading or buffering.
  bool get isBuffering => handle.playback.isBuffering;

  /// Whether a source is open.
  bool get hasSource => handle.source != null;

  /// Whether the stream can be seeked.
  ///
  /// Live streams report no duration and adapters may not support seeking at
  /// all; a bar hides the progress area instead of offering a dead control.
  bool get canSeek {
    if (!hasSource || isLive) {
      return false;
    }

    if (!handle.backendCapabilities.supportsSeek) {
      return false;
    }

    return handle.playback.hasDuration;
  }

  /// Whether the stream is live (no seekable timeline).
  ///
  /// Read from the provider-declared flag rather than inferred from a
  /// missing duration: a VOD that is still loading has no duration yet
  /// and would flash a LIVE badge, while a live engine that reports
  /// elapsed time as its duration would offer a seek bar it cannot
  /// honor.
  bool get isLive => handle.source?.isLive ?? false;

  /// Current position.
  Duration get position => handle.playback.position;

  /// Total duration.
  Duration get duration => handle.playback.duration;

  /// Current volume in the 0.0–1.0 range.
  double get volume => handle.playback.volume;

  /// Whether output is muted.
  bool get isMuted => handle.muted;

  /// Whether playback restarts after completion.
  bool get isLooping => handle.loop;

  /// Current playback rate.
  double get rate => handle.playback.rate;

  /// Title to show, when the source carries one.
  String? get title {
    final source = handle.source;

    if (source == null) {
      return null;
    }

    if (source.hasTitle) {
      return source.title;
    }

    final segments = source.uri.pathSegments;

    return segments.isEmpty ? null : segments.last;
  }

  /// Whether the player can capture a frame right now.
  ///
  /// Read from the handle rather than guessed: it is false when no engine can
  /// capture and no widget renders the player.
  bool get canCaptureScreenshot => handle.canCaptureScreenshot;

  /// Whether the controls are currently shown.
  bool get controlsVisible => _controlsVisible;

  /// Whether the controls hide themselves.
  bool get autoHides => _autoHide;

  /// Style this controller was created for.
  PlayerControlsStyle? get style => _style;

  /// Theme in use: the host's, or the style's convention.
  PlayerControlsTheme get theme {
    return _theme ?? PlayerControlsTheme.of(_style ?? PlayerControlsStyle.resolve());
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _disposed;

  /// Updates the choices the host made about how the player is presented.
  ///
  /// Called by the composed view when the widget's style, theme or policy
  /// change, and by a host that drives a custom bar. A controller created
  /// before the widget settled would otherwise keep rendering the platform's
  /// default style while the bars on screen use another.
  void configure({
    PlayerControlsStyle? style,
    PlayerControlsTheme? theme,
    Duration? hideDelay,
    bool? autoHide,
    bool? keepVisibleWhenPaused,
    PlayerControlActions? actions,
  }) {
    if (_disposed) {
      return;
    }

    var changed = false;

    if (style != null && !identical(style, _style)) {
      _style = style;
      changed = true;
    }

    if (theme != null && !identical(theme, _theme)) {
      _theme = theme;
      changed = true;
    }

    if (hideDelay != null && hideDelay != _hideDelay) {
      _hideDelay = hideDelay;
      changed = true;
    }

    if (autoHide != null && autoHide != _autoHide) {
      _autoHide = autoHide;
      changed = true;
    }

    if (keepVisibleWhenPaused != null && keepVisibleWhenPaused != this.keepVisibleWhenPaused) {
      this.keepVisibleWhenPaused = keepVisibleWhenPaused;
      changed = true;
    }

    if (actions != null && !identical(actions, this.actions)) {
      this.actions = actions;
      changed = true;
    }

    if (changed) {
      _scheduleHide();

      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Visibility
  // ---------------------------------------------------------------------------

  /// Shows the controls and restarts the idle countdown.
  void revealControls({bool restartTimer = true}) {
    if (!_controlsVisible) {
      _controlsVisible = true;

      notifyListeners();
    } else if (!restartTimer) {
      return;
    }

    _scheduleHide();
  }

  /// Hides the controls, unless playback is paused and the host keeps them.
  void hideControls({bool force = false}) {
    if (!force && keepVisibleWhenPaused && !isPlaying) {
      return;
    }

    // Cancel and clear: [_scheduleHide] treats a non-null timer as a countdown
    // already running, so leaving a cancelled one behind would stop the chrome
    // from ever arming an auto-hide again after this call.
    _hideTimer?.cancel();
    _hideTimer = null;

    if (!_controlsVisible) {
      return;
    }

    _controlsVisible = false;

    notifyListeners();
  }

  /// Shows the controls when hidden and hides them when shown.
  ///
  /// This is what a tap on the video does.
  void toggleControls() {
    if (_controlsVisible) {
      // A tap while the controls are up means "I am done"; it hides them even
      // while paused, or a paused video could never be cleared of its bars.
      hideControls(force: true);
    } else {
      revealControls();
    }
  }

  /// Forces the controls to a state, ignoring the idle policy.
  ///
  /// For hosts that own the chrome (fullscreen layouts, kiosk screens).
  void setControlsVisible({required bool visible}) {
    if (visible) {
      revealControls();

      return;
    }

    hideControls(force: true);
  }

  /// Whether activity was seen while the current countdown was running.
  ///
  /// Hover fires on every pointer move - a hundred or more times a second on a
  /// desktop - and each one used to cancel the countdown and build a new
  /// `Timer`. The contract a viewer expects is only "the chrome stays up while
  /// I am doing something, and falls after a quiet stretch", so the running
  /// countdown now notes the activity and re-arms once when it expires: same
  /// behaviour, one timer per window instead of one per event.
  bool _activityWhileCounting = false;

  void _scheduleHide() {
    if (!_autoHide || !_controlsVisible || !isPlaying) {
      _hideTimer?.cancel();
      _hideTimer = null;

      return;
    }

    if (_hideTimer != null) {
      _activityWhileCounting = true;

      return;
    }

    _activityWhileCounting = false;
    _hideTimer = Timer(_hideDelay ?? theme.hideDelay, _onHideDeadline);
  }

  void _onHideDeadline() {
    _hideTimer = null;

    if (_disposed || !_controlsVisible || !isPlaying) {
      return;
    }

    if (_activityWhileCounting) {
      // The pointer was still moving: give the viewer another full window
      // rather than hiding under their hand.
      _scheduleHide();

      return;
    }

    _controlsVisible = false;

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Plays when paused, pauses when playing.
  Future<void> togglePlayPause() {
    revealControls();

    return isPlaying ? pause() : play();
  }

  /// Starts or resumes playback.
  Future<void> play() {
    revealControls();

    return handle.play();
  }

  /// Pauses playback.
  Future<void> pause() {
    // Pausing reveals the controls: the viewer is about to act again.
    revealControls(restartTimer: false);

    return handle.pause();
  }

  /// Stops playback and returns to the start of the stream.
  Future<void> stop() {
    revealControls(restartTimer: false);

    return handle.stop();
  }

  /// Seeks to [position].
  Future<void> seekTo(Duration position) {
    revealControls();

    return handle.seek(_clampPosition(position));
  }

  /// Seeks by [offset] from the current position.
  Future<void> seekBy(Duration offset) {
    return seekTo(handle.playback.position + offset);
  }

  /// Sets the volume in the 0.0–1.0 range.
  ///
  /// Changing the volume while muted unmutes, which is what a viewer dragging
  /// the slider up expects.
  Future<void> setVolume(double value) {
    revealControls();

    final clamped = value.clamp(0.0, 1.0);

    if (isMuted && clamped > 0) {
      return handle.setMute(muted: false).then((_) => handle.setVolume(clamped));
    }

    return handle.setVolume(clamped);
  }

  /// Mutes when unmuted, restores the previous volume when muted.
  Future<void> toggleMute() {
    revealControls();

    return handle.setMute(muted: !isMuted);
  }

  /// Turns looping on or off.
  Future<void> toggleLoop() {
    revealControls();

    return handle.setLoop(loop: !isLooping);
  }

  /// Moves to the next rate in [rates], wrapping around.
  Future<void> cycleRate([List<double> rates = defaultRates]) {
    revealControls();

    final current = rate;
    var index = rates.indexWhere((value) => (value - current).abs() < 0.001);

    if (index < 0) {
      index = rates.indexWhere((value) => value > current);
    }

    final next = index < 0 ? rates.first : rates[(index + 1) % rates.length];

    return setRate(next);
  }

  /// Sets an explicit playback rate.
  Future<void> setRate(double value) {
    revealControls();

    return handle.setRate(value);
  }

  /// Restricts playback to the audio track.
  Future<void> setAudioOnly({required bool value}) {
    revealControls();

    return handle.setAudioOnly(audioOnly: value);
  }

  /// Whether playback is restricted to the audio track.
  bool get isAudioOnly => handle.audioOnly;

  /// Captures the current frame and hands it to the host.
  ///
  /// The frame is returned as well, so a caller that shows its own UI can use
  /// it without going through [PlayerControlActions.onScreenshot].
  Future<PlayerScreenshot?> captureScreenshot({ScreenshotOptions options = ScreenshotOptions.defaults}) async {
    revealControls();

    final screenshot = await handle.captureScreenshot(options: options);

    if (screenshot == null) {
      return null;
    }

    await actions.onScreenshot?.call(screenshot);

    return screenshot;
  }

  /// Enters fullscreen, when the host supports it.
  Future<void> enterFullscreen() async {
    revealControls();

    await actions.enterFullscreen?.call();
  }

  /// Leaves fullscreen, when the host supports it.
  Future<void> exitFullscreen() async {
    revealControls();

    await actions.exitFullscreen?.call();
  }

  /// Enters picture-in-picture, when the host supports it.
  Future<void> enterPip() async {
    revealControls();

    await actions.enterPip?.call();
  }

  /// Enters the floating window, when the host supports it.
  Future<void> enterFloating() async {
    revealControls();

    await actions.enterFloating?.call();
  }

  /// Playback rates a rate button cycles through.
  static const List<double> defaultRates = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Duration _clampPosition(Duration position) {
    if (position < Duration.zero) {
      return Duration.zero;
    }

    final duration = handle.playback.duration;

    if (duration > Duration.zero && position > duration) {
      return duration;
    }

    return position;
  }

  void _onPlayback(PlayerTransportState state) {
    if (_disposed) {
      return;
    }

    final wasPlaying = _playback.value.isPlaying;
    final wasVolume = _playback.value.volume;

    _playback.value = state;

    final structural = wasPlaying != state.isPlaying || wasVolume != state.volume;

    if (structural) {
      _scheduleHide();

      notifyListeners();

      return;
    }

    // Position-only ticks do not touch the countdown. The countdown measures how
    // long the viewer has been idle, and the engine reports position many times
    // a second while anything plays: refreshing on ticks meant the desktop
    // chrome could never fade during playback - each tick cancelled the timer
    // and started a new one, so it expired only when the stream stalled.
    // Ticks also must not rebuild the bars; that is what playbackListenable is
    // for.
  }

  void _onSourceChanged() {
    if (_disposed) {
      return;
    }

    _playback.value = handle.playback;

    // A new video deserves its chrome: the viewer has just made a choice and
    // will want the controls for a moment.
    revealControls();

    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _hideTimer?.cancel();
    _hideTimer = null;

    unawaited(_playbackSubscription?.cancel());
    _playbackSubscription = null;
    unawaited(_sourceSubscription?.cancel());
    _sourceSubscription = null;

    _playback.dispose();

    super.dispose();
  }

  @override
  String toString() {
    return 'PlayerControlsController('
        'player: ${handle.id.value}, '
        'playing: $isPlaying, '
        'visible: $_controlsVisible, '
        'style: ${_style?.name ?? 'auto'}'
        ')';
  }
}
