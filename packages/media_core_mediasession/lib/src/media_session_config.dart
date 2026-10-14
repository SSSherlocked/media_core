/// Configuration for the system media surfaces.
///
/// Notification icon names are Android resource strings in `type/name` form
/// (`drawable/ic_media_play`): audio_service's `getResourceId` splits on `/`
/// and indexes `[1]`, so a bare name crashes `setState` on every publish.
/// Ship matching drawables or pass resource strings of your own icons —
/// a notification whose icons are missing shows no controls at all, which looks
/// like a broken player rather than a missing asset.
final class MediaSessionConfig {
  /// Creates the configuration.
  const MediaSessionConfig({
    this.androidNotificationChannelId = 'media_core.playback',
    this.androidNotificationChannelName = 'Media playback',
    this.androidNotificationOngoing = false,
    this.androidStopOnRemoveTask = false,
    this.androidResumeOnClick = true,
    this.showControls = true,
    this.processInterruptions = true,
    this.pauseOnBecomingNoisy = true,
    this.duckFactor = 0.3,
    this.resumeAfterInterruption = true,
    this.playIcon = 'drawable/ic_media_play',
    this.pauseIcon = 'drawable/ic_media_pause',
    this.stopIcon = 'drawable/ic_media_stop',
    this.previousIcon = 'drawable/ic_media_previous',
    this.nextIcon = 'drawable/ic_media_next',
    this.rewindIcon = 'drawable/ic_media_rewind',
    this.fastForwardIcon = 'drawable/ic_media_forward',
    this.seekStep = const Duration(seconds: 10),
    this.showSeekButtons = true,
    this.androidCompactActionIndices = const <int>[0, 1],
  });

  /// Configuration for a player that has no queue: seek buttons instead of
  /// skip buttons, which is what a video notification wants.
  const MediaSessionConfig.video({
    this.androidNotificationChannelId = 'media_core.video',
    this.androidNotificationChannelName = 'Video playback',
    this.androidNotificationOngoing = false,
    this.androidStopOnRemoveTask = false,
    this.androidResumeOnClick = true,
    this.showControls = true,
    this.processInterruptions = true,
    this.pauseOnBecomingNoisy = true,
    this.duckFactor = 0.3,
    this.resumeAfterInterruption = true,
    this.playIcon = 'drawable/ic_media_play',
    this.pauseIcon = 'drawable/ic_media_pause',
    this.stopIcon = 'drawable/ic_media_stop',
    this.previousIcon = 'drawable/ic_media_previous',
    this.nextIcon = 'drawable/ic_media_next',
    this.rewindIcon = 'drawable/ic_media_rewind',
    this.fastForwardIcon = 'drawable/ic_media_forward',
    this.seekStep = const Duration(seconds: 10),
    this.showSeekButtons = true,
    this.androidCompactActionIndices = const <int>[0, 1, 2],
  });

  /// Notification channel id used on Android.
  final String androidNotificationChannelId;

  /// Notification channel name used on Android.
  final String androidNotificationChannelName;

  /// Whether the Android notification is ongoing while playing.
  final bool androidNotificationOngoing;

  /// Whether playback stops when the task is removed on Android (the app is
  /// swiped away from recents while its process lives on). Stopping also ends
  /// the media service and, with [androidResumeOnClick] off, its notification.
  final bool androidStopOnRemoveTask;

  /// audio_service's `androidResumeOnClick`. On (its default), the
  /// notification survives the media service (detached when the service ends)
  /// and media buttons may restart the app. Off, the notification goes with
  /// the service and media buttons do not reach an app that is not running,
  /// which is what a host that ends playback on exit wants.
  final bool androidResumeOnClick;

  /// Whether transport controls are shown in the notification.
  ///
  /// When true the icon names below must exist as drawables in the host app.
  final bool showControls;

  /// Whether audio focus interruptions (calls, other media apps) are handled
  /// automatically.
  final bool processInterruptions;

  /// Whether playback pauses when headphones are unplugged.
  final bool pauseOnBecomingNoisy;

  /// Volume multiplier applied during a duck interruption.
  final double duckFactor;

  /// Whether playback resumes after a transient interruption ends.
  final bool resumeAfterInterruption;

  /// Drawable name for the play control.
  final String playIcon;

  /// Drawable name for the pause control.
  final String pauseIcon;

  /// Drawable name for the stop control.
  final String stopIcon;

  /// Drawable name for the skip-previous control.
  ///
  /// Only used by a host that installs a queue transport (`skipToPreviousHandler`);
  /// the drawable must exist like the other icons.
  final String previousIcon;

  /// Drawable name for the skip-next control.
  final String nextIcon;

  /// Drawable name for the "back 10s" control.
  final String rewindIcon;

  /// Drawable name for the "forward 10s" control.
  final String fastForwardIcon;

  /// How far the seek buttons jump.
  ///
  /// The platform has no notion of a step size — the button says "rewind" and
  /// the player decides — so the value lives here. The icon names above are
  /// conventionally the ten-second pair; a host that changes the step should
  /// ship matching glyphs.
  final Duration seekStep;

  /// Whether the seek buttons are offered.
  ///
  /// On by default because the alternative for a single-media player (no queue)
  /// is a notification with only play/pause and stop, which cannot move the
  /// position at all. A music host that installs skip-to-next usually wants
  /// both, which is exactly what it gets.
  final bool showSeekButtons;

  /// Compact action indices for the Android notification.
  final List<int> androidCompactActionIndices;
}
