# media_core_recording_ffmpeg

用 FFmpeg（ffmpeg_kit_extended_flutter）把网络流录成**分段 MPEG-TS + CSV 清单**。

实现 [media_core](../media_core) 的 `RecordingBackend` 契约；"录什么"由宿主决定，"怎么排"由内核的
`RecordingManager` 决定，这里只负责：把源与配置翻成 FFmpeg 参数、持有进程、把进程结局映射成录制状态。

```dart
final backend = FfmpegRecordingBackend(outputDirectory: '/storage/recordings');
await backend.start(
  RecordingSource.network(url),
  const RecordingConfig(outputPath: '/storage/recordings'),
);
// …录制中…
final result = await backend.stop();     // 用户主动停止是"成功录制"
```

## 为什么是分段而不是一个文件

直播没有自然结尾。进程被杀、应用被系统回收时，一个正在增长的文件通常**播不了**——索引从来没写过。
分段各自可播，CSV 清单说明它们怎么接起来，所以最坏情况是"丢几秒"，而不是"丢几小时"。
退出码也不是成败判据：用户主动停止同样会得到 255，所以后端记录**意图**（stop / cancel）再据此汇报。

## 结果看的是文件，不是进程

意图解释了进程**为什么**结束，却没说录到了东西。一个开了坏 URL 的 FFmpeg 被杀之后，和被杀的有效录制
退出码一模一样，而空目录上的 `success: true` 只能等用户自己去发现。所以 `stop()` 汇报之前会把清单读回来：
清单里点名的段是否在盘上、大小够不够解码，再（默认）用 FFprobe 打开**首段与末段**——只有这两段，
一天的录制也只多两次原生调用，而不是每段一次。

- `FfmpegRecordingBackend.lastCheck` 是完整判定（段数、缺失/残段计数、结论与原因）。
- 上报的字节数是**盘上实测**，不是统计行里的 `size=`：分段模式下那个数说的是 muxer 自己的计数器，
  也就是"当前正在写的子文件"，用它汇报等于把录制报成了它的零头。
- `suspicious` 仍然是成功：已完成的段各自能播，缺的部分由 `reason` 说清楚。只有 `missing`（什么都没有）
  才是 `success: false`，错误对象是 `FfmpegRecordingFailure`（带退出码）。
- `FfmpegRecordConfig.verifyOutput` / `verifyPlayability` 关掉这两层；`probe` 可注入（真机默认用插件自带的 FFprobe）。

## 容器、命名与"录完再合并"

**容器**（`FfmpegRecordConfig.container`）只有两个选项，因为直播录制没有可靠结尾，容器必须做到"每段可播、被杀也不废"：

- `mpegTs`（默认）：每段都是自包含的 TS 流，合并就是字节级拷贝。
- `mp4Fragmented`：`empty_moov` + `frag_keyframe` + `default_base_moof`，每个分片自带 `moof`/`mdat`，
  播放器友好，但合并必须重新封装（不能直接拼接）。
  普通 MP4 被排除在外：它的 `moov` 索引写在文件末尾，进程被杀就得到一个不能播的文件；
  Matroska 也排除：崩在 cluster 中间会让文件时长说谎。
  段后缀默认跟着容器（`.clock-v1.ts` / `.clock-v1.mp4`），名字里带着 profile，
  免得旧时钟语义的段被误当成同一批拼在一起。

**命名**是三段规则，一处实现（`FfmpegRecordArguments.filePrefixFor`）：

- 前缀来自房间标题时会被清洗，但清洗**保留任何文字的字母和数字**（中文主播名不再被压成一串下划线），
  只丢掉文件系统与 shell 会当回事的字符，并截到 64 个码点 —— 段名会重复前缀，Windows 的长路径会直接失败。
- `includeTimestampPrefix` 决定没有前缀时生成 `20261013_182232_915` 还是 `recording`：
  多房间共用一个目录时需要前者，用了下面的"一录一档"时时间是目录在说。
- `subdirectoryPerRecording` 让一次录制独占一个子目录（默认关，避免把已习惯扁平布局的宿主的路径挪走）。
- 每次断流重开是 `_r1`、`_r2` 一组新文件 + 新清单，因为 `-n` 拒绝覆盖、而清单是整份重写。

**`<prefix>.clock-v1.json` 清单**（`writeManifest`）记录 startedAt、容器、段长、各次尝试的清单文件名与尝试数。
它记的是墙钟开始时间，参考实现用另起线程每秒写一条字幕来给长录制定位"这个画面是几点"，那个做法在停顿处会漂移；
存开始时间就能让读的人自己算。URL 的 query 不进这个文件 —— 直播地址的签名就是凭证。

**合并**（`combineLastRecording()` / `FfmpegRecordingRemuxer`）：读清单里的各次 journal → 生成 concat 列表（正斜杠，
因为 concat 解析器把反斜杠当转义）→ `-c copy` 到 mp4(faststart)/mkv/ts → FFprobe 验证 → 删掉临时列表。
它**故意不在 `stop()` 里做**：合并几小时要花真时间，手机不该因为一次整理而不能开始下一场录制；
输出已存在就跳过（`skipped`），因为崩在合并中途不该让用户下次打开应用时对着一个几小时的重复工作。

## 断流不是录制的终点

直播源会自己断：CDN 换片、房间编码器重启、签名地址过期，FFmpeg 都留下一个 255 —— 和用户主动停止
是同一个码。所以"没人要求它结束"的结局被当成**源**的失败，后端重开它：

- 重开前退避（`restartBackoff`，抖动用核心的 `RetryUtils.backoff`，上限 `restartBackoffMax`）。
- 只数"从没跑起来过"的连续失败（`restartLimit`）：跑到 `healthyAfter` 之后才断的不计数 —— 一小时断一次的流
  是正常录制，不是一个在失败的进程。
- 每次重开**重建整套参数**：新的 `-i` 地址（宿主给了 `urlRefresher` 就取新的）、新的段名前缀（`_r1`、`_r2`）、
  新的清单文件。FFmpeg 的 `-n` 拒绝覆盖已存在的输出，而清单每次都是整份重写，两次尝试共用一份就会把前一段的
  记录丢掉。最终判定读的是**全部清单**，字节与时长也是各次尝试的和（每个进程都从零开始计时）。
- `restartLimit: 0` 就是不重开 —— 断流即结束录制，这是"只按用户动作录"的宿主想要的。

另外两件事重开解决不了，单独盯着：

- **停顿**：`stallTimeout` 内没有任何**推进**（媒体时间与字节都停在原值）就由后端结束进程，交给上面的重开。
  FFmpeg 自己的 `-rw_timeout` 只管"读不回来"，管不了"HLS 清单一直在刷新但没有新片"。看门狗数的是定时器的
  次数而不是墙钟，因此在测试的假时钟里同样能触发。
- **磁盘**：给了 `diskSpace` 探针时，低于 `diskWatermarkBytes` 就不开头（并在重开前再问一次）；没给就跳过 ——
  Dart 没有可移植的问法，依赖那些插件不值当，而写满之后的失败 FFmpeg 自己会报。

## 看着房间，而不是猜时间

`FfmpegLiveRecordingWatcher` 补上后端不知道的那件事：**这个地址背后的人还没开播**。
它每轮问一次宿主给的状态探针（`LiveRoomStatusProbe` —— 只有宿主知道自家平台怎么说"直播中"，
也只有它持有那些 cookie），直播中就录，录完再问，看到关播就结束这一场。三条规则是这套循环的关键：

- **一次开播/关播各通知一次**（`onLiveStart`/`onLiveEnd`，同样的对象也在 `onSessionChanged` 里流出来）。
  直播源抖一下就是几秒钟的离线，逐次轮询都通知的话，20 个房间的监控半天就会被静音。
- **轮询带抖动**（复用核心的 `RetryUtils.backoff`，区间是 `pollInterval` 到它的 1.5 倍）：
  否则宿主同时盯着的 N 个房间会在同一秒打到同一个接口，然后一起被风控。
- **只录了几秒就结束的，很快再问一次**（`recheckInterval`，上限 `maxAlmostStartRechecks` 次）：
  主播重启编码器和房间关播看起来一模一样，等满一分钟就会错过正式开播的开头。超过那个次数就退回正常间隔 ——
  不然一个已经关掉的房间会被每十几秒问一次地问一整夜。

录着的期间**不再轮询**：流真的断了，FFmpeg 的读超时和停顿看门狗会结束进程，后端的重开自己会放弃，
watcher 从录制结束这件事本身得知房间没了，然后再问一次。同一件事派两个定时器去看，只会让它们互相打架。

探针顺带解析出来的播放地址会被直接用（`FfmpegLiveRoomStatus.live(url)`），因为再取一次地址就是第二次
签名请求 —— 而签名地址正是在这两次之间过期的。

## 后台与休眠

录制是"用户让它做、然后就不看了"的活。没有下面这层，屏幕一关，Android 会在几秒内冻结进程，
录制以一个说明不了任何原因的 FFmpeg 退出码结束。默认开启（`FfmpegRecordConfig.keepAlive`）：

- **Android**：前台服务（API 34+ 声明 `dataSync`）+ 通知 + `PARTIAL_WAKE_LOCK`（屏幕熄灭后 CPU 继续跑）。
  清单条目由 `media_core_native` 的插件清单合并进应用，`POST_NOTIFICATIONS` 也由它在第一次取会话时自己弹窗申请（应用不需要写这一步）。
  用户拒了通知权限时，前台服务与唤醒锁照旧生效（只是通知不可见），录制**照常进行**；只有平台连服务都不肯起时才拿不到会话（`acquire` 返回 null），录制依然继续，只是没有保护 —— 不会因为一条通知失败而挂掉录制。
  通知长什么样是宿主决定的：`keepAliveTitle` 给标题（默认 "Recording"）、`keepAliveIcon` 给宿主 `res/drawable` 里的图标名（默认用内置的录制字形），正文是"文件前缀 · 已录时长 · 已写字节"，每秒刷新一次；进度是**转圈**而不是进度条 —— 直播录制没有总量，画一根百分比条只是假装。刷新窗口按**媒体时间**量（就是 FFmpeg 报的那条时钟，也是用户拿去对数的那条），所以直播源掉线重连、`out_time_ms` 回跳时窗口会重新打开而不是从此"还没到点"——否则那条通知会一直停在断流前的秒数，而这正是用户判断"还在录吗"的唯一依据。
- **macOS / Windows**：持有睡眠断言（系统不睡，屏幕可以关）。
- **iOS**：只买到过渡窗口（约 30 秒）。要长时间后台录制，需要应用在 `Info.plist` 声明 `audio` 后台模式——
  这是应用的决定，库替不了；声明后录制才能在后台持续。
- **Linux**：⏳ 未实现（logind `Inhibit`）。

释放是"随录制结束"的，且覆盖每条结束路径（stop / cancel / 自行退出 / dispose）——通知不会比它描述的任务活得更久。

## 宿主的清单检查表（Android）

| 项 | 谁声明 |
| --- | --- |
| `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_DATA_SYNC`、`WAKE_LOCK`、`POST_NOTIFICATIONS`、`<service …foregroundServiceType="dataSync">` | `media_core_native` 的库清单（自动合并） |
| 运行时申请 `POST_NOTIFICATIONS`（API 33+） | `media_core_native`（第一次取会话时弹出；宿主也可自己先问，授权后不会重复弹） |
| **明文流**：`android:usesCleartextTraffic="true"` + `res/xml/network_security_config.xml` | 应用 |

最后一条是直播录制最常见的"在模拟器能录、真机不行"的原因：Android 9+ 默认禁止明文 HTTP，
而直播源大多是 `http://` 的 FLV/HLS。示例应用里有可直接抄的文件：
`examples/example/android/app/src/main/res/xml/network_security_config.xml`。
