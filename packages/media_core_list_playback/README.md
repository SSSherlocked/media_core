# media_core_list_playback

`media_core` 的列表播放模块：一个有序列表在一个窗口里连续播，上下滑动切换条目，每条回到上次离开的位置继续。

## 定位

[media_core](../media_core) 内核负责"打开一个源、管理播放器生命周期"，不负责"一堆条目按顺序播、切换时记住进度"。本包把后者做成独立组件：

- `PlaybackListController` —— 核心：拥有 item list、当前 index、打开 / 切换 / 保存进度。
- **连点 / 快滑只落地最后一条**：`open` / `jumpTo` 在已有打开在飞时**改写目标**而不是排队，并在碰引擎之前、在回填「已打开」状态之前各确认一次自己是否仍然是当前条目。被掠过的行不会各付一次 decode，过期那次也不会把更新的行标成加载完成。
- `PlaybackListPlayer` —— 窄接口（open / seek / position / duration），`KernelPlaybackListPlayer` 桥接 `PlayerHandle`。
- `PlaybackProgressStore` —— 进度持久化接口；`InMemoryPlaybackProgressStore` 是 LRU bounded map，宿主可实现自己的 SharedPreferences / SQLite 版本。
- `PlaybackListConfig` —— resume 开关、完成阈值（默认 20 s）、最大记忆条目数（默认 200）。
- `PlaybackListItem` —— 条目描述（id + `PlayerSource`），id 与 URL 分离使进度在 URL 轮换后仍能对上。

## 用法

```dart
final controller = PlaybackListController(
  player: KernelPlaybackListPlayer(handle),   // handle 来自 kernel 的 PlayerHandle
  items: [
    PlaybackListItem(id: 'ep-01', source: PlayerSource(id: SourceId('ep01'), uri: url1)),
    PlaybackListItem(id: 'ep-02', source: PlayerSource(id: SourceId('ep02'), uri: url2)),
  ],
  store: InMemoryPlaybackProgressStore(),
);

// 打开第一条（自动尝试 resume）。
await controller.open(index: 0);

// 上滑 / 下滑：切换前先保存当前进度。
await controller.next();
await controller.previous();

// 列表变化（频道刷新）：保持当前条目不跳。
controller.updateItems(newItems);

// 离开列表：保存位置。
await controller.savePosition();

// 状态订阅。
controller.onStateChanged.listen((state) {
  print('${state.index + 1}/${state.count} resumedFrom=${state.resumedFrom}');
});
```

### Pool 集成

列表最适合池化：相邻条目已经 open 着，切换变成 source swap 而非冷启。传入 `pool` + `poolPlayerFactory` 即可：

```dart
final controller = PlaybackListController(
  pool: orchestrator,
  poolPlayerFactory: KernelPlaybackListPlayer.new,
  items: entries,
  store: store,
);
```

`PlaybackListConfig.recommendedPoolConfig` 提供了针对列表优化的 `PlayerPoolConfig`（preload 1 邻侧、keepWarm 3）。

## 平台支持

| 平台 | 状态 |
| --- | --- |
| Android / iOS / macOS / Windows / Linux / Web | ✅ 纯 Dart 逻辑层，平台由 `PlaybackListPlayer` 背后的内核决定 |

## 相关文档

- [media_core](../media_core) —— 主包内核、播放器池、`PlayerSource`
- [media_core_download](../media_core_download) —— 离线下载（与列表配合做"整季下载"）
- [项目总览](../../README.md)
