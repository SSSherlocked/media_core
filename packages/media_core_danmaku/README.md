# media_core_danmaku

`media_core` 的弹幕会话模块：平台无关的传输契约、消息归一化、去重与积压闸门、内容过滤，以及"旧 socket 不能写进新房间"的会话围栏。

## 定位

弹幕的两端都不该由这个包拥有：一端是各家站点私有的 socket 协议，另一端是画面。中间那段——一个房间只有一个会话、切换不能串味、重连不能刷屏——才是每个做直播的应用都要重写一遍的脏活。依赖方向因此只有一个：`media_core` 与各能力包 → `media_core_danmaku`；平台协议在 adapter 包里实现 `DanmakuTransport`，画面由宿主实现 `DanmakuSink`（或直接用内置的 `FlameBarrageSink`）。

它解决四个具体问题：

- **旧 socket 写进新房间。** 换房间、改设置、播放器重载、小窗销毁可能落在同一个事件循环轮次里。`DanmakuController` 用核心的 `SerialExecutor` 把每一次连接/断开串行化，每次请求递增 epoch 作废排队中的旧操作，交给传输的监听器绑死 `(transport, roomKey, sessionToken)`——三个校验任一不过就丢弃回调。这和核心给播放用的代际围栏是同一个形状：身份 + 代际，而不是一个 `isConnected` 布尔。
- **重放与积压。** `DanmakuMessageGate` 把两种重复分开处理：带平台 `messageId` 的走 10 分钟长窗（id 无歧义，同 id 就是重放），没有 id 的退回"类型 + 发送者 + 文本"指纹的 2.5 秒短窗（够挡重连重放，又不会吃掉真实刷屏的"666"）；比 `maxMessageAge` 更老的直接丢，后台攒下的积压不会当成现场聊天渲染。未来时钟偏差只容忍有限量，超出的当畸形包。
- **房间在复制粘贴。** `DanmakuRepeatedFilter` 折叠不同账号发的同一句文本，`DanmakuSimilarityFilter` 折叠"666 / 6666 / 666！"这类近似重复，并把保留缓存与逐包比较预算拆成两个上限（缓存长不等于每包算得多）。`DanmakuFilterPolicy` 管的是观众自己拉黑的人和词，与去重是两件事，所以它能被几个房间共用。
- **小画面不是第二个会话。** `DanmakuOverlaySession` 有自己的队列、上限和寿命（隐藏即清空，免得回来时回放旧弹幕），`bindVisibility` 接的是任何一条可见性流——`PipDriver.onPipChanged` 或宿主自己的信号。本包因此不知道 PiP 与悬浮窗存在，那两个包也不需要弹幕依赖。

和核心的接线是实的：串行化与流关闭用核心的 `SerialExecutor` / `DisposeUtils`，决策写进 `LogCategory.danmaku`，队列占用按实例报进 `media_core_memory` 的 `MemoryModule.danmaku`。

## 用法

```dart
// 一条会话，画面出到主面 + 小窗；authProvider 只在连接时被调用。
final overlay = DanmakuOverlaySession();
overlay.bindVisibility(pipDriver.onPipChanged);

final session = DanmakuController(
  sink: DanmakuFanOutSink(
    primary: FlameBarrageSink(barrage, onSuperChatCard: showSuperChatCard),
    overlay: overlay,
    surfaceWidth: () => pipWidth,           // 回调不是值：小窗会边开边被拖大
  ),
  config: DanmakuConfig.defaults,
  policy: DanmakuFilterPolicy(blockedUsers: ['ad_bot'], blockedKeywords: ['私聊']),
  authProvider: (room) => DanmakuAuth(userId: me.id, token: me.token),
);

session.installTransport(siteTransport);      // 首次安装是同步的；再换就走 replaceTransport
await session.connect(DanmakuRoomRef(platform: 'site-a', roomId: '12345'));
```

消息管线只有一条，顺序就是"最便宜且最有决定权的先做"：闸门 → 屏蔽名单 → 重复折叠 → 相似度 → `DanmakuSink`。本地合成的 `system` 消息与观众自己发的回显豁免内容过滤。

```dart
session.onStateChanged.listen((state) => render(state.phase)); // connecting/connected/reconnecting/closed/failed
session.onFailure.listen((f) => report(f.kind));  // 弹幕失败不等于播放失败：聊天可以死，视频可以照放
session.needReconnect(room);                      // 同一个健康会话不该被生命周期噪声拆掉

DanmakuPlayerBinding.forHandle(controller: barrage, handle: handle).attach(); // 播/暂停/倍速/seek 与媒体同拍

session.updateConfig(DanmakuConfig.defaults.copyWith(similarityThreshold: 92));
session.policy = DanmakuFilterPolicy(blockedUsers: blocked); // 只赋值一个字段，所以是可变字段而不是 updatePolicy 方法
await session.recover(room, enabled: viewerSwitchOn); // 关了就 stop：恢复不会重开观众亲手关掉的 socket
await session.dispose();
```

`isConnected` 说的是 socket，`isSessionEstablished` 说的是会话——没有聊天集成的平台会不开任何东西就报到就绪，这种会话同样不该被无限重试。`DanmakuNotice` 给的是代码不是句子（`connecting` / `connected` / `connectionTimeout` / `unsupportedPlatform` / `recordingMode` / `maskedUserName`），措辞归宿主。`BarrageItemMapper` 是把归一化消息翻成 flame_barrage 条目的全部配对面；渲染参数一律来自 `BarrageConfig`，这里不另开一套同名旋钮。

## 平台支持

| 面 | 状态 |
| --- | --- |
| 会话、闸门、两个过滤器、播放器绑定 | ✅ 纯 Dart，无 `dart:io`、无方法通道，任何 Flutter 平台同一份代码 |
| 画面 | 由 flame_barrage 决定；不想要它的宿主实现 `DanmakuSink` 自行绘制 |
| 平台协议 | ❌ 本包不含任何站点的 transport 实现（仓库里只有测试与示例用的假传输），接入要自己实现 `DanmakuTransport` |

传输契约刻意是**单房间、单次使用**：一个实例为一个 `start` 而生、由 `stop` 而灭。复用实例会让上一个 socket 的迟到包被算到新房间头上，而那正是会话令牌要防的事。心跳也不归传输：它报告 `heartbeatInterval`，由会话来排定时器，应用被挂起或切后台时就不会积累并行的保活工作。

## 相关文档

- 主包与 `SerialExecutor`：[../media_core](../media_core)
- 逐格弹幕的消费方（视频墙）：[../media_core_multiview](../media_core_multiview)
- 小窗可见性流来自：[../media_core_pip](../media_core_pip)
- 内存记账：[../media_core_memory](../media_core_memory)
- 模块文档：[doc/zh-Hans.md](doc/zh-Hans.md) · [doc/en.md](doc/en.md)
- 仓库总览：[../../README.md](../../README.md)
