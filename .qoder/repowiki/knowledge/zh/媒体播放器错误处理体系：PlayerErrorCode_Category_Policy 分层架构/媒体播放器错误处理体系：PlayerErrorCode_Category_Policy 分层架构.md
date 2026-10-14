---
kind: error_handling
name: 媒体播放器错误处理体系：PlayerErrorCode/Category/Policy 分层架构
category: error_handling
scope:
    - '**'
source_files:
    - packages/media_core/lib/error/player_error_code.dart
    - packages/media_core/lib/error/player_error_category.dart
    - packages/media_core/lib/error/player_exception.dart
    - packages/media_core/lib/error/player_failure.dart
    - packages/media_core/lib/core/player_error.dart
    - packages/media_core/lib/error/error_classifier.dart
    - packages/media_core/lib/error/error_policy.dart
    - packages/media_core/lib/error/error_formatter.dart
    - packages/media_core/lib/adapter/player_adapter_error.dart
    - doc/en/error.md
---

## 1. 采用的系统与方法

media_core 在 `packages/media_core/lib/error/` 下建立了一套**与 Dart 原生异常解耦**的错误模型，核心思路是：**错误码 + 分类 + 策略 + 格式化**四层分离。该体系不依赖第三方错误库（仅使用 `equatable`），也不使用 `freezed` 生成错误类型；适配器层 (`adapter/player_adapter_error.dart`) 是唯一使用 freezed 的例外。

关键组件：
- `PlayerErrorCode` — 稳定的机器可读错误码值对象（约 80+ 个内置常量，如 `NETWORK_ERROR`、`BACKEND_FATAL`、`RECOVERY_EXHAUSTED`）。
- `PlayerErrorCategory` — 宽泛的错误域分类值对象（source/network/decoder/renderer/audio/recording/lifecycle/fallback/recovery 等）。
- `PlayerException` — 运行时抛出的唯一异常包装，携带 code/message/cause/stackTrace/context。
- `PlayerFailure` — 不可变结构化失败数据对象，供上层策略消费。
- `PlayerError` — 带 PlayerId/SessionId/SourceId/RequestId/GenerationId 等上下文元数据的错误快照。
- `ErrorClassifier` — 将 `PlayerErrorCode` 映射到 `PlayerErrorCategory` 的纯函数。
- `ErrorPolicy` — 决定 retry/recover/fallback/fail 的策略引擎，返回 `ErrorPolicyAction`。
- `ErrorFormatter` — 负责用户消息、日志、调试输出三种格式。
- `ErrorContext` / `error_utils.dart` — 结构化诊断上下文。

## 2. 关键文件与包

| 路径 | 职责 |
|---|---|
| `packages/media_core/lib/error/player_error_code.dart` | 所有稳定错误码定义，含 `_potentiallyRecoverableCodes` 可恢复性标记 |
| `packages/media_core/lib/error/player_error_category.dart` | 错误域分类，含 networkRelated/mediaRelated/playbackRelated/resourceRelated/presentationRelated 分组 |
| `packages/media_core/lib/error/player_exception.dart` | 运行时异常包装，提供 `toFailure()` |
| `packages/media_core/lib/error/player_failure.dart` | 结构化失败数据，提供 `fromError`/`toException` |
| `packages/media_core/lib/core/player_error.dart` | 带完整 PlayerIdentity 上下文的错误快照 |
| `packages/media_core/lib/error/error_classifier.dart` | code → category 映射表 |
| `packages/media_core/lib/error/error_policy.dart` | shouldRetry/shouldFallback/shouldRecover/isTerminal/decide |
| `packages/media_core/lib/error/error_formatter.dart` | format/formatLog/formatDebug/formatContext |
| `packages/media_core/lib/adapter/player_adapter_error.dart` | 后端适配器专用错误（freezed，含 `requiresFallback`/`retryable`） |
| `doc/en/error.md` / `doc/zh-Hans/error.md` | 官方错误文档 |

其他模块也定义了各自领域的异常（如 `network/http_header_sanitizer.dart` 中的 `HttpHeaderError extends ArgumentError`、`task/task_errors.dart` 的 `TaskManagerDisposedException`、`reactive/stream_cancellation.dart` 的 `StreamCancelledException`），但统一通过 `PlayerFailure.fromError` 或 `PlayerException.from` 归一化进主错误模型。

## 3. 架构与约定

### 3.1 三层职责严格分离

代码注释中反复强调同一组约束（以 `PlayerFailure` 为例）：
- 分类由 `ErrorClassifier` 负责；
- 决策由 `ErrorPolicy` 负责；
- 展示由 `ErrorFormatter` 负责；
- 数据对象本身**不**决定重试、回退、恢复、格式化。

`ErrorPolicy` 明确区分两个问题：
> ErrorClassifier answers: "What kind of error is this?"
> ErrorPolicy answers: "What should the player do about it?"

### 3.2 错误码与分类的关系

`PlayerErrorCode` 和 `PlayerErrorCategory` 都是**值对象**而非枚举，允许应用/适配器自定义扩展。每个内置值同时维护一个 `value`（大写蛇形，如 `PLAYER_INVALID_ARGUMENT`）和一个 `name`（小驼峰，用于人类可读）。`ErrorClassifier.classify` 是唯一的 code→category 映射源，未知码降级为 `unknown`。

### 3.3 可恢复性标记

`PlayerErrorCode._potentiallyRecoverableCodes` 是一个显式集合，列出网络、TLS、backend、decoder、streamEndedUnexpectedly、resource、renderer、audio、fallback/recovery 等可能被自动恢复的错误。**注释明确声明**：这只是分类提示，不代表播放器一定会重试/回退/恢复——决策属于 policy 层。

### 3.4 策略决策流程

`ErrorPolicy.decide` 的优先级固定为：
1. cancelled/staleGeneration/superseded/disposed → ignore/cancel
2. shouldRetry → retry
3. shouldRecover → recover
4. shouldFallback → fallback
5. fail

`shouldRetry` 中 `nonRetryable` 集合优先级高于 `retryable`；默认 `defaults()` 已预置一组可重试（timeout/network/sourceResolveFailed/backendOpenFailed/playbackFailed/decoderError/resourceUnavailable/insufficientBandwidth）和不可重试（invalidArgument/unsupported/authenticationFailed/mediaCorrupted/disposed 等）的码集。

### 3.5 异常与结构化失败的互转

```dart
// 抛出异常时
throw PlayerException(code: ..., message: ..., cause: ...);

// 捕获后转为结构化失败
final failure = PlayerFailure.from(error, code: PlayerErrorCode.unknown);

// 策略消费
final action = ErrorPolicy.defaults().decide(failure);

// 需要向上抛出时再转换
throw failure.toException();
```

`PlayerException.from` 对已是 `PlayerException` 的对象直接返回，避免重复包装。

### 3.6 上下文传播

`ErrorContext` 与 `PlayerError` 共同承载 playerId/sessionId/sourceId/requestId/generationId/timestamp/metadata，`ErrorFormatter.formatContext` 将其序列化为键值对日志。`PlayerError.effectiveCategory` 优先使用显式 category，否则委托 `ErrorClassifier.classify`。

### 3.7 适配器层适配

`PlayerAdapterError` 是适配器专用的 freezed 类型，包含 `type`、`recoverable`、`requiresFallback`、`retryable` 等字段，作为后端错误进入 media_core 前的规范化入口。

## 4. 约定与约束

- **错误码命名规范**：内置码使用全大写下划线字符串（如 `NETWORK_TIMEOUT`），`name` 字段使用小驼峰（如 `networkTimeout`），由 `PlayerErrorCode.custom` 创建自定义码时会对 value/name 做 trim 并校验非空。
- **分类与策略解耦**：`PlayerErrorCategory` 和 `PlayerErrorCode` 只负责语义分类，不决定重试/回退/恢复；这些决策集中在 `ErrorPolicy`。
- **未知码安全降级**：`ErrorClassifier.fromValue`、`PlayerErrorCode.fromValue`、`PlayerErrorCategory.fromValue` 遇到未知值都返回 `unknown`，保证向后兼容。
- **可恢复性仅为提示**：`isPotentiallyRecoverable` 被多处注释明确限定为“classification hint only”，实际行为由 policy 决定。
- **重试延迟指数退避**：`ErrorPolicy.retryDelayFor` 实现 base * 2^(n-1) 的指数退避，上限 1 分钟。
- **诊断输出三档**：`format`（用户消息）、`formatLog`（含 code/category/context/cause）、`formatDebug`（含 stackTrace），由 `ErrorFormatter` 统一管理。
- **敏感信息警告**：`ErrorFormatter.formatContext` 注释明确要求调用方不要将 secret/token/cookie/authorization header 放入 `ErrorContext.metadata`。
- **适配器错误独立于核心错误模型**：`PlayerAdapterError` 使用 freezed 且自带 `retryable`/`requiresFallback` 判断，与 `PlayerErrorCode`/`PlayerFailure` 并行存在，需在上层进行桥接。
- **Dart 原生异常仅在极薄边界使用**：除 `HttpHeaderError extends ArgumentError` 外，其余领域异常（`TaskManagerDisposedException`、`StreamCancelledException`、`OperationCancelledException` 等）均为 `implements Exception` 的轻量类型，最终应被包装为 `PlayerFailure`。

## 5. 未覆盖范围

仓库中没有全局 panic/recover 机制（Flutter/Dart 无此概念），也没有中间件式的错误拦截器；错误处理通过显式的 `ErrorPolicy` 注入到播放生命周期中。UI 层的错误呈现不在本目录内，而是由示例应用或 UI 插件自行消费 `PlayerErrorEvent`/`PlayerFailure`。