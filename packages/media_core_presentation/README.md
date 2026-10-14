# media_core_presentation

`media_core` 的演示能力包：让画面以正确朝向铺满屏幕或缩成小窗，并提供叠在视频之上的通用图层系统。

## 定位

三件事：

- **朝向感知的演示**。横屏视频走横屏全屏、竖屏视频按配置走竖屏（或旋转 90° 用满横屏）；`PresentationCapabilityConfig` 编码这两条策略（`PortraitFullscreenStrategy.fill/fit/rotate`、`LandscapeOnPortraitStrategy.fit/fill`），宿主不必在每个 widget 里重推。`video_presentation_geometry.dart` 还带竖屏流探测（`PortraitStreamDetector`）、有效画面观测与 PiP 比例推导。
- **图层系统**。`MediaPlayerOverlay` + `PlayerOverlayLayer` 把任意内容（弹幕、字幕、控件、角标、水印）按 `PlayerOverlaySlot`（top/bottom/center/四角）叠到画面上，`PlayerOverlayVisibility` 决定它常显、跟控件显隐、还是隐藏时透传输入。桌面靠 hover 收放、触控设备恒显（`overlayHoverMode` 自动降级）。`PresentationStage` 把朝向感知的视频槽和这套图层组合成单 player 的全屏舞台。
- **一个把上面接进内核的驱动**。`MediaCorePresentation` 实现 `KernelPresentationDriver`，转发到桌面窗口驱动，并从适配器事件跟踪当前视频朝向。

`MediaCorePresentation` 只服务 **Windows / macOS / Linux**（`window_manager` 的全屏 + 常驻小窗 PiP）。在 Android/iOS 上 `apply` 抛 `UnsupportedError`——移动端请改用按平台拆分的独立包（见下）。

> 说明：`WindowManagerPresentationDriver`（本包内那个把全屏/PiP/悬浮捆在一起的驱动）**已被取代**。这些模式现在是各管一件事的独立包——[media_core_fullscreen](../media_core_fullscreen)、[media_core_pip](../media_core_pip)——经 `PresentationDriverChain` 组合。本类的捆绑驱动仅为已有依赖者的兼容保留，不再新增模式；本包仍在演进的是上面的**朝向几何**与**图层系统**。

## 用法

```dart
// 图层：竖屏感知的视频槽 + 弹幕 + 控件。
PresentationStage(
  presentation: presentation,
  videoBuilder: (context, orientation) => MyVideoSurface(orientation: orientation),
  layers: [
    PlayerOverlayLayer(
      slot: PlayerOverlaySlot.bottom,
      visibility: PlayerOverlayVisibility.withControls,
      builder: (_) => MyControlBar(),
    ),
    PlayerOverlayLayer(
      slot: PlayerOverlaySlot.center,
      ignorePointer: true,
      builder: (_) => DanmakuView(),
    ),
  ],
)

// 作为桌面演示驱动接进内核（仅 Win/macOS/Linux）。
final presentation = MediaCorePresentation();
await presentation.initialize();
kernel.presentationDriver = presentation;
presentation.observeKernel(kernel);
await kernel.enterFullscreen(playerId);
```

`PresentationCapabilityConfig` 是配置入口：朝向策略、PiP 尺寸/边距/标题、`overlayHoverMode`、`overlayAutoHideDelay`、弹幕安全区上下比例。

## 平台支持

| 能力 | Windows | macOS | Linux | Android | iOS | Web |
| --- | --- | --- | --- | --- | --- | --- |
| `PresentationStage` / `MediaPlayerOverlay` / 几何 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `MediaCorePresentation` 演示驱动 | ✅ | ✅ | ✅ | ❌ 抛 `UnsupportedError` | ❌ 抛 `UnsupportedError` | ❌ |

`PresentationStage`、图层系统与几何计算是纯 widget/计算逻辑，任何平台可渲染；`apply` 里的窗口调用只在桌面成立。移动端的系统 PiP 由 [media_core_pip](../media_core_pip) 承担；应用内浮层归宿主（`PresentationMode.floating` 是内核词汇，任何 widget 都能实现它）。

## 相关文档

- 全屏：[../media_core_fullscreen](../media_core_fullscreen)
- 画中画：[../media_core_pip](../media_core_pip)
- 主包与 `PresentationDriverChain`：[../media_core](../media_core)
- 仓库总览：[../../README.md](../../README.md)
