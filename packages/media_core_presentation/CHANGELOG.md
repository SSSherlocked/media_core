## Unreleased

- **Named booleans and complete docs**: `updateAvailability(available:)` and `updateEnabled(enabled:)` on the presentation controllers take named parameters, in line with the workspace's lint configuration. The classes nothing constructs (the legacy floating/PiP/fullscreen facades) are documented as such rather than dressed up.

- Hover layers: a pointer move inside the region now revives layers that faded on idle. A pointer that never left cannot send another enter event, so movement was the only available signal and it was ignored - the old code hid that by restarting the countdown on every move, which also meant a desktop mouse built and cancelled a `Timer` a hundred-plus times a second. The running countdown now notes the activity and re-arms once when it expires, and only the hidden→visible transition calls `setState`.
- A cancelled countdown is cleared as well, so leaving and returning does not strand the layers on screen.
- `test/player_overlay_hover_cost_test.dart` pins the cost, not just the look: fifty pointer reports inside one window rebuild the layer zero times (the pre-fix wiring rebuilt it 19 - the frames the reports actually landed in), and movement across a deadline buys exactly one more window instead of a timer per report.

## 0.1.0

Initial release.

- Presentation state coordination: fullscreen, picture-in-picture and the in-app floating window are mutually exclusive, and `PresentationStage` is the single value that says which one is active.
- Video-orientation awareness: `PortraitFullscreenStrategy` and `LandscapeOnPortraitStrategy` decide how a landscape video fills a portrait device and how a portrait video fills a landscape fullscreen.
- Overlays: `MediaPlayerOverlay` / `PlayerOverlaySlot` / `PlayerOverlayVisibility` show and hide controls, danmaku and other overlays with the presentation state, so no host has to work that out itself.
- Wired to the kernel's presentation module: the driver chain (`PresentationDriverChain`) keeps switches ordered and never lets two states be active at once.
