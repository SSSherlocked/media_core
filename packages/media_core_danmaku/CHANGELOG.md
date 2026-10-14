## Unreleased

- **Named parameters and full docs**: `DanmakuOverlaySession.setEnabled(enabled:)` and the rest of this package's boolean parameters became named, following the workspace's `very_good_analysis` configuration, and every public member now carries a doc comment. Nothing else about the overlay's behaviour changed.

## 0.1.0

Initial release.

- Danmaku sessions: `DanmakuController` and the `DanmakuSessionPhase` state machine, covering loading / connecting / paused / failed.
- Transport contract: the platform-agnostic `DanmakuTransport` interface plus a fan-out sink (`DanmakuFanoutSink`) that can feed several render slots at once.
- Message model: normalized `DanmakuMessage` (type, placement, time, color) and `DanmakuNotice`.
- Filtering and de-duplication: repeated filtering (`DanmakuRepeatedFilter`), similarity filtering (`DanmakuSimilarityFilter`) and one filter policy that always reports a reason (`DanmakuFilterReason`).
- Overlay: `DanmakuOverlaySession` / `DanmakuOverlayConfig` and session state (`DanmakuSessionState`).
- Failure classification: `DanmakuFailureKind` separates network, protocol, parsing and intentional close.
