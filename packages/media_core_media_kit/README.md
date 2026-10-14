# media_core_media_kit

以 [media_kit](https://pub.dev/packages/media_kit)（libmpv）为引擎的 media_core 后端适配器，四个后端里的**默认首选**：协议与容器覆盖最广，桌面平台原生可用。

## 定位

`MediaKitPlayerAdapter` 继承 `PlayerAdapterBase`、实现 `PlayerVideo`，把 mpv 接到 [media_core](../media_core) 的契约上：`onInitialize` / `onBeforeOpen` / `onOpen` / `onAfterOpen` / `onPlay` / `onPause` / `onStop` / `onSeek` / `onSetVolume` / `onSetRate` / `onSetAudioOnly` / `onApplyEngineOptions` / `onCaptureFrame` / `onClose` / `onDispose` 全部实现，画面侧是 `build()` / `available` / `attach()` / `detach()` / `setVideoFit()`。会话、串行化与恢复梯级来自核心，本包只管 mpv 细节。

**位置按 UI 节奏上报，不是按帧**：libmpv 的 `time-pos` 属性在**每一帧**都会触发一次事件，60fps 就是每秒 60 次 transport state 重建 + 每一层监听重绘，这是弱机上信息流一滑一顿的直接来源。适配器用 `PositionThrottle`（250ms、前缘立即出）把它收敛到每秒约 4 次：起播与 seek 仍然即刻到位（跳变越过节流窗口就直接放行），gap 内欠下的最新值在窗口关闭时补发，进度条不会停在旧位置。同族的 fvp 本来就是 500ms 轮询 —— 这条只是把事件驱动的那台拉回同一水位。

引擎来源在 `pubspec.yaml` 里钉到 commit：`Predidit/media-kit` 的 `media_kit` 与 `media_kit_video`，原生库由 media_kit 自己的 build hook 提供，**不**需要 `media_kit_libs_*`。注意这份 revision 不含 PureLive 分支的那些补丁（`setVideoOutputEnabled`、Windows 的 `frameRevision` 等），适配器也不依赖它们。这是 **git 依赖**：pub.dev 不接受带 git 依赖的发布，所以在 `media_kit` / `media_kit_video` 换回 hosted 版本（或本包改成 `publish_to: none`）之前，这个包只能按路径 / git 依赖分发。

后端 id 是 `kMediaKitPlayerBackendId = 'mpv'`（注册表与日志里看到的就是 `mpv`），`registration()` 默认 priority 100，高于 ijk（90）、fvp 与 better_player（80）。

## 用法

```dart
import 'package:media_core/media_core.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKitPlayerAdapter.ensureInitialized();            // 加载原生 libmpv

  final kernel = PlayerKernel()
    ..registerBackend(const MediaKitAdapterFactory().registration());   // priority 100

  final handle = await kernel.create(
    source: PlayerSource(id: SourceId('demo'), uri: Uri.parse('https://example.com/video.mp4')),
    config: const PlayerConfig(autoPlay: true),
  );
}
```

`playerConfiguration` 与 `videoControllerConfiguration` 是 media_kit 自己的类型，**原样递给引擎**，适配器不做任何归一化；要在运行时改，用引擎选项（mpv 属性）而不是这两个字段。`videoControllerConfigurationBuilder` 每次创建适配器都求值，所以宿主改了输出设置之后，下一次引擎重建就能拿到。

```dart
// 运行时调参：标量走 NativePlayer.setProperty，List 走 change-list（逐条 append + 读回 `<key>-count`）。
await handle.applyEngineOptions([
  const EngineOption('cache-secs', '30'),
  const EngineOption('glsl-shaders', ['filterA.glsl', 'filterB.glsl']),
]);   // 默认 effect 是 EngineOptionEffect.immediate：不能即时生效就重建引擎

// 逐源属性与宿主自持输入：配置在工厂上，每个新建的适配器都带上。
final factory = MediaKitAdapterFactory(
  beforeOpen: (player, source) async {/* 引擎已创建、URL 还没交出时写属性 */},
  customInputOpener: (player, recipe) async {/* 打开宿主自己持有的输入（回环租约、中继 socket） */},
);
```

源的 `metadata` 里带 `kMediaKitCustomInputKey`（或 `protocol == SourceProtocol.custom`）时，`onOpen` 交给 `customInputOpener`；否则是 `player.open(Media(uri, httpHeaders: ...))`，请求头来自 `PlayerSource.headers`。

画面：`MediaKitVideoView(adapter: ...)` 是"自定义 surface"的参考实现——它不调 `adapter.build()`，而是直接读 `adapter.videoController` 与 `adapter.fitListenable`，参数逐项对齐 `mkv.Video`。要自己搭 widget 树就从这两个 getter 出发；`setRenderTargetSize(width:, height:)` 能不重建播放器就改原生渲染目标尺寸。

## 这份能力表里有什么

- **抓帧**：`onCaptureFrame` 走 mpv 的 `screenshot`，返回解码后原始分辨率的画面（不要求 widget 在屏上），`image/jpeg` 与 PNG 都按请求满足；字幕只在 mpv 自己渲染字幕（libass 开着）且调用方要求烧录时才带上。
- **纯音频**：`setVideoTrack(VideoTrack.no())` 真的关掉视频轨，`available` 随之为 false，每次 open 后重新施加（恢复重开同一源时不会漏）。
- **复合源**：声明 `CompositeSupport.externalAudio`。DASH 双轨的主视频是 `player.open` 的目标，多出来的音轨用 mpv 侧信道 `change-list audio-files append` 挂上去（字幕走 `sub-files`），必要时把编排层算出的错帧换算成 `audio-delay`，并把该轨的请求头镜像到 `user-agent` / `http-header-fields`（mpv 取外部文件用的是全局网络选项）。挂不上就 `MediaCoreLog.warning` 报出来，绝不静默只剩画面。
- **解码帧心跳只在 Windows**：`estimated-vf-fps` 的观察者仅 Windows 启动，构造时 `_honestCapabilities` 会把声明收窄——否则直播看门狗会为一台健康设备上的流判卡顿，然后无穷地拆流重开。Web 同理把 `supportsScreenshot` / `supportsEngineOptions` 收成 false，并把 `compositeSupport` 收成 `none`（没有 `NativePlayer` 可写）。读实际能力请用 `adapter.capabilities`，不要读那个常量。
- **设备事实**：`PlayerAdapterContext.codecs` 来自平台探针。本包用它做的是**可见性**而非策略——track 列表里的编解码器若在这台设备上没有硬解，就记一条 warning；解码器选择仍然由调用方给的 `videoControllerConfiguration` 决定，没有自动降级策略。（`PlayerConsts` / `MpvPlatformProfile` 提供 `--vo` / `--ao` / `--hwdec` 的目录与逐平台归一化，给宿主的专家设置界面用。）
- 明确不做的：轨道与字幕选择、视频/音频滤镜、hwdec 信息查询、缓冲比例、章节、循环、播放列表、元数据、系统 PiP（`supportsFullscreen` 为 true，走 `defaultEnterNativeFullscreen`）。

直播源不接变速命令（`onSetRate` 直接返回）：mpv 会把没有"播放速度"可言的广播变调。音量按 mpv 的 0–100 换算，位置/时长在 `stop()` 后会被 media_kit 重放一次零值，适配器用 `_hasOpened` 挡住，免得上一个源的收尾泄漏进下一个代际。

## 平台支持

跟随 media_kit（libmpv）：Android、iOS、macOS、Windows、Linux 原生可用；Web 由 media_kit 驱动 HTML 元素，适配器能编译运行，但按上面所说把需要原生命令面的能力如实收窄。宿主在 `main` 里调一次 `MediaKitPlayerAdapter.ensureInitialized()`。

## 相关文档

- 核心与契约：[../media_core/README.md](../media_core/README.md)（`PlayerAdapterCapabilities` 在 `lib/adapter/`）
- 设备事实的来源：[../media_core_native/README.md](../media_core_native/README.md)
- 同层适配器：[media_core_fvp](../media_core_fvp/README.md) · [media_core_ijk_player](../media_core_ijk_player/README.md) · [media_core_better_player](../media_core_better_player/README.md)
- 仓库总览：[../../README.md](../../README.md)
