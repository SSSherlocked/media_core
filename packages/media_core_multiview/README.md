# media_core_multiview

`media_core` 的多画面视频墙：N 个独立直播格子排在一个网格里，带监控墙真正需要的四件事——逐格健康度、唯一的音频归属、解码预算、逐格弹幕。

## 定位

一面墙不是"把 N 个播放器摆在一起"。摆起来之后立刻有四件事没人管就会坏：

- **谁在响。** 九条流同时出声是噪音不是信息。`MultiviewAudioMode`（`exclusive` / `muted` / `mixed`）决定音量怎么分，而"被听的格子"与"被看的格子"是两个设置（`setAudioFocus` / `setVideoFocus`）：观众把声音钉在一个房间、眼睛扫别的房间是真实用法。`muteAll` 会记住静音前的模式，取消静音不会把一面 mixed 墙偷偷变成 exclusive。
- **解码器数量。** 每个格子是一个解码器。无视这点的墙不是多播了几路，而是把观众在意的那一路饿死。预算是 `MultiviewConfig.effectiveMaxCells`（布局容量与宿主 `maxCells` 取小者），`reportPressure(ResourcePressure)` 立刻生效而不是等下一次 tick——设备出问题时不该再等两秒。策略三选一：`keepFocusedOnly`（除焦点格外的播放格全部停下）、`letPlatformDrop`（交给平台丢帧）、`refuseNewCells`（到预算就拒绝新格子并抛 `StateError`）。`snapshot.budgetExceeded` 让宿主能把"这些格子为什么安静了"讲清楚，而不是留下九个看起来坏掉的窗口。
- **逐格死活。** `MultiviewCellStatus`（`empty` / `starting` / `playing` / `paused` / `offline` / `recovering` / `failed`）配 `MultiviewCellFailureKind`（解析失败 / 开流失败 / 停滞）。每 2 秒的 tick 检查每个播放格的位置是否还在前进，停滞超过 `cellStallTimeout` 就在 `cellMaxRestarts` 预算内重启；预算耗尽后带 playlist 的格子前进到下一个房间——这是"在监控"和"盯着一帧静止画面"的区别。**上一轮没跑完就不再开第二轮**：tick 是 `Timer.periodic` 而不等异步体，一次比 2 秒慢的重启若被后面的 tick 重复看到，同一格会被记第二次、第三次重启，预算就这样被幽灵扫描吃光；巡更（patrol）同理。`offline` 是业务状态不是故障：平台说没开播，就不该开一个播放器去制造一个观众早已知道原因的错误。
- **谁该看清晰。** `MultiviewQualityPolicy.focusFirst` 给焦点格 `best`、其余 `lowest`；但只有宿主知道自己的站点怎么换档，所以质量是注入的回调 `MultiviewQualityResolver`——没给就是没有降级，这一点写明而不是假装。焦点变化时本包只标记 `cell.hasVideoFocus`，真正换档时机由宿主决定：为了换档把正在播的格子拆了重连，代价是所有其他格子陪它重新缓冲。

墙通过核心的 `PoolPlayerHost` 取还播放器：换房间的格子复用热播放器，不必每次付一次冷启动；释放时先 `recycle` 再还给 host。弹幕是 `media_core_danmaku` 的 `DanmakuOverlaySession`，每格一个队列（共享一个就会让 A 格的积压出现在 B 格），`danmakuOnlyOnFocused` 只决定喂不喂。决策写进 `LogCategory.multiview`，占用按实例报进 `MemoryModule.multiview`（计入的是所有已指派格子，不只是在播的——暂停的格子还握着解码器）。

它不渲染网格（宿主从 `snapshot` / `onChanged` 画）、不解析房间与线路（宿主给 `MultiviewCellSource`）、不拥有窗口。

## 用法

```dart
final wall = MultiviewController(
  players: KernelPoolPlayerHost(kernel),
  config: MultiviewConfig.defaults.copyWith(
    layout: MultiviewLayout.nine,
    maxCells: 4,                       // 屏幕放得下九个，设备只养得起四个
    budgetPolicy: MultiviewBudgetPolicy.keepFocusedOnly,
    patrolEnabled: true,
  ),
  qualityResolver: (source, preference) => site.pickRendition(source, preference),
);

wall.onChanged.listen((snapshot) => setState(() => _snapshot = snapshot));

await wall.assignAll([
  MultiviewCellSource(
    source: PlayerSource(id: SourceId('cam-1'), uri: Uri.parse(directUrl)),
    title: '东门',
    roomId: 'gate-east',
    expiresAt: signedUntil,                       // 签名播流 URL 到点就作废
    renew: (current) => site.refreshPlayUrl(current.roomId!),  // 每次(重)开前调用
  ),
]);

// 会轮播的格子给它 playlist：失败或看完就前进，而不是重试同一个死掉的房间。
await wall.assign(3, primary, playlist: rotation);

await wall.setVideoFocus(2);
await wall.setAudioFocus(2);
await wall.reportPressure(pressure);
await wall.handOverCell(2, (playerId) => pip.enter(PlayerId(playerId)));  // 同一个播放器换个地方显示，流不重开

final danmaku = wall.ensureDanmakuFor(wall.focusedIndex);  // 焦点格的队列，宿主的 sink 往这里路由
await wall.dispose();                                      // 每格的播放器都还给 host
```

其余面：`pauseCell` / `resumeCell`（暂停的格子跳过停滞看门狗）、`restartCell`、`stopCell`、`clear` / `clearAll`、`advanceCell`、`setCellVolume` / `clearCellVolume`（手动音量只在被听的那一格压过音频模式，静音永远优先）、`startPatrol` / `stopPatrol`（巡检只跳到 `playing` 的格子，且 `patrolSkipsOfflineCells` 默认开）、`playerIdOf`、`updateConfig`（放大布局补空格，缩小则释放多出来格子的播放器）。

## 平台支持

| 面 | 状态 |
| --- | --- |
| 编排本体 | ✅ 纯 Dart，无 `dart:io`、无方法通道；任何 Flutter 平台同一份代码 |
| 画面 | 本包一个 widget 都不画：宿主读 `snapshot.cells` 自己排网格 |
| 实际能同时解几路 | 由设备与所选后端决定，不由本包决定——`maxCells` 与 `reportPressure` 是把答案告诉墙的两个入口 |

后端能报设备能力（核数、内存、逐编解码器硬解）的是 [media_core_native](../media_core_native) 的探针；资源压力经核心的 `ResourceManager` 汇总后由宿主用 `reportPressure` 送进来。本包不监听应用生命周期，也不切后台：恢复播放是宿主的 lifecycle 驱动与核心之间的事。

## 相关文档

- 播放器池与 `PoolPlayerHost` / `ResourcePressure`：[../media_core](../media_core)
- 逐格弹幕：[../media_core_danmaku](../media_core_danmaku)
- 格子交给小窗：[../media_core_pip](../media_core_pip)
- 设备能力探针：[../media_core_native](../media_core_native)
- 内存记账：[../media_core_memory](../media_core_memory)
- 仓库总览：[../../README.md](../../README.md)
