## Unreleased

- `MediaSessionConfig.androidStopOnRemoveTask` now does what it says. The field was read by nothing, so every host that set it to stop playback when the app is swiped out of Android's recents kept playing anyway. `MediaSessionHandler` gained `stopOnTaskRemoved` and an `onTaskRemoved()` override that stops when asked, and the driver forwards the config's value — the default (`false`, keep playing from the notification) is unchanged, which is what a music app wants; a live room is the case that needs it on.
- The media notification publishes position at most once a second, while anything the viewer acts on (play/pause, speed, duration, the control list) still goes out immediately. Every transport tick used to be a platform notification rebuild, and the player can report many times a second - a lock screen redraws its bar about once a second whatever the app pushes, so the rest was battery and heat for nothing. A seek or a new song is a different timeline, not a step along this one, so a backwards jump publishes at once.
- Test seam: `MediaSessionDriver(handler:)` accepts a handler instead of letting `initialize()` build one through `AudioService.init`, which needs a platform.

## 0.1.0

Initial release.

- Puts **any** player from the kernel on the system media surfaces: Android notification, iOS lock screen and control center, Windows SMTC and Linux MPRIS.
- One line to start: `MediaSessionBootstrap.enable()`, after which every player shows up on the notification automatically.
- Video and audio share the same thing — one notification, one lock screen entry, one set of media keys; only the dressing differs (previous / next become ±10 seconds, the channel name changes), declared through `MediaSessionConfig`.
- Audio focus, interruption handling and pause-on-unplug.
- A handler (`MediaSessionHandler`) and driver (`MediaSessionDriver`) built on `audio_service`.
- Dependency direction: `media_core_audio` depends on this package, so the music module no longer bundles the system media surfaces.
