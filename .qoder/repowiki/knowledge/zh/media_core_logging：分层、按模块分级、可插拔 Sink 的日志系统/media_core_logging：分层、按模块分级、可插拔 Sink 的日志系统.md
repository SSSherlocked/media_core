---
kind: logging_system
name: media_core_logging：分层、按模块分级、可插拔 Sink 的日志系统
category: logging_system
scope:
    - '**'
source_files:
    - packages/media_core_logging/lib/media_core_logging.dart
    - packages/media_core_logging/lib/src/media_core_log.dart
    - packages/media_core_logging/lib/src/player_logger.dart
    - packages/media_core_logging/lib/src/log_module.dart
    - packages/media_core_logging/lib/src/log_level.dart
    - packages/media_core_logging/lib/src/log_category.dart
    - packages/media_core_logging/lib/src/log_scope.dart
    - packages/media_core_logging/lib/src/log_filter.dart
    - packages/media_core_logging/lib/src/log_formatter.dart
    - packages/media_core_logging/lib/src/memory_log_sink.dart
    - packages/media_core_logging/lib/src/log_file_sink.dart
    - packages/media_core_logging/pubspec.yaml
---

## 1. 使用的系统与总体方案

仓库没有使用 `logging` / `logger` / `stack_trace` 等第三方日志框架，而是自实现了一个名为 `media_core_logging` 的独立 Flutter/Dart 包（`packages/media_core_logging`），作为整个工作区的统一诊断输出层。其核心设计是：**一个全局入口 + 每模块一个类别 + 可插拔 sink + 结构化字段 + 作用域字段**。

- 记录模型：`PlayerLogRecord`，包含 `LogLevel`、`LogCategory`、`message`、`timestamp`、可选的 `error`/`stackTrace`，以及 `Map<String, Object?> fields` 结构化字段。
- 级别枚举：`trace < debug < info < warning < error < critical < nothing`，其中 `nothing` 是默认生产级别，使未配置的宿主应用完全静默。
- 分类枚举：`general`、`player`、`session`、`source`、`playback`、`buffering`、`renderer`、`audio`、`presentation`、`recovery`、`fallback`、`cache`、`recording`、`danmaku`、`visibility`、`lifecycle`、`network`、`performance`、`memory`、`multiview`、`pool`、`download`、`logging`、`diagnostics`、`error`。
- 路由与过滤：`PlayerLogger` 维护多个 `PlayerLogSink`，支持最小级别、每类别级别覆盖、开发者级 `LogFilter`（按类别+关键字）和按类别的 `LogThrottle`（滑动窗口限流）。
- 作用域字段：通过 Dart `Zone` 实现的 `LogScope.run` / `LogScope.runAsync`，把 `roomId`、`engine` 等上下文自动附加到作用域内所有日志行。
- Sink 抽象：`LogSink` 接口 + `consoleLogSink()`（基于 `dart:developer`）、`MemoryLogSink`（环形缓冲内存日志）、`LogFileSink`（带大小/时间触发旋转的文件 sink）。
- 格式化：`LogFormatter` 提供单行文本格式，供 console/file sink 共享，避免控制台和 bug report 出现两种格式。

## 2. 关键文件与包

- `packages/media_core_logging/pubspec.yaml` — 包声明，仅依赖 `equatable`，无运行时日志框架依赖。
- `packages/media_core_logging/lib/media_core_logging.dart` — 库出口，导出所有公共 API。
- `packages/media_core_logging/lib/src/media_core_log.dart` — 全局静态入口 `MediaCoreLog`，持有唯一 `PlayerLogger`，暴露 `level`、`enabled`、`configure`、`setCategoryLevel`、`attachMemorySink`、`attachFileSink`、`install`、`reset` 等。
- `packages/media_core_logging/lib/src/player_logger.dart` — 核心路由器：级别判定、sink 分发、`Stream<PlayerLogRecord>`、计数统计、dispose 保护。
- `packages/media_core_logging/lib/src/log_module.dart` — 绑定单个 `LogCategory` 的轻量 logger，模块代码通过 `MediaCoreLog.of(LogCategory.playback).debug(...)` 调用，避免重复写类别名。
- `packages/media_core_logging/lib/src/log_level.dart` — `LogLevel` 枚举 + `LogLevelX` 扩展（`weight`、`isAtLeast`、`name`、`isError`）+ `LogLevelValue` 值对象。
- `packages/media_core_logging/lib/src/log_category.dart` — `LogCategory` 枚举 + `LogCategoryX.name` + `LogCategoryValue` 值对象。
- `packages/media_core_logging/lib/src/log_scope.dart` — 基于 `Zone` 的作用域字段容器，`fields` 在 scope 入口快照，嵌套 scope 合并且内层覆盖外层。
- `packages/media_core_logging/lib/src/log_filter.dart` — `LogFilter`（按类别集合 + 不区分大小写关键字匹配 message 和 fields）和 `LogThrottle`（按 category 的滑动窗口限流，被抑制次数会写入下一条记录的 `suppressed` 字段）。
- `packages/media_core_logging/lib/src/log_formatter.dart` — 单行格式器，支持 timestamp、category、structured fields、error、stack trace、category 对齐。
- `packages/media_core_logging/lib/src/memory_log_sink.dart` — `consoleLogSink()` 使用 `dart:developer.log`，name 为 `media_core/<category>`；`MemoryLogSink` 保留最近 N 条记录并提供 `forCategory`、`messagesFor`、`contains`、`dump`。
- `packages/media_core_logging/lib/src/log_file_sink.dart` — `LogFileSink` 带缓冲、定时/大小 flush、`maxBytes` 触发旋转（`file.1`、`file.2`…）、并发 flush 串行化（`_pending` chain）。

## 3. 架构与约定

### 3.1 全局入口 + 模块 logger

所有模块通过 `MediaCoreLog` 这个静态 hub 访问日志，而不是通过构造函数注入 logger。`MediaCoreLog` 内部维护一个 `_logger: PlayerLogger`，并通过 `levelResolver` 把 per-category 覆盖表链接进去，从而让“下载模块 trace，其他模块 warning”这类配置生效。

模块侧约定：
```dart
final _log = MediaCoreLog.of(LogCategory.playback);
_log.debug('opened', fields: {'uri': uri});
```
`LogModule` 缓存 `category`，每次调用时再解析当前 `_logger`，以便宿主调用 `MediaCoreLog.install` / `MediaCoreLog.reset` 后新 logger 能立即生效。

### 3.2 级别策略

- 默认全局级别是 `LogLevel.nothing`，即“生产环境零开销”。
- 级别顺序由 `LogLevel.weight` 决定：trace=0 … critical=5，nothing=6（最高权重，用于关闭某类别）。
- 每个 category 可通过 `MediaCoreLog.setCategoryLevel(category, level)` 或 `MediaCoreLog.configure(categories: {...})` 覆盖。
- `LogFilter` 是开发者调试用的第二道门（按类别集合 + keyword），`LogThrottle` 是热路径防刷屏的第二道门（默认关闭，因为注释明确说“打开日志的人希望看到发生了什么”）。

### 3.3 结构化字段与作用域

每条记录携带 `Map<String, Object?> fields`，用途是“机器可读的诊断信息”，不应替代主 message。作用域字段通过 `LogScope.run` / `runAsync` 注入，`PlayerLogger.log` 中先合并 scope fields，再合并 call-site fields，因此**调用点显式传入的字段优先级高于作用域字段**。

### 3.4 Sink 多路分发

`PlayerLogger` 维护 sink 列表，一条记录会依次传给所有 sink。默认安装 `consoleLogSink()`，宿主可以额外 `addSink(MemoryLogSink().call)` 或 `attachFileSink(File(...))`。`MediaCoreLog.attachMemorySink` / `attachFileSink` 是便捷方法，同时注册并返回 sink 实例。

### 3.5 输出格式

- Console sink：`[HH:mm:ss.SSS][category][LEVEL] message | key=value ...`，通过 `dart:developer.log` 输出，name 为 `media_core/<category>`，便于 DevTools 按类别过滤。
- File sink：由 `LogFormatter.format` 生成单行，格式类似 `[HH:mm:ss.SSS] [LEVEL] [category] message key=value error=...`，stack trace 单独换行（默认不打印 stack trace，避免控制台洪水）。
- Memory sink：`dump(formatter: LogFormatter())` 复用同一 formatter，保证 console 和 bug report 一致。

### 3.6 生命周期与资源

- `PlayerLogger.dispose()` 关闭 broadcast stream 并清空 sinks，之后调用任何方法抛 `StateError('PlayerLogger has been disposed.')`。
- `LogFileSink.close()` 等待 pending flush 完成后再标记 closed；flush 失败被吞掉，注释说明“log sink 抛出异常会把正在调试的代码一起拖垮，丢一行是正确的权衡”。
- `MemoryLogSink` 是固定容量环形缓冲，超过 capacity 丢弃最旧记录。

## 4. 约定与约束

- **默认静默**：`MediaCoreLog.defaultLevel` 是 `LogLevel.nothing`，未显式配置的宿主不会输出任何日志（见 `media_core_logging.dart` 文档注释与 `media_core_log.dart` 默认构造）。
- **每模块一类别**：每个子包在 `LogCategory` 中拥有稳定枚举成员，并通过 `MediaCoreLog.of(category)` 获取 logger，避免在每个调用点重复类别名（见 `log_module.dart` 注释）。
- **per-module 级别优先于全局级别**：`PlayerLogger.levelResolver` 将 `MediaCoreLog._categoryLevels` 接入决策链，确保“某个 category 设为 trace 不会被全局 minimumLevel 覆盖”（见 `player_logger.dart` 对 `levelResolver` 的注释）。
- **作用域字段不可变快照**：`LogScope.run` 在 zone 创建时复制 fields，嵌套 scope 合并且内层覆盖外层，值在 scope 入口捕获而非延迟读取（见 `log_scope.dart` 注释）。
- **Console 与 file 输出格式一致**：`LogFormatter` 被 console/file sink 共享，注释明确说明“开发者看控制台和 bug report 不应该需要翻译两种格式”（见 `log_formatter.dart`）。
- **Sink 不能破坏被 log 的代码**：`LogFileSink._writeBuffer` 吞掉异常，因为“log sink 抛出异常会把正在调试的代码一起拖垮”（见 `log_file_sink.dart` 注释）。
- **热路径限流默认关闭**：`throttle` 默认 null，注释解释“开发者打开日志后不希望第一条 burst 被静默隐藏”（见 `player_logger.dart`）。
- **错误级别判断**：`LogLevel.isError` 仅当 level 为 `error` 或 `critical` 时为 true（见 `log_level.dart`）。
- **级别名称解析别名**：`MediaCoreLog.levelFromName` 接受 `warn`→warning、`off`/`none`→critical、`fatal`→critical（见 `media_core_log.dart`）。
- **记录流**：`PlayerLogger.records` 是 `broadcast(sync: true)` 的 `Stream<PlayerLogRecord>`，供 UI 或诊断面板订阅。
- **包边界**：`media_core_logging` 只依赖 `equatable`，不依赖任何业务包；业务包通过 `MediaCoreLog` 静态 API 消费日志，形成单向依赖。

## 5. 在工作区中的使用痕迹

根目录 `.pubcheck/` 下存在大量 `<module>.log` 文件（如 `media_core_media_kit.log`、`media_core_playback.log`、`media_core_logging.log` 等），这些正是各模块通过 `MediaCoreLog` 输出的日志产物，印证了该日志系统是跨包统一的基础设施。