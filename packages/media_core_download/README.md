# media_core_download

`media_core` 的离线下载模块：任务队列 + 并发限制 + 可验证的断点续传 + 退避重试。

## 定位

[media_core](../media_core) 核心的 `TaskManager` 已有并发调度、优先级排序和取消能力；本包**复用它**而不是重建一套调度器，只加上下载特有的两件事：

- **暂停语义**：核心队列的状态是 created/queued/running/terminal，而"用户暂停"意味着任务离开队列但保留 partial file，不被下一次 slot 自动重启。
- **续传验证**：一个 partial file 只有在尾部字节匹配远端时才被信任；不匹配则 truncate 重头下载，避免"下载成功但文件播到某点断掉"这种最难排查的 corruption。

本包由以下公开 API 组成：

- `DownloadManager` —— 队列入口：add / start / pause / resume / cancel / retry / remove。
- `DownloadTask` —— 任务描述（url, filePath, headers, priority）与运行时状态（status, progress, error）。
- `DownloadStatus` —— idle → queued → running → completed / paused / stopped / failed / cancelled。
- `DownloadProgress` —— receivedBytes、totalBytes、speedBytesPerSecond、attempt。
- `DownloadConfig` —— maxConcurrent（默认 3）、maxAttempts、retryDelay、timeout、verifyTailBytes、userAgent 等。
- `DownloadResumePlanner` —— 断点续传决策（restart / resume / alreadyComplete）。
- `DownloadTransport` / `HttpDownloadTransport` —— 网络获取抽象（可替换）。
- `DownloadFileSink` / `IoDownloadFileSink` —— 本地文件操作抽象。

## 用法

```dart
final manager = DownloadManager();

// 订阅进度。
manager.onTaskChanged.listen((task) {
  final pct = task.progress.percent;
  print('${task.fileName}: ${pct == null ? '${task.progress.receivedBytes} B' : '$pct%'}');
});

// 添加任务。
manager.add(DownloadTask(
  id: TaskId('room-123'),
  url: streamUrl,
  filePath: '/storage/downloads/room-123.ts',
  headers: {'Referer': pageUrl},
));
// 暂停 / 恢复。
await manager.pause('room-123');
await manager.resume('room-123');

// 重试（清空 retry budget 后重新入队）。
await manager.retry('room-123');

// 清理已完成任务。
await manager.clearCompleted();
```

`onTaskChanged` 的**进度事件按 200ms 窗口发**，不是每个数据块发一次：快链路一秒能到几百块，每块都付一次任务拷贝、一次内存记账、一次监听唤醒，而画面上那个百分比根本读不出区别。首块仍立即上报（UI 不会开局空着），窗口是**按任务**记的（六个并发下载不会互相饿死），终态那次带精确字节数——节流只吃中间过程，不吃结果。

### 续传验证流程

1. 发现 partial file（`length > 0`）→ `DownloadResumePlanner.plan` 决定 restart / resume / alreadyComplete。
2. resume 时：向 transport 请求 `Range: bytes=<localBytes - verifyTailBytes>-`，拿回头部若干字节与本地尾部对比。
3. 匹配 → truncate 回验证起点、重写验证字节、从断点继续 append。
4. 不匹配 → truncate(0)，从头下载。

## 平台支持

| 平台 | 状态 |
| --- | --- |
| Android / iOS / macOS / Windows / Linux | ✅ 基于 `dart:io` HttpClient + File IO |
| Web | ❌ 依赖 `dart:io`；宿主需要自行提供 Web transport 与 file sink 实现 |

## 相关文档

- [media_core](../media_core) —— `TaskManager`、`PlayerTask`、`RetryUtils`
- [media_core_recording_ffmpeg](../media_core_recording_ffmpeg) —— 直播录制（共享 `media_core_native` 后台执行能力）
- [项目总览](../../README.md)
