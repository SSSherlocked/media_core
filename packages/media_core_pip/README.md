# media_core_pip

`media_core` 的画中画能力包：一个特性、一份契约、两类平台路径——桌面是应用自己掌控的常驻小窗，Android / iOS 是系统 PiP 窗口（经 `native_picture_in_picture` 的原生播放器接管）。

## 定位

```text
desktop → 常驻顶部、按视频比例成形的小窗
  Windows    → Win32PipWindow（直接 user32 调用，无插件）
  macOS/Linux→ WindowManagerPipWindow（window_manager 插件）
  选择        → defaultDesktopPipWindow()，宿主可按平台注入
android → 系统 PiP 窗口（NativePipSystemPip，ExoPlayer 接管，API 26+）
iOS     → 系统 PiP 窗口（NativePipSystemPip，AVKit 接管，14+）
web     → 不支持，availability 报 false
```

`PipDriver` 实现 `KernelPresentationDriver`，只服务 `PresentationMode.pip`；被 `PresentationDriverChain` 路由，其余模式（全屏等）交给别的驱动。桌面是应用完全掌控的窗口：抓快照、缩进角落、退出时还原。

移动端两条被如实尊重的平台事实：

- PiP **可请求但无法从 Dart 退出**——`normal` 撤销不了它，状态跟随系统自己的 `statusStream`；
- Android 只接受 1/2.39..2.39 的比例，超出范围的形状退回系统默认而非让请求失败。

## 接管式 PiP：它意味着什么

`native_picture_in_picture` 不是"把现有画面缩进系统窗口"的桥——它**自带播放器**（ExoPlayer / AVKit），小窗里播的是它重新打开的那路流。所以移动端进入 PiP 是一次**移交（handoff）**：

1. 驱动问宿主 `pipMediaResolver`：给我一个**原生播放器自己能打开的 URL**（纯 HTTP(S) / file://，带签名头、私有协议、loopback 代理、DRM 的源给不出来），外加当前播放位置；
2. 解析器返回 null → 请求抛 `UnsupportedError`，而不是弹一个空窗口；
3. 原生播放器初始化、seek 到位置、起播、缩进 PiP；此刻宿主应暂停自己的引擎（`PresentationLifecycleHooks.beforeEnter`），避免两路声音；
4. 系统报窗口关闭（`didStop` / `restoreUI`）→ 驱动的 `onHandoffReturn` 回调把播放器交还宿主，宿主从 `NativePipSystemPip.position` 读回进度后恢复自己的引擎。

Android 侧插件用全屏 `SurfaceView(setZOrderOnTop(true))` 盖住 Flutter 再 `enterPictureInPictureMode`，等到第一帧真正渲染才收缩——进入动画期间整屏会被视频盖一下，这是插件的设计；退出/失败时它会拆掉这个 SurfaceView。**宿主 App 必须配置**（插件 README 同款要求）：

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<activity
    android:name=".MainActivity"
    android:supportsPictureInPicture="true" ... >
```
```kotlin
// MainActivity 必须继承 FlutterFragmentActivity，否则 enterPictureInPictureMode 无效
class MainActivity : FlutterFragmentActivity()
```
```xml
<!-- iOS: Info.plist -->
<key>UIBackgroundModes</key><array><string>audio</string></array>
```

## 为什么有的 App 的 PiP 窗口特别大（尺寸原理）

系统 PiP 窗口的尺寸不是 App 能直接指定的，规则是：

- **基准大小由系统定**：约取屏幕短边的 2/3（各版本略有出入），App 无法改这个数；
- **形状由 `setAspectRatio` 定**：不设 → 系统默认形状；竖屏比例（如 9:16）→ 高瘦的大窗。插件当前**写死 16:9 且不传 sourceRectHint**，所以窗口偏大、动画从全屏收缩而不是从播放器位置放大；
- **Android 12+ 默认可缩放**：用户拖角能把窗口放到接近半屏，这是"某 App 的 PiP 好大"最常见的真实原因；旧版本（或设了固定比例的 App）尺寸恒定；
- 想要"小"，唯一抓手是比例（横屏视频天然小）；想要"从正确位置飞进去"，需要 `setSourceRectHint`——这是插件侧的改进项，本包通过 `SystemPipMedia` 与 `SystemPipSourceRect` 已把信息备好，等插件开接口即可透传。

## 用法

```dart
// 装成驱动链里负责 PiP 的一环（移动端：声明接管式解析器）。
final pip = PipDriver(
  pipMediaResolver: (playerId) async {
    final handle = kernel.get(playerId);
    final url = handle?.source?.uri.toString();
    if (handle == null || url == null || !url.startsWith('http')) return null;   // 私有协议交不出去
    return SystemPipMedia(url: url, position: handle.position);
  },
  onHandoffReturn: (playerId) async {
    // 交还：把自己的引擎从系统播放器的进度续上（pip.position 可读）。
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
if (await pip.isAvailable) { /* 桌面恒 true；移动端问平台 */ }

// 移动路径需要先喂尺寸，否则 enable 抛 StateError。
pip.onVideoSize(1920, 1080);
pip.videoRect = videoRectOnScreen;   // 仅作进入动画的来源提示

// 桌面小窗的默认后端可替换：
PipDriver(desktopWindow: const WindowManagerPipWindow());   // 或 Win32PipWindow()
```

`PipConfig` 是调参入口：`width`/`height`（桌面小窗长短边，横屏流得 320x180、竖屏流得 180x320）、`minWidth`/`minHeight`、`cornerSpacing`、`skipTaskbar`、`title`、`restoreWindowOnExit`、`lockAspectRatio`、`requestSourceRectHint`（仅移动端、纯观感）。

## 平台支持

| 路径 | Windows | macOS | Linux | Android | iOS | Web |
| --- | --- | --- | --- | --- | --- | --- |
| 桌面小窗 | ✅ `Win32PipWindow` | ✅ `WindowManagerPipWindow` | ✅ `WindowManagerPipWindow`（X11 完整；Wayland 下置顶/摆放由合成器裁决，`keep_above` 不保证生效） | — | — | — |
| 系统 PiP | — | — | — | ✅ `NativePipSystemPip`（API 26+，需 FragmentActivity） | ✅ `NativePipSystemPip`（14+，需 audio 后台模式；模拟器不支持） | ❌ |

Linux 的摆放能力按 X11/Wayland 分档是 `window_manager` 的行为，本包不做"假定全部窗口操作都会成功"的分支——后端返回什么就如实上报什么；宿主需要更细的能力检测时，注入自己的 `PipWindow`。

## 依赖

- **`native_picture_in_picture: ^1.0.1`**（pub.dev）——Android/iOS 系统 PiP 的接管式播放器。
- **`media_core_win32`** 提供 `Win32PipWindow` 的直接 user32 FFI 通路（`window_manager` 的无边框快路径会跳过样式更新、其 `setSkipTaskbar` 有过崩溃报告，原生路径两者都没有）。

## 相关文档

- 全屏：[../media_core_fullscreen](../media_core_fullscreen)
- Windows FFI：[../media_core_win32](../media_core_win32)
- 主包与 `PresentationDriverChain`：[../media_core](../media_core)
- 仓库总览：[../../README.md](../../README.md)
