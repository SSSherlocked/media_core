## Unreleased

- `MediaSessionDriver.setForegroundHold`: keeps the surfaces "playing" (and so the Android foreground service) while the host reconnects, waits or is interrupted, also across a player released between two opens.
- `MediaSessionDriver.onRemotePause`: told when the notification, lock screen or a media key pauses or stops; such a pause also cancels a resume planned for the end of an interruption.

## 0.1.0

Initial release.

- Puts **any** player from the kernel on the system media surfaces: Android notification, iOS lock screen and control center, Windows SMTC and Linux MPRIS.
- One line to start: `MediaSessionBootstrap.enable()`, after which every player shows up on the notification automatically.
- Video and audio share the same thing — one notification, one lock screen entry, one set of media keys; only the dressing differs (previous / next become ±10 seconds, the channel name changes), declared through `MediaSessionConfig`.
- Audio focus, interruption handling and pause-on-unplug.
- A handler (`MediaSessionHandler`) and driver (`MediaSessionDriver`) built on `audio_service`.
- Dependency direction: `media_core_audio` depends on this package, so the music module no longer bundles the system media surfaces.
