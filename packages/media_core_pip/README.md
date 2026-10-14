# media_core_pip

`media_core` 的画中画能力包：一个特性、一份契约、两类平台路径——桌面是应用自己掌控的常驻小窗，Android 是悬浮窗 overlay，iOS 是系统 PiP 窗口（经 `pip_kit`）。

## 定位

```text
desktop → 常驻顶部、按视频比例成形的小窗
  Windows    → Win32PipWindow（直接 user32 调用，无插件）
  macOS/Linux→ WindowManagerPipWindow（window_manager 插件）
  选择        → defaultDesktopPipWindow()，宿主可按平台注入
android → 应用上层悬浮窗（OverlayPipSystemPip，flutter_overlay_window；
          视频在第二个 Flutter engine 里重放 URL）
ios     → 系统 PiP 窗口（OverlayPipSystemPip，pip_kit；直接抬起 App 自己
          正在播放的播放器层，无二次解码、无移交）
web     → 不支持，availability 报 false
```

`PipDriver` 实现 `KernelPresentationDriver`，只服务 `PresentationMode.pip`；被 `PresentationDriverChain` 路由，其余模式（全屏等）交给别的驱动。桌面是应用完全掌控的窗口：抓快照、缩进角落、退出时还原。

## 移动端两条路径

`OverlayPipSystemPip` 同时服务两个移动平台，但两条路的机制不同：

### Android：flutter_overlay_window 悬浮窗

`flutter_overlay_window` 在所有应用之上开一个**可拖拽的悬浮窗**，悬浮窗的内容跑在**第二个 Flutter engine**（独立 isolate）里——它不知道主 engine 的任何状态，只能拿 URL 自己重新打开视频。所以 Android 进入 PiP 是一次**移交（handoff）**：

1. 驱动问宿主 `pipMediaResolver`：给一个新 engine 能自己打开的 URL（纯 HTTP(S) / file://，带签名头、私有协议、loopback 代理的源给不出来），外加当前播放位置；
2. 解析器返回 null → 请求抛 `UnsupportedError`，而不是弹一个空窗；
3. 悬浮窗打开后，包通过 messenger 通道把 `{url, position}` 发过去（含 `ready` 握手重发，防 engine 启动竞态）；宿主应在 `PresentationLifecycleHooks.beforeEnter` 暂停自己的引擎，避免两路声音；
4. 观看者点悬浮窗上的关闭 → 悬浮窗先回 `close` 事件（可携带进度）再关窗，驱动的 `onHandoffReturn` 把播放器交还宿主，`OverlayPipSystemPip.lastClosedPosition` 可读回进度。

悬浮窗窗口大小按视频比例从 `overlayShortSide`（默认 180 逻辑像素）推出，换算成物理像素传给插件（插件直接喂给 `WindowManager.LayoutParams`）；`enableDrag: true` + `positionGravity: auto`，拖动后自动吸边。

**宿主 App 必须配置**：

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
```

```dart
// main.dart：注册悬浮窗 engine 的入口点（必须有 pragma，否则 release 包找不到）
@pragma('vm:entry-point')
void overlayMain() => overlayPipMain(
  builder: (context) => MyOverlayVideoPage(),   // 从 OverlayPipSession.instance.payload 读 url/position
);
```

悬浮窗权限（`SYSTEM_ALERT_WINDOW`）在首次 `enable()` 时自动请求；被拒绝则报 `SystemPipStatus.unavailable`。

### iOS：pip_kit 系统 PiP

`pip_kit` 驱动系统画中画窗口**直接抬起 App 自己正在播放的 `AVPlayerLayer`**——没有第二个播放器、没有移交，App 的引擎一直在播。宿主需要：

1. 在 App 根部挂 `PipHost`（pip_kit 的要求）：

```dart
MaterialApp(
  builder: (context, child) => PipHost(child: child!),
);
```

2. 视频用平台视图渲染（如 `video_player` 的 `viewType: VideoViewType.platformView`），系统才有 layer 可抬；
3. 构造 `OverlayPipSystemPip(surfaceBuilder: ...)` 传入与屏上一致的播放器 widget（iOS 上 `PipContent.video` 不会真的绘制 builder，系统直接抬层）。

`SystemPipTrigger.onLeaveApp` 会映射成 pip_kit 的 `autoEnter`（离开 App 时自动缩窗）；`SystemPipMedia` 在 iOS 路径完全不需要——播放从未离开过本 App。

## 用法

```dart
// 装成驱动链里负责 PiP 的一环。
final pip = PipDriver(
  // Android 移交需要；iOS 不需要（给了也只在 Android 被调用）。
  pipMediaResolver: (playerId) async {
    final handle = kernel.get(playerId);
    final url = handle?.source?.uri.toString();
    if (handle == null || url == null || !url.startsWith('http')) return null;   // 私有协议交不出去
    return SystemPipMedia(url: url, position: handle.position);
  },
  onHandoffReturn: (playerId) async {
    // Android：从 OverlayPipSystemPip.lastClosedPosition 读回进度，恢复自己的引擎。
  },
  lifecycleHooks: PresentationLifecycleHooks(
    beforeEnter: (event) async => kernel.get(event.playerId)?.pause(),
  ),
);
await pip.initialize();            // 移动端会订阅系统 PiP 状态流
kernel.presentationDriver = PresentationDriverChain(bindings: [
  PresentationDriverBinding(modes: {PresentationMode.pip}, driver: pip),
]);

await kernel.enterPip(playerId);

// 移动路径需要先喂尺寸，否则 enable 抛 StateError。
pip.onVideoSize(1920, 1080);
```

后端可整体替换（`PipDriver(systemPip: ...)` / `desktopWindow: ...`）。`OverlayPipSystemPip` 自身的调参：`overlayTitle`（悬浮窗通知标题，默认取 `PipConfig.title`）、`overlayEnableDrag`（可拖拽，默认开）、`overlayShortSide`（悬浮窗短边，默认 180 逻辑像素）、`surfaceBuilder`（iOS 窗口内容）。

## 平台支持

| 路径 | Windows | macOS | Linux | Android | iOS | Web |
| --- | --- | --- | --- | --- | --- | --- |
| 桌面小窗 | ✅ `Win32PipWindow` | ✅ `WindowManagerPipWindow` | ✅ `WindowManagerPipWindow`（X11 完整；Wayland 下置顶/摆放由合成器裁决，`keep_above` 不保证生效） | — | — | — |
| 悬浮窗 / 系统 PiP | — | — | — | ✅ `OverlayPipSystemPip`（flutter_overlay_window，需 `SYSTEM_ALERT_WINDOW`） | ✅ `OverlayPipSystemPip`（pip_kit，iOS 14+；模拟器不支持） | ❌ |

## 依赖

- **`flutter_overlay_window: ^1.0.0`**——Android 悬浮窗：第二个 Flutter engine 渲染、可拖拽吸边。
- **`pip_kit: ^1.0.2`**——iOS 系统 PiP：抬起屏上播放器层，App 引擎不中断。
- **`media_core_win32`** 提供 `Win32PipWindow` 的直接 user32 FFI 通路（`window_manager` 的无边框快路径会跳过样式更新、其 `setSkipTaskbar` 有过崩溃报告，原生路径两者都没有）。

## 相关文档

- 全屏：[../media_core_fullscreen](../media_core_fullscreen)
- Windows FFI：[../media_core_win32](../media_core_win32)
- 主包与 `PresentationDriverChain`：[../media_core](../media_core)
- 仓库总览：[../../README.md](../../README.md)
