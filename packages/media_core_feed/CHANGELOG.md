## Unreleased

- Swipe coalescing: a page requested while an attach is still running **replaces** the in-flight target instead of queueing behind it, and the target is re-checked immediately before any engine work. A fling from item 1 to item 8 now opens item 8 - previously every page crossed paid a full open and a state transition, which is what made fast scrolling stall.
- Reloading re-attaches: `load()` on a feed already sitting at index 0 used to no-op, so a pull-to-refresh kept playing the video that used to be there.
- `onPlaybackStateChanged` is a stable stream that follows the current player, so a page subscribing before `load()` no longer holds an empty stream for its lifetime.

## 0.1.0

Initial release.

- Vertical feed: `FeedPlayerController` keeps one shared player for the whole feed and hands playback to the item that is on screen.
- Configuration: `FeedConfig` carries the pool sizing a feed wants (`recommendedPoolConfig`: one active player, one preloaded, a warm window of three).
- Lifecycle: `FeedItemState` reports the visible item as `idle` / `opening` / `playing` / `paused` / `error`, published on `onItemStateChanged`; players for off-screen items belong to the pool, which decides when to stand them down.
- Optional next-item preload: start the next item early when the network allows it, so a swipe lands on already-playing video.
