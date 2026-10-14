## Unreleased

- **Conformed to media_core's new signatures**: the live controller, pipeline and watchdogs call `setMute(muted:)`, `setAudioOnly(audioOnly:)`, `setBuffering(buffering:)` and read `PlayerKernel.presentationDriver` as assigned rather than attached, and the package's own boolean parameters became named. Public members are documented.

## 0.1.0

Initial release.

- Orchestration for non-seekable live streams: this package does not use `media_core`'s recovery ladder for on-demand playback — it decides what to switch and when.
- Line and engine sweep: a failing line is replaced by the next one; once lines run out the engine changes, so engine and line advance in pairs.
- Stall watchdog: the only criterion is whether the position advances (not each engine's own heartbeat), so a stall starts recovery; `LiveStallKind` classifies the stall and `LiveWatchdogRecoveryAction` names the action taken.
- Backoff retry: repeated failures retry on a backoff schedule instead of hammering the origin.
- Single-use URLs: signed URLs are one-shot, so hosts plug a refresh into both places the sweep can outlive them — `EngineFallbackSourceResolver` before an engine switch, `RecoverySourceResolver` before a recovery re-open.
- Serialization: the whole live chain runs on a single-slot task queue, so two switches can never race.
