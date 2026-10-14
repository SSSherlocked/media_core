# media_core_audio

`media_core` 的音乐播放模块：曲目来源与注册表、播放队列与播放模式、歌词与桌面歌词窗口、系统媒体面接入，以及 ffmpeg 下载。逻辑层，不含 UI 与主题。

## 定位

[media_core](../media_core) 的内核只回答"怎么把一个源播起来"。它不知道歌单该怎么推进、音质档位是什么、平台给的播放地址十分钟后就失效、LRC 里的 `<mm:ss.xx>` 该怎么对齐。本包把这些**音乐特有的决策**收在一处：

- **来源契约**：`MusicSource` 只规定三件事 —— 能搜（`search`）、能把曲目解析成可播地址（`resolveTrackSource`）、能给词（`resolveLyric`）。站点实现带着自己的加密、token 与 header 留在宿主 App 里，本包不内置任何平台知识；`MusicSourceRegistry` 按 `MusicTrack.sourceId` 把队列里的曲目路由回它自己的平台。自带的是 `LocalMusicSource`（扫目录、读同名 `.lrc`）。
- **一个引擎句柄播完整张歌单**：`AudioPlaybackController` 在首次播放时 `kernel.create()` 一次，之后每首歌重开同一个句柄。每首歌建一个播放器会把解码器启动成本变成用户听得见的延迟。
- **签名 URL 是一等公民**：`TrackSource.expiresAt` 让解析结果自带寿期；播放失败、或 `AudioPlaybackConfig.loadTimeout` 到点仍没播起来时，**先用重新解析的地址试一次**，再把失败上报 —— 这是区分"链接过期"和"这首本来就播不了"的唯一办法。失败的曲目在本会话内被标记，不再自动重试，队列照常往后走。
- **媒体面不重复实现**：通知 / 锁屏 / SMTC / MPRIS 与音频焦点属于 [media_core_mediasession](../media_core_mediasession)，因为视频宿主也要用同一套。本包提供 `MediaCoreAudio`（`MediaSessionDriver` 的子类）与 `MusicBackgroundBinding`（把队列、进度、transport 命令镜像过去），并保留 `AudioCapabilityConfig` / `MediaCoreAudioHandler` / `AudioHandlerState` / `AudioHandlerMediaItem` 四个历史名字的 typedef，老调用点不用改。

桌面歌词为什么连着原生窗口一起放在本包：判断"现在第几行、走到哪儿、锁没锁"是 Dart，而那扇窗是平台对象（Win32 layered window、Android `TYPE_APPLICATION_OVERLAY`、borderless `NSWindow`、GTK popup），两者用 `DesktopLyricTransport` 隔开。没有实现的平台 `isSupported()` 返回 `false`、`show()` 返回 `false`，宿主就不提供这个功能 —— 这不是错误状态。

## 用法

```dart
final kernel = PlayerKernel();
final registry = MusicSourceRegistry([LocalMusicSource(roots: ['/music'])]);
final player = AudioPlaybackController(kernel, registry: registry);

// 队列与播放模式：list / listLoop / singleLoop / random
await player.setQueue(tracks, startIndex: 0);
player.setPlayMode(PlayMode.random);
await player.playTrack(another, insertNext: true);      // 「下一首播放」
player.setQuality(MusicQuality.flac);                   // 下一首生效，不打断当前

// 歌词：解析 + LRU 缓存 + 并发合并；进度对应的当前行/词由 LyricTimeline 给出
final lyric = await player.loadCurrentLyric();
final line = lyric.lineAt(player.state.position);
```

```dart
// 桌面歌词窗口（show() 自己去要悬浮窗权限，并等用户从系统设置回来）
final overlay = DesktopLyricController(player);
if (await overlay.show()) {
  await overlay.setLocked(true);                        // 点击穿透
  await overlay.setStyle(const DesktopLyricStyle(fontSize: 32, opacity: 0.9));
}

// 后台播放 + 系统媒体面
final audio = MediaCoreAudio();
await audio.initialize();
kernel.attachAudio(audio);

// 退到后台默认暂停（由 PlayerKernel 观察并 deactivate 所有在播的 handle）。
// 旁白/播客要继续播：AudioPlaybackController(kernel, playerConfig: PlayerConfig(pauseWhenBackgrounded: false))。
final background = MusicBackgroundBinding(player, audio)..attach();

// 运行时权限
final permissions = AudioPermissionService();
await permissions.request(AudioPermission.notifications);  // Android 13+
await permissions.request(AudioPermission.mediaLibrary);    // 只在下本地库时要
```

```dart
// 下载：ffmpeg 处理 HLS / 签名 CDN / tag 写入 / 编码选择
final downloads = MusicDownloadQueue(maxConcurrent: 1, maxAttempts: 2);
final task = downloads.downloadTrack(
  track: track,
  source: await registry.resolveTrackSource(track, quality: MusicQuality.k320),
  directory: downloadDir,
  format: MusicDownloadFormat.copy,   // 容器不可直拷时自动转 mp3
);
downloads.updates.listen((t) => render(t.status, t.progress));   // progress 可能为 null
```

## 平台支持

pubspec 的 `flutter.plugin.platforms` 只声明了 **android / windows / macos / linux** —— 那是桌面歌词窗口与权限通道需要的原生实现。插件没注册的平台不会报错：`MethodChannelDesktopLyricTransport` 吞掉 `MissingPluginException` 并回答"不支持"，`AudioPermissionService` 在没有权限概念的平台一律回答"已授权"。

| 能力 | Android | Windows | macOS | Linux | iOS | Web |
| --- | --- | --- | --- | --- | --- | --- |
| 播放 / 队列 / 歌词 | ✅ | ✅ | ✅ | ✅ | ✅ | ❌（见下） |
| 桌面歌词窗口 | ✅ | ✅ | ✅ | ✅ | ❌ 无跨应用悬浮窗 | ❌ 网页出不了自己的标签页 |
| 媒体通知 / 锁屏 | ✅ `audio_service` | ✅ `audio_service_win`（SMTC） | ✅ 走 `audio_service` 的 iOS 实现路径 | ✅ `audio_service_mpris`（MPRIS） | ✅ `audio_service` | — |
| 下载 | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |

两点要说清：

- **Web 不支持。** `LocalMusicSource` 与 `MusicSourceRegistry.resolveTrackSource` 走 `dart:io` 的 `File`/`Directory`，歌词缓存与下载也按文件系统假设写的。这是设计取舍，不是待补的坑。
- **Linux 桌面歌词的点击穿透只在 X11 下成立。** 空输入形状是 X11 机制；Wayland 下锁住后控件会隐藏但仍吃掉输入。

平台清单与 manifest 需要声明哪些权限见 [`doc/permissions.md`](doc/permissions.md)。

## 相关文档

- 内核与句柄生命周期：[../media_core](../media_core)
- 系统媒体面与音频焦点的实现：[../media_core_mediasession](../media_core_mediasession)
- 日志分类与 sink：[../media_core_logging](../media_core_logging)
- 歌词缓存的内存记账：[../media_core_memory](../media_core_memory)
- 仓库总览与 30 秒接入：[../../README.md](../../README.md)
