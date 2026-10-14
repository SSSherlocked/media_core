# FFmpeg 录播

<cite>
**本文引用的文件**   
- [README.md](file://packages/media_core_recording_ffmpeg/README.md)
- [media_core_recording_ffmpeg.dart](file://packages/media_core_recording_ffmpeg/lib/media_core_recording_ffmpeg.dart)
- [ffmpeg_recording_backend.dart](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart)
- [ffmpeg_record_arguments.dart](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart)
- [ffmpeg_executor.dart](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart)
- [ffmpeg_record_config.dart](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart)
- [recording_recovery.dart](file://packages/media_core_recording_ffmpeg/lib/src/recording_recovery.dart)
- [recording_verification.dart](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart)
- [recording_remuxer.dart](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart)
- [live_recording_watcher.dart](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart)
- [recording_manifest.dart](file://packages/media_core_recording_ffmpeg/lib/src/recording_manifest.dart)
- [ffmpeg_probe.dart](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_probe.dart)
- [ffmpeg_record_container.dart](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_container.dart)
- [output_path.dart](file://packages/media_core_recording_ffmpeg/lib/src/output_path.dart)
- [recording.md](file://doc/zh-Hans/recording.md)
- [ffmpeg_recording_test.dart](file://packages/media_core_recording_ffmpeg/test/ffmpeg_recording_test.dart)
</cite>

## 更新摘要
**变更内容**   
- 新增复杂分段录制机制与恢复策略
- 添加全面的输出验证系统
- 实现自动流恢复与退避策略
- 集成磁盘空间监控功能
- 增加停滞检测机制
- 扩展复用能力支持多种输出格式
- 完善结果验证与错误处理

## 目录
1. [简介](#简介)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构总览](#架构总览)
5. [详细组件分析](#详细组件分析)
6. [高级功能](#高级功能)
7. [依赖关系分析](#依赖关系分析)
8. [性能与参数调优](#性能与参数调优)
9. [故障排查与恢复](#故障排查与恢复)
10. [结论](#结论)
11. [附录：API 参考与示例路径](#附录api-参考与示例路径)

## 简介
本文件系统化梳理基于 FFmpegKit 的录制引擎，覆盖复杂分段录制机制、CSV 日志清单、格式复制策略、后台保活、状态监控与失败恢复。文档同时介绍新增的自动流恢复、磁盘空间监控、停滞检测、全面结果验证和复用能力，以及录制参数配置、输出格式选择、存储空间管理建议，以及完整的 API 使用路径与代码片段位置，帮助在不同平台稳定地实现直播流录制。

## 项目结构
该模块以"后端契约 + 参数构建 + 执行器抽象"的方式组织，并新增了多个高级功能模块：
- 对外导出统一的库入口，暴露后端、执行器、参数构建器和配置类。
- 后端负责会话生命周期、FFmpeg 进程控制、状态与进度上报、后台保活。
- 参数构建器负责把网络源和配置转换为 FFmpeg 命令行参数，并处理协议白名单、重连、头部等。
- 执行器抽象封装 FFmpegKit，便于测试替换与多实现扩展。
- 配置对象集中管理录制行为的可调项。
- **新增** 恢复机制处理流中断和地址刷新。
- **新增** 验证系统检查输出文件的完整性和可播放性。
- **新增** 复用器将分段文件合并为单一输出文件。
- **新增** 直播监视器管理房间状态和录制会话。
- **新增** 清单文件记录录制元数据和尝试历史。

```mermaid
graph TB
A["媒体核心<br/>RecordingManager / RecordingSession"] --> B["FfmpegRecordingBackend<br/>录制后端"]
B --> C["FfmpegRecordArguments<br/>参数构建器"]
B --> D["FfmpegExecutor / FfmpegKitExecutor<br/>执行器"]
D --> E["FFmpegKit<br/>原生进程"]
B --> F["BackgroundExecution<br/>后台保活/通知"]
C --> G["CSV 清单 + TS 分段<br/>输出目录"]
B --> H["FfmpegSegmentJournal<br/>分段日志"]
B --> I["FfmpegRecordingCheck<br/>结果验证"]
B --> J["FfmpegRecordingRemuxer<br/>文件复用"]
B --> K["FfmpegLiveRecordingWatcher<br/>直播监视"]
B --> L["FfmpegRecordingManifest<br/>录制清单"]
```

图示来源
- [media_core_recording_ffmpeg.dart:1-30](file://packages/media_core_recording_ffmpeg/lib/media_core_recording_ffmpeg.dart#L1-L30)
- [ffmpeg_recording_backend.dart:62-119](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L62-L119)
- [ffmpeg_record_arguments.dart:23-28](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L23-L28)
- [ffmpeg_executor.dart:67-88](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L67-L88)
- [recording_verification.dart:18-145](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L18-L145)
- [recording_remuxer.dart:132-156](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L132-L156)
- [live_recording_watcher.dart:154-171](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L154-L171)
- [recording_manifest.dart:20-30](file://packages/media_core_recording_ffmpeg/lib/src/recording_manifest.dart#L20-L30)

章节来源
- [media_core_recording_ffmpeg.dart:1-30](file://packages/media_core_recording_ffmpeg/lib/media_core_recording_ffmpeg.dart#L1-L30)
- [recording.md:1-30](file://doc/zh-Hans/recording.md#L1-L30)

## 核心组件
- FfmpegRecordingBackend：实现录制后端契约，负责启动/停止/取消、状态与进度、后台保活、退出码意图判定、内存与日志记录。
- FfmpegRecordArguments：生成 FFmpeg 参数，支持分段录制、音频中继、协议选项、头部规范化与安全文件名。
- FfmpegExecutor / FfmpegKitExecutor：抽象并封装 FFmpegKit 会话创建、统计回调、日志回调与销毁。
- FfmpegRecordConfig：集中管理录制行为的可调项，包括恢复策略、停滞检测和磁盘空间监控。
- FfmpegStatistics：仅携带录制有用的统计字段（时间、字节、比特率、速度、丢帧）。
- **新增** FfmpegSegmentJournal：解析和管理 CSV 分段日志。
- **新增** FfmpegRecordingCheck：验证录制结果的完整性和可播放性。
- **新增** FfmpegRecordingRemuxer：将分段文件复用为单一输出文件。
- **新增** FfmpegLiveRecordingWatcher：监控直播房间状态并管理录制会话。
- **新增** FfmpegRecordingManifest：记录录制元数据和尝试历史。

章节来源
- [ffmpeg_recording_backend.dart:62-119](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L62-L119)
- [ffmpeg_record_arguments.dart:23-28](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L23-L28)
- [ffmpeg_executor.dart:5-42](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L5-L42)
- [ffmpeg_record_config.dart:1-22](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L1-L22)
- [recording_verification.dart:18-145](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L18-L145)
- [recording_remuxer.dart:132-156](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L132-L156)
- [live_recording_watcher.dart:154-171](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L154-L171)
- [recording_manifest.dart:20-30](file://packages/media_core_recording_ffmpeg/lib/src/recording_manifest.dart#L20-L30)

## 架构总览
录制从上层 RecordingManager/RecordingSession 发起，由后端将源与配置转为 FFmpeg 参数，启动原生进程；过程中通过统计回调更新状态与后台通知；结束时根据"用户意图"而非"退出码"决定成功或失败。新增的验证系统确保输出文件可用，恢复机制处理流中断，监视器管理直播会话。

```mermaid
sequenceDiagram
participant Host as "宿主应用"
participant Manager as "RecordingManager"
participant Watcher as "FfmpegLiveRecordingWatcher"
participant Backend as "FfmpegRecordingBackend"
participant Args as "FfmpegRecordArguments"
participant Exec as "FfmpegExecutor"
participant Kit as "FFmpegKit"
participant Verifier as "FfmpegRecordingCheck"
participant Remuxer as "FfmpegRecordingRemuxer"
participant OS as "系统/后台服务"
Host->>Manager : start(source, config)
Manager->>Watcher : watch(source, config)
Watcher->>Backend : start(source, config)
Backend->>Args : recordArguments(...)
Args-->>Backend : argv(分段TS+CSV清单)
Backend->>OS : 申请后台保活/通知
Backend->>Exec : initialize()
Backend->>Exec : start(argv, onStatistics)
Exec->>Kit : createSession + execute()
Kit-->>Exec : statisticsCallback
Exec-->>Backend : FfmpegStatistics
Backend->>Host : onStateChanged(duration/bytes)
Note over Backend,Verifier : 流中断时自动恢复
Note over Backend,Verifier : 输出完成后验证完整性
Host->>Backend : stop()/cancel()
Backend->>Exec : stop()/cancel()
Exec->>Kit : cancelSession()
Kit-->>Exec : exitCode
Exec-->>Backend : exitCode
Backend->>Verifier : evaluate(journal, duration)
Verifier-->>Backend : verdict + check result
Backend->>Remuxer : run(manifest, directory)
Remuxer-->>Backend : remux result
Backend->>Host : RecordingResult(按意图判定成功/失败)
Watcher->>Host : session completed with outcomes
```

图示来源
- [ffmpeg_recording_backend.dart:141-210](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L141-L210)
- [ffmpeg_record_arguments.dart:47-139](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L47-L139)
- [ffmpeg_executor.dart:131-173](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L131-L173)
- [recording_verification.dart:223-301](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L223-L301)
- [recording_remuxer.dart:162-278](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L162-L278)
- [live_recording_watcher.dart:247-272](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L247-L272)

## 详细组件分析

### 录制后端 FfmpegRecordingBackend
职责与边界：
- 负责构建 FFmpeg 参数、持有进程、观察进度、结束进程并将结果映射为录制状态与结果。
- 不决定"录什么"，也不编排多个录制；这些由上层 RecordingManager 负责。
- 不合并分段文件；只写 CSV 清单供后续合并。
- **新增** 集成恢复机制处理流中断和地址刷新。
- **新增** 集成验证系统确保输出文件可用性。
- **新增** 集成停滞检测防止输入卡死。
- **新增** 集成磁盘空间监控避免写入失败。

关键流程要点：
- 启动时校验源类型（不支持本地文件）、输出目录、并发限制。
- 先申请后台保活，再启动 FFmpeg；失败时释放保活。
- 通过统计回调更新媒体时间与写入字节，并节流更新通知。
- 停止/取消会设置"意图"，避免用 255 退出码误判失败。
- dispose 统一走取消路径，确保所有结束分支都释放资源。
- **新增** 流中断时自动重试，使用指数退避策略。
- **新增** 输出完成后进行完整性验证。
- **新增** 停滞检测超时后主动终止进程触发恢复。
- **新增** 磁盘空间不足时拒绝开始录制。

```mermaid
flowchart TD
Start(["开始录制"]) --> Validate["校验源/目录/并发"]
Validate --> DiskCheck{"磁盘空间充足?"}
DiskCheck --> |否| DiskError["报告磁盘不足错误"]
DiskCheck --> |是| BuildArgs["构建 FFmpeg 参数"]
BuildArgs --> KeepAlive["申请后台保活/通知"]
KeepAlive --> Launch["启动 FFmpeg 进程"]
Launch --> Stats["监听统计回调<br/>更新 duration/bytes"]
Stats --> StallCheck{"检测到停滞?"}
StallCheck --> |是| StallTimeout["触发停滞超时"]
StallCheck --> |否| Notify["节流更新通知"]
Notify --> ExitWatch{"进程自行退出?"}
ExitWatch --> |是| IntentCheck{"是否用户主动停止?"}
IntentCheck --> |否| Recovery{"需要恢复?"}
Recovery --> |是| Backoff["指数退避重试"]
Backoff --> Launch
Recovery --> |否| Fail["报告错误状态"]
IntentCheck --> |是| Verify["验证输出完整性"]
Verify --> Success["报告完成状态"]
ExitWatch --> |否| StopCancel["stop/cancel 触发"]
StopCancel --> SetIntent["设置意图(stop/cancel)"]
SetIntent --> AwaitExit["等待退出码"]
AwaitExit --> Release["释放保活/清理资源"]
Release --> End(["结束"])
```

图示来源
- [ffmpeg_recording_backend.dart:141-210](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L141-L210)
- [ffmpeg_recording_backend.dart:214-284](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L214-L284)
- [ffmpeg_recording_backend.dart:403-457](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L403-L457)
- [recording_recovery.dart:3-76](file://packages/media_core_recording_ffmpeg/lib/src/recording_recovery.dart#L3-L76)

章节来源
- [ffmpeg_recording_backend.dart:33-61](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L33-L61)
- [ffmpeg_recording_backend.dart:141-210](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L141-L210)
- [ffmpeg_recording_backend.dart:214-284](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L214-L284)
- [ffmpeg_recording_backend.dart:292-401](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L292-L401)
- [ffmpeg_recording_backend.dart:403-457](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L403-L457)

### 参数构建器 FfmpegRecordArguments
能力与约束：
- 生成两段参数：分段录制（MPEG-TS + CSV 清单）与纯音频中继（localhost HTTP）。
- 强制复制编码（-c copy），不进行转码，保证录制性能与质量无损。
- 启用分段与 CSV 清单，使崩溃后仍可获得可播放片段，且能拼接。
- 对网络输入启用重连与超时；对 RTSP/UDP/RTP 做针对性优化。
- 规范化请求头，拒绝非法头名，避免凭据静默丢失。
- 安全化文件名前缀，防止路径穿越与非法字符。

```mermaid
classDiagram
class FfmpegRecordArguments {
+recordArguments(url, outputDirectory, segmentPattern, journalPath, headers, filePrefix) String[]
+audioRelayArguments(url, port, rwTimeout, headers) String[]
+inputProtocolOptions(rawUrl, rwTimeout) String[]
+usesNetworkInput(rawUrl) bool
+normalizeHeaders(headers) Map~String,String~
+buildHeader(headers) String
+safeFilePrefix(value) String
+timestampPrefix(time) String
+formatArguments(arguments) String
}
```

图示来源
- [ffmpeg_record_arguments.dart:23-28](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L23-L28)
- [ffmpeg_record_arguments.dart:47-139](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L47-L139)
- [ffmpeg_record_arguments.dart:141-176](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L141-L176)
- [ffmpeg_record_arguments.dart:178-281](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L178-L281)

章节来源
- [ffmpeg_record_arguments.dart:47-139](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L47-L139)
- [ffmpeg_record_arguments.dart:141-176](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L141-L176)
- [ffmpeg_record_arguments.dart:178-281](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L178-L281)

### 执行器 FfmpegExecutor / FfmpegKitExecutor
设计要点：
- 抽象出初始化、启动、销毁接口，便于测试替换与多实现。
- FfmpegKitExecutor 封装 FFmpegKitExtended，转发统计与日志回调。
- 通过 Completer 跟踪会话完成，统一 isRunning/exitCode 语义。

```mermaid
classDiagram
class FfmpegExecutor {
<<interface>>
+initialize() Future~void~
+start(arguments, onStatistics, onLog) Future~FfmpegExecution~
+dispose() Future~void~
}
class FfmpegExecution {
<<interface>>
+isRunning bool
+exitCode Future~int~
+stop() Future~void~
+cancel() Future~void~
}
class FfmpegKitExecutor {
-_createSession
-_cancelSession
+initialize() Future~void~
+start(arguments, onStatistics, onLog) Future~FfmpegExecution~
+dispose() Future~void~
}
class _FfmpegKitExecution {
-_session
-_cancelSession
-_exitCode
-_running
+isRunning bool
+exitCode Future~int~
+stop() Future~void~
+cancel() Future~void~
}
FfmpegKitExecutor ..|> FfmpegExecutor
_FfmpegKitExecution ..|> FfmpegExecution
```

图示来源
- [ffmpeg_executor.dart:44-88](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L44-L88)
- [ffmpeg_executor.dart:91-179](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L91-L179)
- [ffmpeg_executor.dart:181-215](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L181-L215)

章节来源
- [ffmpeg_executor.dart:44-88](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L44-L88)
- [ffmpeg_executor.dart:91-179](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L91-L179)
- [ffmpeg_executor.dart:181-215](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L181-L215)

### 配置 FfmpegRecordConfig
可调项说明：
- keepAlive：是否保持后台运行（Android 前台服务+唤醒锁，macOS/Windows 睡眠断言，iOS 需声明后台模式）。
- segmentTime：分段时长（10..86400 秒），平衡碎片开销与容错范围。
- rwTimeout：读写超时（秒），避免死等。
- threadQueueSize：输入包队列大小，优先完整性。
- preferBestStream：优先首条音视频轨，避免多码率变体被录成多轨。
- filePrefix/segmentSuffix/journalSuffix：命名规范，便于识别与合并。
- keepAliveTitle/keepAliveIcon：通知标题与图标。
- **新增** restartLimit：最大重试次数。
- **新增** restartBackoff/restartBackoffMax：重试退避策略。
- **新增** stallTimeout：停滞检测超时。
- **新增** diskWatermarkBytes：磁盘空间水位线。

章节来源
- [ffmpeg_record_config.dart:1-22](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L1-L22)
- [ffmpeg_record_config.dart:24-97](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L24-L97)
- [ffmpeg_record_config.dart:99-121](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L99-L121)
- [ffmpeg_record_config.dart:198-227](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L198-L227)

### 分段日志与验证系统 FfmpegSegmentJournal & FfmpegRecordingCheck
**新增** 分段日志解析：
- 解析 FFmpeg 生成的 CSV 清单文件，提取分段信息。
- 处理部分写入的行和不完整的数据。
- 计算总分段数和总字节数。
- 支持多个尝试的日志合并。

**新增** 结果验证：
- 检查分段文件的完整性和可播放性。
- 区分完整、可疑和缺失三种结果。
- 可选使用 FFprobe 验证文件可解码性。
- 提供详细的失败原因和统计信息。

```mermaid
classDiagram
class FfmpegSegmentJournal {
+entries FfmpegJournalledSegment[]
+unreadableLines int
+totalBytes int
+isEmpty bool
+length int
+first FfmpegJournalledSegment?
+last FfmpegJournalledSegment?
+fromFile(file) FfmpegSegmentJournal
+fromFiles(files) FfmpegSegmentJournal
}
class FfmpegJournalledSegment {
+index int
+name String
+path String
+bytes int
+isPresent bool
}
class FfmpegRecordingCheck {
+verdict FfmpegRecordingVerdict
+segments int
+bytesOnDisk int
+missingSegments int
+stubSegments int
+unreadableSegments int
+journalLinesIgnored int
+reason String?
+isUsable bool
+evaluate(journal, claimedDuration, probe, minimumSegmentBytes) FfmpegRecordingCheck
}
enum FfmpegRecordingVerdict {
complete
suspicious
missing
}
FfmpegSegmentJournal --> FfmpegJournalledSegment
FfmpegRecordingCheck --> FfmpegSegmentJournal
```

图示来源
- [recording_verification.dart:18-145](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L18-L145)
- [recording_verification.dart:147-169](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L147-L169)
- [recording_verification.dart:171-337](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L171-L337)

章节来源
- [recording_verification.dart:18-145](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L18-L145)
- [recording_verification.dart:147-169](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L147-L169)
- [recording_verification.dart:171-337](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L171-L337)

### 文件复用器 FfmpegRecordingRemuxer
**新增** 文件复用功能：
- 将分段文件复用为单一输出文件。
- 支持 MP4、Matroska 和 MPEG-TS 目标格式。
- 使用 concat demuxer 进行高效合并。
- 跳过已存在的输出文件以避免重复工作。
- 记录复用过程的内存使用和进度。
- 清理临时列表文件。

```mermaid
classDiagram
class FfmpegRecordingRemuxer {
-_executor FfmpegExecutor?
-_probe FfmpegProbe?
-_memory MemoryAccount
-_memoryKey String
+run(manifest, directory, target) FfmpegRemuxResult
+combinedName(prefix, target) String
+_segmentsOf(manifest, directory) FfmpegJournalledSegment[]
+_concatList(segments) String
+_awaitExit(execution) Future~int?~
}
class FfmpegRemuxResult {
+success bool
+outputPath String
+bytesWritten int
+duration Duration
+skipped bool
+error Object?
+completed(outputPath, bytesWritten, duration) FfmpegRemuxResult
+alreadyThere(outputPath, bytesWritten, duration) FfmpegRemuxResult
+failed(outputPath, error) FfmpegRemuxResult
}
enum FfmpegRemuxTarget {
mp4
matroska
mpegTs
}
FfmpegRecordingRemuxer --> FfmpegRemuxResult
FfmpegRecordingRemuxer --> FfmpegRemuxTarget
```

图示来源
- [recording_remuxer.dart:132-156](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L132-L156)
- [recording_remuxer.dart:157-278](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L157-L278)
- [recording_remuxer.dart:284-328](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L284-L328)

章节来源
- [recording_remuxer.dart:132-156](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L132-L156)
- [recording_remuxer.dart:157-278](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L157-L278)
- [recording_remuxer.dart:284-328](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L284-L328)

### 直播监视器 FfmpegLiveRecordingWatcher
**新增** 直播房间监视：
- 定期轮询房间状态，检测直播开始和结束。
- 管理录制会话的生命周期。
- 处理快速重检查和抖动轮询。
- 跟踪录制结果和会话统计。
- 提供会话变更事件流。
- 处理探测失败和连接问题。

```mermaid
classDiagram
class FfmpegLiveRecordingWatcher {
-_backend FfmpegRecordingBackend
-_statusProbe LiveRoomStatusProbe
-pollInterval Duration
-recheckInterval Duration
-shortRecordingAfter Duration
-maxConsecutiveProbeFailures int
-maxAlmostStartRechecks int
-onLiveStart Function?
-onLiveEnd Function?
-_sessions StreamController
-_states StreamSubscription?
-_timer Timer?
-_pollInFlight Future?
-_recordings FfmpegRecordingOutcome[]
-_source RecordingSource?
-_config RecordingConfig?
-_liveSince DateTime?
-_recordingStartedAt DateTime?
-_title String?
-_session FfmpegLiveRecordingSession?
-_probeFailures int
-_running bool
-_recording bool
-_recheckSoon bool
-_rechecksTaken int
-_disposed bool
+watch(source, config) Future~void~
+stop() Future~void~
+dispose() Future~void~
+_check() Future~void~
-_poll() Future~void~
-_onRecordingState(state) void
-_finishRecording(state) void
-_schedule() void
-_cancelTimer() void
-_endSession() void
-_announce(endedAt) FfmpegLiveRecordingSession?
}
class FfmpegRecordingOutcome {
+startedAt DateTime
+finishedAt DateTime
+success bool
+bytesWritten int
+segments int?
+directory String?
+error Object?
+elapsed Duration
}
class FfmpegLiveRecordingSession {
+startedAt DateTime
+recordings FfmpegRecordingOutcome[]
+endedAt DateTime?
+title String?
+recordedFor Duration
}
FfmpegLiveRecordingWatcher --> FfmpegRecordingOutcome
FfmpegLiveRecordingWatcher --> FfmpegLiveRecordingSession
```

图示来源
- [live_recording_watcher.dart:154-171](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L154-L171)
- [live_recording_watcher.dart:172-230](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L172-L230)
- [live_recording_watcher.dart:247-532](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L247-L532)

章节来源
- [live_recording_watcher.dart:154-171](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L154-L171)
- [live_recording_watcher.dart:172-230](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L172-L230)
- [live_recording_watcher.dart:247-532](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L247-L532)

### 录制清单 FfmpegRecordingManifest
**新增** 录制元数据管理：
- 记录录制的起始时间、容器类型、分段时长。
- 存储源标签（不含敏感查询参数）。
- 跟踪所有尝试的日志文件列表。
- 维护版本兼容性。
- 提供 JSON 序列化支持。

章节来源
- [recording_manifest.dart:20-30](file://packages/media_core_recording_ffmpeg/lib/src/recording_manifest.dart#L20-L30)
- [recording_manifest.dart:61-119](file://packages/media_core_recording_ffmpeg/lib/src/recording_manifest.dart#L61-L119)
- [recording_manifest.dart:121-147](file://packages/media_core_recording_ffmpeg/lib/src/recording_manifest.dart#L121-L147)

## 高级功能

### 自动流恢复与退避策略
**新增** 智能恢复机制：
- 流中断时自动重新打开连接。
- 使用指数退避策略避免频繁重试。
- 支持 URL 刷新回调处理签名过期。
- 限制最大重试次数防止无限循环。
- 区分正常停止和异常中断。

**新增** 磁盘空间监控：
- 在录制开始前检查可用空间。
- 使用水位线阈值避免写入失败。
- 提供具体的磁盘不足异常信息。
- 支持平台特定的磁盘空间查询。

**新增** 停滞检测：
- 检测输入流停滞（无媒体时间推进）。
- 配置停滞超时时间。
- 自动终止停滞的进程触发恢复。
- 区分不同类型的停滞情况。

章节来源
- [recording_recovery.dart:3-76](file://packages/media_core_recording_ffmpeg/lib/src/recording_recovery.dart#L3-L76)
- [ffmpeg_record_config.dart:198-227](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L198-L227)
- [ffmpeg_recording_backend.dart:101-107](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L101-L107)

### 全面结果验证
**新增** 多层次验证：
- 文件系统级别：检查分段文件存在性和大小。
- 内容级别：使用 FFprobe 验证文件可解码性。
- 逻辑级别：检查分段连续性和完整性。
- 提供详细的验证报告和失败原因。

**新增** 结果分类：
- complete：所有分段完整且可播放。
- suspicious：部分分段缺失或损坏但仍可用。
- missing：没有任何可用的录制内容。

章节来源
- [recording_verification.dart:171-337](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L171-L337)
- [ffmpeg_probe.dart:10-52](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_probe.dart#L10-L52)

### 容器格式支持
**新增** 多种容器格式：
- MPEG-TS：默认格式，每个分段自包含，适合直播录制。
- Fragmented MP4：平台兼容性好，需要后处理合并。
- 支持不同的分段格式选项和优化。

章节来源
- [ffmpeg_record_container.dart:1-66](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_container.dart#L1-L66)

## 依赖关系分析
- 后端依赖参数构建器与执行器，解耦了"如何录制"和"用什么引擎录制"。
- 执行器依赖 FFmpegKit，但通过抽象屏蔽具体实现差异。
- 后台保活通过 BackgroundExecutionStarter 注入，便于测试与平台适配。
- 日志与内存统计通过 MediaCoreLog/MediaCoreMemory 上报，便于观测。
- **新增** 验证系统依赖 FFprobe 进行文件解码性检查。
- **新增** 复用器依赖执行器进行文件合并操作。
- **新增** 监视器依赖后端进行录制管理。
- **新增** 清单系统提供录制元数据管理。

```mermaid
graph LR
Backend["FfmpegRecordingBackend"] --> Args["FfmpegRecordArguments"]
Backend --> Exec["FfmpegExecutor"]
Exec --> Kit["FFmpegKit"]
Backend --> BE["BackgroundExecutionStarter"]
Backend --> Log["MediaCoreLog"]
Backend --> Mem["MediaCoreMemory"]
Backend --> Verifier["FfmpegRecordingCheck"]
Backend --> Remuxer["FfmpegRecordingRemuxer"]
Backend --> Watcher["FfmpegLiveRecordingWatcher"]
Backend --> Manifest["FfmpegRecordingManifest"]
Verifier --> Probe["FfmpegProbe"]
Remuxer --> Probe
```

图示来源
- [ffmpeg_recording_backend.dart:1-10](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L1-L10)
- [ffmpeg_recording_backend.dart:62-119](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L62-L119)
- [ffmpeg_executor.dart:91-179](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L91-L179)
- [recording_verification.dart:1-5](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L1-L5)
- [recording_remuxer.dart:1-9](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L1-L9)
- [live_recording_watcher.dart:1-15](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L1-L15)
- [recording_manifest.dart:1-6](file://packages/media_core_recording_ffmpeg/lib/src/recording_manifest.dart#L1-L6)

章节来源
- [ffmpeg_recording_backend.dart:1-10](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L1-L10)
- [ffmpeg_executor.dart:91-179](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L91-L179)

## 性能与参数调优
- 编码策略：始终使用复制（-c copy），避免转码带来的 CPU 与质量损失。
- 分段策略：默认 300 秒分段，兼顾可播放性与碎片开销；短于 10 秒会增加容器开销，长于一天无意义。
- 网络重连：HTTP(S) 开启重连与 5xx 重试，RTSP 使用 TCP，UDP/RTP 增大 fifo 并忽略非致命溢出。
- 队列与吞吐：threadQueueSize 默认较大，优先保证完整写入；可根据设备 I/O 调整。
- 时间戳修正：对网络输入启用 dts 阈值修正，避免 CDN 跳点导致播放异常。
- 输出偏移：保留 MPEG-TS 预卷偏移，避免拼接时丢弃负 DTS。
- 保活与通知：按媒体时间节流更新通知，避免频繁 UI 刷新；直播无总量，使用不确定进度。
- **新增** 恢复策略：指数退避避免频繁重试，合理设置最大重试次数。
- **新增** 停滞检测：根据网络条件调整超时时间，避免误判。
- **新增** 磁盘监控：设置合理的空间水位线，预留足够空间。
- **新增** 复用优化：跳过已存在的输出文件，减少重复工作。

章节来源
- [ffmpeg_record_arguments.dart:63-131](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L63-L131)
- [ffmpeg_record_arguments.dart:178-217](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L178-L217)
- [ffmpeg_record_config.dart:55-75](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L55-L75)
- [ffmpeg_recording_backend.dart:329-392](file://packages/media_core_recording_backend.dart#L329-L392)
- [ffmpeg_record_config.dart:198-227](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L198-L227)

## 故障排查与恢复
常见问题与对策：
- 无法启动录制：检查是否已调用 initialize；确认输出目录存在且可写；避免重复并发录制。
- 本地文件源报错：后端仅支持网络源；本地文件无需录制。
- 明文 HTTP 失败：Android 9+ 默认禁止明文，需在应用侧添加 network_security_config 与 usesCleartextTraffic。
- 后台录制中断：确认 keepAlive 开启；Android 需要前台服务与通知权限；iOS 需声明 audio 后台模式。
- 通知不更新：统计回调按媒体时间节流；若源时间回退会重置窗口，避免永久卡住。
- 退出码 255：可能是用户主动停止，也可能是崩溃；后端通过"意图"区分，不要仅凭退出码判断成败。
- 文件不可播放：确认未发生转码；检查分段与 CSV 清单是否齐全；必要时进行二次合并。
- **新增** 流中断频繁：检查 URL 是否需要刷新，调整重试间隔和最大次数。
- **新增** 磁盘空间不足：检查磁盘水位线设置，确保有足够的可用空间。
- **新增** 录制停滞：调整停滞超时时间，检查网络连接质量。
- **新增** 验证失败：检查分段文件完整性，查看 FFprobe 输出详情。
- **新增** 复用失败：确认分段文件格式一致，检查目标格式兼容性。

章节来源
- [ffmpeg_recording_backend.dart:141-210](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L141-L210)
- [ffmpeg_recording_backend.dart:214-284](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L214-L284)
- [ffmpeg_recording_backend.dart:417-457](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L417-L457)
- [recording_recovery.dart:25-76](file://packages/media_core_recording_ffmpeg/lib/src/recording_recovery.dart#L25-L76)
- [recording_verification.dart:339-363](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L339-L363)
- [recording_remuxer.dart:317-328](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L317-L328)
- [README.md:18-38](file://packages/media_core_recording_ffmpeg/README.md#L18-L38)
- [README.md:40-51](file://packages/media_core_recording_ffmpeg/README.md#L40-L51)

## 结论
该录制方案以"分段 + CSV 清单 + 复制编码 + 意图驱动"为核心，在直播场景下提供高鲁棒性：即使进程被杀或应用回收，也能最大限度保留可播放片段；通过后台保活与节流通知提升用户体验；通过参数构建器的严格校验与协议优化降低失败概率。新增的自动恢复机制、全面验证系统、磁盘空间监控和停滞检测进一步增强了系统的稳定性和可靠性。上层只需关注源与配置，后端负责工程化细节，便于跨平台复用与维护。

## 附录：API 参考与示例路径

### 快速上手
- 后端初始化与录制：
  - 初始化后端、创建管理器、启动录制、停止并获取结果。
  - 参考路径：[media_core_recording_ffmpeg.dart:6-17](file://packages/media_core_recording_ffmpeg/lib/media_core_recording_ffmpeg.dart#L6-L17)

- 直接调用后端：
  - 构造后端、传入源与配置、调用 start/stop。
  - 参考路径：[README.md:8-16](file://packages/media_core_recording_ffmpeg/README.md#L8-L16)

### 核心 API 速查
- 后端
  - 构造函数：FfmpegRecordingBackend({executor, config, outputDirectory, keepAliveStarter})
  - initialize()
  - start(source, config)
  - stop() → RecordingResult
  - cancel()
  - dispose()
  - state / onStateChanged / isAvailable / activeDirectory / setOutputDirectory()
  - 参考路径：[ffmpeg_recording_backend.dart:62-139](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L62-L139)

- 参数构建器
  - recordArguments(url, outputDirectory, segmentPattern, journalPath, headers?, filePrefix?)
  - audioRelayArguments(url, port, rwTimeout?, headers?)
  - inputProtocolOptions(rawUrl, rwTimeout?)
  - normalizeHeaders(headers)
  - buildHeader(headers)
  - safeFilePrefix(value)
  - timestampPrefix(time)
  - formatArguments(arguments)
  - 参考路径：[ffmpeg_record_arguments.dart:47-281](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L47-L281)

- 执行器
  - FfmpegExecutor.initialize()
  - FfmpegExecutor.start(arguments, onStatistics, onLog)
  - FfmpegExecutor.dispose()
  - FfmpegExecution.isRunning / exitCode / stop() / cancel()
  - 参考路径：[ffmpeg_executor.dart:67-88](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L67-L88), [ffmpeg_executor.dart:181-215](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_executor.dart#L181-L215)

- 配置
  - FfmpegRecordConfig.defaults
  - 字段：keepAlive, keepAliveTitle, keepAliveIcon, segmentTime, rwTimeout, threadQueueSize, preferBestStream, filePrefix, includeTimestampPrefix, segmentSuffix, journalSuffix
  - 参考路径：[ffmpeg_record_config.dart:1-22](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L1-L22), [ffmpeg_record_config.dart:24-97](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L24-L97)

- **新增** 恢复相关
  - UrlRefresher: 流地址刷新回调
  - DiskSpaceProbe: 磁盘空间查询回调
  - FfmpegRecordingDiskFullException: 磁盘不足异常
  - FfmpegRecordingGaveUpException: 恢复放弃异常
  - 参考路径：[recording_recovery.dart:3-76](file://packages/media_core_recording_ffmpeg/lib/src/recording_recovery.dart#L3-L76)

- **新增** 验证相关
  - FfmpegSegmentJournal.fromFile/fromFiles: 分段日志解析
  - FfmpegRecordingCheck.evaluate: 结果验证
  - FfmpegRecordingVerdict: 验证结果枚举
  - FfmpegRecordingFailure: 录制失败异常
  - 参考路径：[recording_verification.dart:18-363](file://packages/media_core_recording_ffmpeg/lib/src/recording_verification.dart#L18-L363)

- **新增** 复用相关
  - FfmpegRecordingRemuxer.run: 文件复用
  - FfmpegRemuxResult: 复用结果
  - FfmpegRemuxTarget: 目标格式枚举
  - FfmpegRemuxException: 复用异常
  - 参考路径：[recording_remuxer.dart:132-328](file://packages/media_core_recording_ffmpeg/lib/src/recording_remuxer.dart#L132-L328)

- **新增** 监视器相关
  - FfmpegLiveRecordingWatcher.watch: 开始监视
  - FfmpegLiveRecordingWatcher.stop: 停止监视
  - FfmpegLiveRecordingSession: 录制会话
  - FfmpegRecordingOutcome: 录制结果
  - 参考路径：[live_recording_watcher.dart:154-532](file://packages/media_core_recording_ffmpeg/lib/src/live_recording_watcher.dart#L154-L532)

- **新增** 清单相关
  - FfmpegRecordingManifest.read: 读取清单
  - recordingManifestName: 清单文件名
  - recordingSourceLabel: 源标签
  - 参考路径：[recording_manifest.dart:20-147](file://packages/media_core_recording_ffmpeg/lib/src/recording_manifest.dart#L20-L147)

### 录制状态与结果
- 状态：starting → recording → stopping/completed/error/cancelled
- 结果：RecordingResult(success, outputPath, duration, bytesWritten, error?)
- 参考路径：[ffmpeg_recording_backend.dart:214-245](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L214-L245), [ffmpeg_recording_backend.dart:449-457](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_recording_backend.dart#L449-L457)

### 实际示例路径
- 控制台演示（含录制启动与多实例）：
  - [example/lib/demos/console/recording_demo.dart:104-170](file://example/lib/demos/console/recording_demo.dart#L104-L170)
- 单元测试（参数构建、目录创建、并发限制、统计进度、通知更新）：
  - [ffmpeg_recording_test.dart:101-125](file://packages/media_core_recording_ffmpeg/test/ffmpeg_recording_test.dart#L101-L125)
  - [ffmpeg_recording_test.dart:257-319](file://packages/media_core_recording_ffmpeg/test/ffmpeg_recording_test.dart#L257-L319)
  - [ffmpeg_recording_test.dart:321-336](file://packages/media_core_recording_ffmpeg/test/ffmpeg_recording_test.dart#L321-L336)

### 输出结构与元数据
- 输出：分段 TS 文件 + CSV 清单（segment_list_type=csv）
- 命名：由前缀 + 序号 + 后缀组成；前缀安全化处理，后缀用于版本标识
- 清单：CSV 用于后续合并；不在此层合并
- **新增** 元数据：JSON 清单文件记录录制信息
- 参考路径：[ffmpeg_record_arguments.dart:105-131](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_arguments.dart#L105-L131), [ffmpeg_record_config.dart:90-97](file://packages/media_core_recording_ffmpeg/lib/src/ffmpeg_record_config.dart#L90-L97), [recording_manifest.dart:121-147](file://packages/media_core_recording_ffmpeg/lib/src/recording_manifest.dart#L121-L147)