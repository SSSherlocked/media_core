## Unreleased

- Position reporting is throttled to a UI cadence (250 ms, leading edge) instead of forwarded per frame. libmpv fires `time-pos` on every displayed frame, so a 60 fps video used to rebuild the transport state and repaint every listener 60 times a second per player - the main cause of feed/list stutter on weak devices. A seek or loop restart still lands immediately, and a value owed inside the gap is flushed when the gap closes so the bar never ends up a frame behind.

- Re-exports `package:media_kit/media_kit.dart` and `package:media_kit_video/media_kit_video.dart`, so a host that depends on this adapter alone gets the upstream API (`Media`, `Video`, `VideoController`, `PlayerConfiguration`, `MediaKit.ensureInitialized()`, …) without declaring them itself. Nothing is hidden: `media_core`'s own public types use composed names (`PlayerIdentity`, `PlayerCoreState`, `PlayerTransportState`, `PlayerMediaType`), so importing both barrels is unambiguous even for media_kit's `Player` and `PlayerState`.

## 0.1.0

Initial release.

- Backend adapter: `MediaKitPlayerAdapter` + `MediaKitAdapterFactory` connect media_kit to the media_core adapter contract (`PlayerAdapter` + `PlayerVideo`).
- View: `MediaKitVideoView` carries media_kit's rendering output.
- Engine options: `onApplyEngineOptions` writes mpv properties through `NativePlayer.setProperty` and reports per option what the engine actually took; a `List` value is a list option and travels as `change-list` (clear, then one `append` per entry) with a `<key>-count` read-back, because a comma-joined string makes mpv open one over-long file name.
- Per-source hooks: `beforeOpen` applies engine properties derived from the source itself, and `customInputOpener` opens a host-owned input (the recipe rides in the source metadata under `kMediaKitCustomInputKey`). Proxy and whitelist decisions stay with the caller — this adapter ships no built-in preset.
- Composite sources: declared `CompositeSupport.externalAudio`; the extra audio and subtitle essences are mounted on mpv's `audio-files` / `sub-files` side channel, with `audio-delay` alignment and the track's headers mirrored onto `user-agent` / `http-header-fields`. `kIsWeb` narrows the declaration to `none` (no `NativePlayer` to command), together with `supportsEngineOptions` and `supportsScreenshot`.
- Option catalogs: `PlayerConsts` (`--vo` / `--ao` / `--hwdec`) and `MpvPlatformProfile` (per-platform filtering and normalization) for host-side expert settings.
- Shares the kernel with the other backends: sessions, the recovery ladder and event normalization come from `media_core`.
