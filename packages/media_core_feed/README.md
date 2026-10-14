# media_core_feed

`media_core` 的竖屏信息流（抖音/TikTok 式）播放：整个流共用一个播放器，滑到哪个条目就把播放交给它。

## 定位

信息流唯一的难点是**滑动必须免费**。每个页面各建一个播放器是"能跑但一滑就顿"的写法：每次滑动都付一次解码器建立，离开时又付一次销毁，而销毁正是泄漏和发热的来源。所以本包把"无限个条目"收敛成"少数几个播放器"，两种做法：

- **不带池**：整个流一个 `PlayerHandle`，`showIndex(i)` 把它重开到 `items[i]`。正确，但每次滑动仍是一次冷开。`preloadAhead` 时把下一条登记进 `kernel.preload(...)` —— 那是一条**预热意图**，不是已经开好的播放器。
- **带池**（`pool: PlaybackPoolOrchestrator(...)`）：邻居是真的 open 且 paused，滑动变成"在已打开的播放器上换个源"。此时 `preloadAhead` 被忽略：池自己决定谁保持打开，比排队一个意图强。`FeedConfig.recommendedPoolConfig` 就是信息流要的那组值 —— 同时只有一个在播、两侧各一个可及、3 个暖播放器覆盖无限流、空闲 30 秒回收。

其余几条是这个模块存在的理由，不是别处能顺手拿到的：

- **连滑只开落点那一页**：`showIndex` 在已有 attach 在飞时**替换目标**而不是排队。PageView 甩一把会连着报 1→2→…→8，逐页打开就等于把 8 次冷开串成一条可见的停顿；现在中间页只更新目标，引擎只在最后一个 index 上被碰（attach 前后各确认一次 `_index`，所以连"准备打开"都省了）。等待 `showIndex` 的调用方拿到的是同一条 settle future。
- **开不完就弃**：`showIndex` 打开成功后先确认可见条目还是不是它（`currentIndex`）—— 用户在这条还在 loading 时继续往下滑是常态，旧页面不能再回来改状态。日志把这条单独记一行，因为"停在原地的页面"和"被放弃的打开"看起来一模一样。
- **状态流是稳定的流，不是句柄快照**：`onPlaybackStateChanged` 内部按流身份重新挂接到当前播放器（`_reattachTransport`）。曾经的写法是 `_handle?.playbackStream ?? _pooledPlayer?... ?? Stream.empty()` 当场求值，于是在 `load()` 建出第一个播放器之前订阅的页面拿到一条空流，进度条永远停在 0。这里保留了重新挂接与 ValueStream 的当前值（时长不等到下一拍就出现）。
- **错误只报可见条目**：`onItemError` 对每个失败条目发一次 `PlayerFailure`，跳过、重试还是删除由宿主决定。**正在播的条目卡住**不是这里的事，那是 [../media_core_live](../media_core_live) 的看门狗与扫描；信息流里混直播源就要自己把那一层接上。
- **只记元数据**：账本走 `MediaCoreMemory.of(MemoryModule.playback)`，报的是条目数 × `MemoryEstimates.playbackItem`。媒体本身归播放器算，这样才能把"feed 攥着一条长列表"和"某个解码器在吃内存"区分开。

可见条目的状态是 `FeedItemState`：`idle` / `opening` / `playing` / `paused` / `error`。离开画面被留暖的条目停在 `paused`，用户在同一页按暂停也是 —— 两者对上层是同一个值。

## 用法

```dart
final feed = FeedPlayerController(kernel);

await feed.load(items, initialIndex: 0);          // items 是 List<PlayerSource>

feed.onIndexChanged.listen(updatePageIndicator);
feed.onItemStateChanged.listen(switchPlaceholderOverlay);
feed.onItemError.listen(decideSkipOrRetry);       // 每个失败条目一次
feed.onPlaybackStateChanged.listen(drawProgress); // 换条目也不用重新订阅

await feed.next();
await feed.pause();
await feed.setVolume(0.8);
await feed.setMute(muted: true);
await feed.dispose();                               // 不带池才把句柄还给 kernel
```

让滑动变成源切换而不是冷开 —— 池由宿主提供，`feed` 只取用结果：

```dart
final pool = PlaybackPoolOrchestrator(
  host: myPoolPlayerHost,
  config: FeedConfig.recommendedPoolConfig,
);

final feed = FeedPlayerController(kernel, pool: pool);
await feed.load(items);

// 带池时可见条目的句柄在 pooledPlayer 上（PoolPlayerHandle）；
// handle（PlayerHandle）只有当池的宿主就是这个 kernel 时才有值，
// 所以渲染表面应当先看 pooledPlayer。
final PoolPlayerHandle? pooled = feed.pooledPlayer;
final PlayerHandle? plain = feed.handle;
```

滚动视图归宿主：pager 每滚过一个位置就调用 `showIndex(index)`，它对"已经在这一条"是 no-op，所以每次滚动回调都调是安全的。

## 平台支持

纯 Dart 包：pubspec 只有 `flutter` 与 `media_core` 两个依赖，没有 `flutter.plugin` 段、没有平台代码。因此**平台支持完全等于内核注册了后端适配器的范围**，本包不额外要求任何能力。

它也不画任何东西：不渲染视频表面、不做滑动手势、不决定列表内容。宿主负责把 `PlayerSource` 列表滚动起来并回报可见 index，本包负责"该谁播、要不要预热、这一次打开还算不算数"。

## 相关文档

- 内核、`PlayerSource` 与 `kernel.preload`：[../media_core](../media_core)（`kernel` 与 `preload` 模块）
- 播放器池与 `PlaybackPoolOrchestrator`：`../media_core` 的 `pool` 模块
- 直播源的停顿与切线：[../media_core_live](../media_core_live)
- 元数据记账：[../media_core_memory](../media_core_memory)
- 仓库总览与 30 秒接入：[../../README.md](../../README.md)
