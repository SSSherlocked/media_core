## Unreleased

- **Conformed to media_core's new signatures**: the cell volume and danmaku-feeding paths call `setMute(muted:)` and `setEnabled(enabled:)` by name, `FakeHandle`-style test doubles were updated to the new overrides, and the package's public members are documented.

- The stall sweep and the patrol rotation now skip a tick while their previous run is still awaiting the engine. Both were `Timer.periodic` bodies with async work inside, so a restart slower than the interval let the next tick see the same frozen cell, count another restart against the budget and issue another one - a wall of cells could spend its whole restart allowance on a single stall.

## 0.1.0

Initial release.

- Multi-cell live wall: `MultiviewController` runs N players side by side, laid out by `MultiviewLayout`.
- One audio owner: only one cell is audible at a time; `MultiviewAudioMode` decides whether that is a pinned cell, the focused one, or everything muted.
- Decode budget: `MultiviewBudgetPolicy` caps how many cells decode at once, with the rest downgraded or stepped aside according to policy.
- Quality policy: `MultiviewQualityPolicy` / `MultiviewQualityPreference` / `MultiviewQualityResolver` pick a resolution per cell from its size and the remaining budget.
- Per-cell health: `MultiviewCellStatus` and `MultiviewCellFailureKind` are tracked per cell, so one failing cell does not take the wall down.
- Per-cell danmaku: wired to `media_core_danmaku`, each cell filtering independently.
