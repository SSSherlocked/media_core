# media_core

跨平台可复用的 Flutter 播放器核心：**一个与平台无关的编排层** + **按能力拆分的包**。

核心包（`packages/media_core`）内含 40 个模块，负责播放最难的那部分——会话与代际、命令串行化、
恢复决策、池化、事件归一化——但不含任何平台代码、UI 或主题。工作区共 24 个包：4 个后端适配、15 个能力包（含 UI、系统媒体面与平台探针）、日志与内存两个
基础设施包，以及被 vendor 进来的 media_kit。

> 📐 完整分层架构（模块职责、挂载点、数据流、恢复决策流）：[中文](docs/zh-Hans/architecture.md) ·
> [English](docs/en/architecture.md)
>
> 📚 各模块文档：`docs/zh-Hans/`（另有 [English](docs/en/README.md) 与 [繁體中文](docs/zh-Hant/README.md)）

## 30 秒接入

```dart
import 'package:media_core/media_core.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';
import 'package:media_core_mediasession/media_core_mediasession.dart';
import 'package:media_core_ui/media_core_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKitPlayerAdapter.ensureInitialized();

  // 系统媒体面（通知 / 锁屏 / SMTC / MPRIS）：一行，之后每个播放器自动上通知。
  await MediaSessionBootstrap.enable();

  final kernel = PlayerKernel()..registerBackend(const MediaKitAdapterFactory().registration());

  final handle = await kernel.create(
    source: PlayerSource(id: SourceId('demo'), uri: Uri.parse('https://example.com/video.mp4')),
    config: const PlayerConfig(autoPlay: true),
  );

  runApp(MaterialApp(
    home: Scaffold(
      // 视频 + 六套设计语言的控制条 + 双指缩放 + 截图，全在这一个 widget 里。
      body: AspectRatio(aspectRatio: 16 / 9, child: MediaCorePlayerView(handle: handle)),
    ),
  ));
}
```

`MediaCorePlayerView` 的风格按平台解析（Android→material、iOS→cupertino、macOS→macos、
Windows→fluent、Linux→yaru），也可以强制成任意一套：

```dart
MediaCorePlayerView(handle: handle, style: PlayerControlsStyle.neumorphic)  // 或 fluent / cupertino / …
```

要自己写界面时，底层零件同样可用：`MediaPlayerView`（只画视频）+ `PlayerControlsController`
（状态与动作）+ `PlayerControlsTheme`（令牌），三件加起来就是一套自定义控制条。

## 架构总览

```text
PlayerSource ─┐
              │   SourceService（解析 / 校验 / 探测）
              ▼
PlayerKernel ──▶ PlayerAdapterSelector ──▶ PlayerAdapterRegistry（media_kit / ijk / video_player / fvp）
    │                按协议、格式、直播能力、优先级打分选出后端
    │
    └── PlayerHandle（单个播放器的门面，公开操作的唯一入口）
            │
            ├── PlayerRuntime          组合根：adapter + session + playback + geometry + bindings
            │      ├── PlayerSession        会话 + Generation（过期异步结果据此丢弃）
            │      ├── PlaybackController   播放状态机（命令串行化）
            │      └── GeometryController   尺寸 / 旋转 / 比例
            ├── SessionController      会话生命周期状态
            ├── LifecycleController    前后台 / 激活 / 分离（AppLifecycleDriver 供电）
            ├── RecoveryLadder         **唯一的恢复决策点**：同后端重开 → 换线路 → 换后端 → 放弃
            ├── OperationTracker       操作记录（`onOperation` 可观测）
            └── ScreenshotManager      抓帧（引擎抓帧 / 渲染面抓取双通道；runtime 持有，handle 暴露）

PlayerKernel 另外持有跨播放器的协作对象：
    PlayerPool · PreloadManager · PlayerEventBus · GlobalPlayerCoordinator · 能力驱动（audio / presentation / platform）

单槽任务队列（`TaskManager`）不属于 handle，而是由需要"一次只做一件事"的能力包各自持有
（直播的线路/引擎扫描、下载队列），它是那些编排的序列化权威。
```

三条贯穿全仓库的规则：

- **能力靠声明，不靠猜**：`PlayerAdapterCapabilities` 是后端能力的唯一来源，`PlatformCapabilities`
  与 `PlatformCodecCapabilities` 是设备事实的唯一来源（由探针填报）；两者都保留"未知"的表达。
- **一个决策点**：恢复只有 `RecoveryLadder` 一处做决定（消费者用 `reportFailure` 上报、用
  `recoveryEvents` 观察），引擎切换必须验证播放进度真的在推进。
- **序列化即正确性**：公开操作进队列按序执行，队列自身状态是唯一的门（任务队列、操作注册表、
  代际守卫），不靠散落的布尔标志。

## 错误自愈链路

adapter 报错后，唯一决策点 `RecoveryLadder` 按梯级推进，每一步都要拿到**播放真的在走**的证据
（位置前进；直播换源后重新基线）才算成功：

1. **同后端重开**（`sameBackendReopen`）：原地重开当前源；
2. **换线路**（`nextLine`）：候选源列表里的下一个（直播多线路）；
3. **换后端**（`nextBackend`）：注册表里的下一个引擎，切换前先刷新签名 URL（单次有效）；
4. **放弃**：候选耗尽，发布带原因的终态事件。

全程通过 `PlayerEventBus` 与 `recoveryEvents` 可观测；重试预算、退避与候选策略来自
`PlayerConfig` / `KernelOptions` / `RecoveryPolicy`。

## 能力一览

| 包                              | 能力         | 一句话                                                                                                                         |
| ------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `media_core_ui`               | 播放器 UI    | **六套设计语言**（material / cupertino / fluent / macos / yaru / neumorphic）共用一层控制逻辑；含双指/双击缩放与截图按钮 |
| `media_core_mediasession`     | 系统媒体面   | 通知 / 锁屏 / SMTC / MPRIS + 音频焦点；**进程内一次 `enable()`，之后所有播放器自动挂载**                               |
| `media_core_native`           | 平台能力探针 | 编解码硬解与分辨率上限、内存/核数、系统特性，以及**后台保活**（前台服务/唤醒锁、防休眠）；五平台实现，答案随每个 session 与适配器下发 |
| `media_core_live`             | 直播         | 线路/引擎扫描、卡顿看门狗、宿主节奏的即时 retry（跑在单槽任务队列上）                                                                      |
| `media_core_feed`             | 抖音式上下滑 | 共用一个播放器换源、滑动吸附、下一项预载                                                                                       |
| `media_core_list_playback`    | 列表播放     | 单窗口上/下滑切换，按条目记忆进度，返回时续播                                                                                  |
| `media_core_multiview`        | 多画面同看   | 监控式视频墙：逐格健康度、唯一音频归属、解码预算、逐格弹幕、巡更轮巡、逐格列表                                                 |
| `media_core_danmaku`          | 弹幕         | 传输契约 + 消息归一化 + 去重/积压闸门 + 内容过滤 + 会话围栏                                                                    |
| `media_core_audio`            | 音乐         | 音源注册与解析（签名 URL 带过期）、队列与四种播放模式、歌词（LRC/翻译/逐字）、桌面歌词原生窗口、下载（ffmpeg）                 |
| `media_core_recording_ffmpeg` | 录播         | FFmpegKit 分段 MPEG-TS 录制 + CSV 日志；失败只丢几秒而非整场；进程默认取后台保活会话（熄屏继续录）                              |
| `media_core_download`         | 下载         | 有界并发队列、断点续传（先校验再续）、重试预算与进度                                                                           |
| `media_core_presentation`     | 呈现接缝     | 窗口级驱动契约 + 通用浮层舞台（槽位 / 悬停显隐），窗口类包共用                                                               |
| `media_core_fullscreen`       | 全屏         | 系统全屏与窗口级全屏两种变体，含横竖屏适配策略                                                                                 |
| `media_core_pip`              | 画中画       | 桌面置顶小窗（可锁宽高比）+ Android/iOS 系统 PiP（`native_picture_in_picture` 接管式）；移动端"能进不能出"是平台事实，如实返回                    |
| `media_core_logging`          | 分级日志     | 全局枢纽：分级/分类开关、多 sink（控制台/内存环/文件轮转）、作用域字段                                                         |
| `media_core_memory`           | 内存记账     | 按贡献者申报求和 + 设备实测快照；预算阈值驱动的四级压力                                                                        |

### 池化播放编排

`PlaybackPoolOrchestrator` 用**有界播放器池**驱动列表 / 信息流 / 直播：交换源而非重建（解码器只建一次），
可见性驱动 + 迟滞（半可见条目不反复起停），邻居预热，`ResourcePressure` 上升时先放弃预热再释放空闲。
播放器来自宿主实现的两个接缝 `PoolPlayerHost` / `PoolPlayerHandle`；`KernelPoolPlayerHost` 已把内核实例池接上，
各功能包给出推荐预设（`FeedConfig.recommendedPoolConfig`、`LivePoolPolicy.toPoolConfig()` 等）。

### 分级日志与内存

日志默认**完全静默**（`LogLevel.nothing`），由宿主开启；分类与模块一一对应，排查单个问题时只调高那一类：

```dart
MediaCoreLog.level = LogLevel.debug;
MediaCoreLog.setCategoryLevel(LogCategory.pool, LogLevel.trace);
final ring = MediaCoreLog.attachMemorySink(capacity: 500);
LogScope.run({'roomId': room.id}, () => player.open(source));   // 该作用域内每条日志都带房间号
```

内存有两个视角——"谁在用"（模块按贡献者 `report`/`withdraw`，可求和）与"一共多少"（设备真值由宿主安装
provider）。没有 Dart API 能报出解码器/纹理占了多少字节，所以模块上报的是保守**申报值**（用于排序与预算），
磁盘缓存/下载/录像是**实测值**；压力按 512 MiB / 70% / 85% 折算四级，并桥接进资源层的 `ResourcePressure`。

## 后端适配包

| 包                           | 后端                               | 工厂                           | 说明                                                                      |
| ---------------------------- | ---------------------------------- | ------------------------------ | ------------------------------------------------------------------------- |
| `media_core_media_kit`     | media_kit（vendor 在本仓库）       | `MediaKitAdapterFactory`     | 协议/格式覆盖最广，默认首选；自带解码策略（按设备能力决定硬解或直接软解） |
| `media_core_ijk_player`    | ijk（`flv_lzc`）                 | `IjkPlayerAdapterFactory`    | FLV / H.265，移动端                                                       |
| `media_core_better_player` | better_player_plus（video_player） | `BetterPlayerAdapterFactory` | 轻量、纯 Flutter 生态                                                     |
| `media_core_fvp`           | fvp（libmdk）                      | `FvpAdapterFactory`          | 另一条桌面/移动解码路径                                                   |

注册方式统一：`kernel.registerBackend(const XxxAdapterFactory().registration())`。

## 平台支持

|                                          | Android | iOS           | macOS | Windows         | Linux                      |
| ---------------------------------------- | ------- | ------------- | ----- | --------------- | -------------------------- |
| 播放（四个后端任选）                     | ✅      | ✅            | ✅    | ✅              | ✅                         |
| 系统媒体面（通知 / 锁屏 / SMTC / MPRIS） | ✅      | ✅            | ✅    | ✅              | ✅                         |
| 能力探针（硬解 / 设备 / 系统特性）       | ✅      | ✅            | ✅    | ✅              | ✅（逐编解码器待接 libva） |
| 系统 PiP                                 | ✅      | ⏳ 需帧投递层 | ⏳    | — 用应用内小窗 | — 用应用内小窗            |
| 桌面歌词窗口                             | ✅      | —            | ✅    | ✅              | ✅                         |

## 文档

- 中文：[docs/zh-Hans/README.md](docs/zh-Hans/README.md) · 架构：[architecture.md](docs/zh-Hans/architecture.md)
- English: [docs/en/README.md](docs/en/README.md) · Architecture: [architecture.md](docs/en/architecture.md)
- 繁體中文：[docs/zh-Hant/README.md](docs/zh-Hant/README.md)

包级细节：媒体面在 `packages/media_core_mediasession/README.md`，探针契约在
`packages/media_core_native/README.md`，权限与平台清单在 `packages/media_core_audio/doc/permissions.md`。

## 仓库约定

- **核心不依赖平台**：`media_core` 只依赖 Flutter、两个基础设施包（`media_core_logging` / `media_core_memory`）与少量纯 Dart 库；平台代码一律在能力包或 `media_core_native` 内。
- **能力包实现核心契约**：能力包通过 `KernelAudioDriver` / `KernelPresentationDriver` / `PlatformProvider`
  等接口挂到内核，核心永不反向依赖它们——所以能按需引入，也能整包移除。
- **未知 ≠ 不支持**：能力与设备事实的每一层都保留"未探测 / 未上报"的表达（`bool?`、`reported` 标志），
  由调用方决定"要不要试"，而不是把沉默当成否定。
- **模块的 `library.dart` 是生成的**（`// GENERATED MODULE LIBRARY` 头），新增模块时手工补一条导出。

## Workspace 布局

```text
packages/
  media_core/                       核心：40 个模块 + 编排层（kernel / handle / runtime）
  media_core_media_kit/             media_kit 适配（默认后端）
  media_core_ijk_player/            ijk (flv_lzc) 适配
  media_core_better_player/         video_player 适配
  media_core_fvp/                   fvp (libmdk) 适配
  media_core_native/                平台能力探针（android / ios / macos / linux / windows）
  media_core_ui/                    六套设计语言的控件
  media_core_mediasession/          通知 / 锁屏 / SMTC / MPRIS + 音频焦点
  media_core_audio/                 音乐：音源 / 队列 / 歌词 / 桌面歌词 / 下载
  media_core_presentation/          呈现接缝（窗口驱动契约 + 浮层舞台）
  media_core_fullscreen/            全屏（两种变体 + 方向策略）
  media_core_pip/                   画中画（桌面小窗 + Android/iOS 系统 PiP）
  media_core_danmaku/               弹幕
  media_core_live/                  直播编排
  media_core_feed/                  抖音式上下滑
  media_core_list_playback/         列表播放（进度续播）
  media_core_multiview/             多画面同看（监控式视频墙）
  media_core_recording_ffmpeg/      录播（FFmpegKit 分段录制）
  media_core_download/              下载（队列 + 续传 + 重试）
  media_core_logging/               分级日志
  media_core_memory/                内存记账
example</* */s/example/                   示例 App：9 个可运行页面 + 14 个模块速览
```

`media_kit`、`media_kit_video` 与 `fvp` 不随本仓库分发：前两个按 `packages/media_core_media_kit` 里固定的 ref
从 `Predidit/media-kit` 取，`fvp` 取 pub.dev 的 `^0.38.1`。所以这里**没有** PureLive 分支的那些补丁
（`setVideoOutputEnabled`、Windows 的 `frameRevision` 等），适配器不得依赖它们。

示例应用把上面每一件都做成可点、可看的面：`player`（生命周期与操作记录）、`live`（多线路与引擎回退）、
`feed`（上下滑）、`media-session`（自动挂载的系统媒体面）、`ui-styles`（六套风格实时切换 + 缩放 + 截图）、
`music`（音源 → 队列 → 歌词 → 桌面歌词 → 下载）、`multiview`（视频墙）、`presentation`（全屏 / PiP / 浮窗 / 弹幕）、
`memory`（内存仪表盘），外加模块速览里打印出来的平台探针报告与纯逻辑演示。
