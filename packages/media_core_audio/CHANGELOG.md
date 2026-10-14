## Unreleased

- Turning the binding off now takes the media surface with it. `detach()` used to clear the queue transports and stop mirroring while leaving `MediaSessionDriver.active` pointing at the player and the last published state saying `ready + playing` — which on Android is precisely what keeps the media foreground service alive. That is why "关闭后台播放" looked like a switch wired to nothing. `detach` now releases the surface it published (`setActive(null)`, which parks the session and clears the item), and only when the surface is still the one it took: a video player that the kernel activated in the meantime is left alone.
- Re-attaching restores the queue transports. `detach` is not teardown for the binding object, and the second attach used to leave the notification without next/previous.
- Background policy is the kernel's, not the binding's: `PlayerKernel` observes the app and pauses what is playing, and a music host passes `AudioPlaybackController(playerConfig: PlayerConfig(pauseWhenBackgrounded: false))` for the narration-keeps-playing case. One mechanism, one owner.
- `ffmpeg_kit_extended_flutter` is required as `^0.6.2` instead of the exact `0.6.2`. A single-version requirement is an exact pin, so an app that reached FFmpeg through any other package could not satisfy both constraints at once; `^0.6.2` still resolves to 0.6.2 today, since it is the newest release.

## 0.1.0

Initial release.

- Sources: the `MusicSource` contract and registry, with a local source built in.
- Queue and play modes: `PlayQueue`, `PlayMode` (sequential / single / shuffle and friends) and the `PlayModeX` extension.
- Lyrics: LRC parsing, `LyricDocument` and the timeline (`LyricTimeline`), with a pluggable `LyricProvider`.
- Desktop lyric window: native windows for Windows and Android, including alignment, actions and the transport layer (`DesktopLyricController`).
- Background playback: `MusicBackgroundBinding` ties the app lifecycle and the audio session together.
- System media surfaces: notification / lock screen / SMTC / MPRIS through `media_core_mediasession` (`MediaCoreAudioHandler`).
- Downloads: an FFmpeg-backed source download queue (`MusicDownloadFormat` / `MusicDownloadStatus`).
- Permissions: `AudioPermissionService` and `AudioCapabilityConfig` declare what the module needs.
