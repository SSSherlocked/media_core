## Unreleased

- **Conformed to media_core's new signatures**: the control layer calls `setMute(muted:)`, `setLoop(loop:)` and `setAudioOnly(audioOnly:)` through the named forms, and the widgets/controllers it exposes gained the doc comments the workspace's lint configuration asks for.

- Engine position ticks no longer keep the controls on screen. The idle countdown is a measure of how long the *viewer* has been still, but every transport report refreshed it - and the player reports position many times a second - so on desktop the chrome could never fade during playback: each tick cancelled the timer and started a new one, and it expired only if the stream stalled. Hover and tap still extend it, and one pointer move now marks the running countdown instead of cancelling and re-arming it a hundred times a second.
- A cancelled countdown is cleared, not just cancelled: a cancelled-but-set timer read as "already counting", so after a manual hide (a tap on the video) the next reveal armed nothing and the controls sat on screen for the rest of the session.
- Dragging the volume or rate slider while the player was still answering a `play` used to swallow that `play` (the kernel keeps one cancellation slot, and every slider step took it). The slider now reports one request for the whole drag, which the player answers once — see `media_core`'s request-number coalescing.
- `test/player_controls_controller_test.dart` now pins what viewer activity costs: a hundred `revealControls` reports inside one idle window notify nobody, and the window they marked is paid for once - the chrome falls two windows after the last report, not one. (Re-arming on every report, which is what the body used to do, hides it a window early; that is how the difference is observable from outside.)

## 0.1.0

Initial release.

- One line to start: `MediaCorePlayerView` = video surface + controls + pinch zoom + screenshot entry point, so hosts do not have to assemble UI.
- Six design languages: material, cupertino, fluent, macos, yaru and neumorphic share one control layer (state, actions, theme tokens), which is why all six behave identically and differ only in looks.
- Resolved per platform: Android→material, iOS→cupertino, macOS→macos, Windows→fluent, Linux→yaru; a style can also be forced with `PlayerControlsStyle`.
- The lower-level parts are public too: `PlayerControlsController` (state and actions) + `PlayerControlsTheme` (tokens) + `MediaPlayerView` (video only), which together are a custom control set.
- Theme and skin: progress track, thumb shape (`PlayerProgressTrack` / `PlayerProgressThumbShape`), button skin (`PlayerControlButtonSkin`) and double-tap action (`PlayerDoubleTapAction`) are all replaceable.
