## Unreleased

- **Conformed to the adapter contract's new shape**: `onSetAudioOnly({required bool audioOnly})`, `emitBuffering(buffering:, resumePlaying:)` `setAudioOutputSuppressed(suppressed:)` takes a named boolean, and the package's public surface is documented.

- Re-exports the engine: `package:fvp/mdk.dart` (the mdk player API — `MediaInfo`, stream and codec info, …) and `package:fvp/fvp.dart` (`registerWith`, `VideoPlayerRegistrant`), so a host reaches them from its single dependency on this adapter. Nothing is hidden: `media_core`'s own public types use composed names (`PlayerIdentity`, `PlayerCoreState`, `PlayerTransportState`, `PlayerMediaType`), so importing both barrels stays unambiguous even against mdk's `Player`, `PlaybackState` and `MediaType`.

## 0.1.0

Initial release.

- fvp (libmdk) playback backend adapter: `FvpPlayerAdapter`, `FvpAdapterFactory`, `FvpVideoView`.
