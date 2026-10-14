---
kind: configuration_system
name: 基于不可变 Config 对象的运行时配置体系
category: configuration_system
scope:
    - '**'
source_files:
    - pubspec.yaml
    - packages/media_core/lib/core/player_config.dart
    - packages/media_core/lib/factory/player_factory_config.dart
    - packages/media_core/lib/adapter/player_adapter_config.dart
    - packages/media_core/lib/pool/player_pool_config.dart
    - packages/media_core/lib/bug/bug_mode_config.dart
    - packages/media_core/lib/bug/bug_mode_controller.dart
    - packages/media_core/lib/diagnostics/diagnostics_config.dart
    - packages/media_core/lib/recording/recording_config.dart
    - packages/media_core/lib/renderer/renderer_config.dart
    - packages/media_core/lib/screenshot/screenshot_config.dart
---

## 1. 总体方案

仓库没有使用外部配置框架（如 `flutter_config`、`envied`、`.yaml`/`.env` 文件加载器）。整个 media_core 的“配置系统”是**纯 Dart 代码内定义的不可变值对象 + 可选的 Controller 包装器**，通过构造函数参数从调用方注入。配置与运行态严格分离：配置类只描述“如何创建/初始化”，不持有 session、adapter、operation 等运行时引用。

工作区层面的构建/依赖配置集中在根 `pubspec.yaml`（`workspace:` 列表、`melos` scripts、`dependency_overrides`），属于包管理配置而非应用运行时配置。

## 2. 核心文件与包

- `packages/media_core/lib/core/player_config.dart` — 播放器主配置 `PlayerConfig`
- `packages/media_core/lib/factory/player_factory_config.dart` — 工厂创建期配置 `PlayerFactoryConfig`
- `packages/media_core/lib/adapter/player_adapter_config.dart` — 后端适配器配置 `PlayerAdapterConfig`
- `packages/media_core/lib/pool/player_pool_config.dart` — 播放器池配置 `PlayerPoolConfig`
- `packages/media_core/lib/bug/bug_mode_config.dart` + `bug_mode_controller.dart` — 故障注入模式配置及可变控制器
- `packages/media_core/lib/diagnostics/diagnostics_config.dart`、`recording/recording_config.dart`、`renderer/renderer_config.dart`、`screenshot/screenshot_config.dart`、`pool/player_pool_config.dart` 等模块各自携带自己的 `*Config` 类型
- 根 `pubspec.yaml` — melos workspace、`dependency_overrides`、scripts

## 3. 架构与约定

### 3.1 配置分层（按生命周期）

| 阶段 | 配置类型 | 职责 |
|---|---|---|
| 工厂创建 | `PlayerFactoryConfig` | preferredBackend / platform / autoInitialize / enableDiagnostics / enableHardwareDecode / enableFallback / policy |
| 播放器实例 | `PlayerConfig` | name / mediaType / sourceId / autoPlay / loop / muted / volume / playbackRate / preload / keepAlive / enableAudio/Video/Subtitles/Buffering/Recovery/Fallback/Metrics/Diagnostics / maxRecoveryAttempts / maxFallbackAttempts |
| 后端适配 | `PlayerAdapterConfig` | hardwareAcceleration / audioEnabled / volume / playbackRate / networkTimeout / bufferDuration / maxBufferBytes / preferredDecoder / options |
| 资源池 | `PlayerPoolConfig` | maxPlayers / initialSize / lazyCreate / enableRecycle / idleTimeout / keepWarm / warmSize / maxActivePlayers / preloadCount / visibilityThresholds / reuseIdlePlayers |
| 调试/故障 | `BugModeConfig` + `FaultConfig` | mode / enabled / allow*Faults / maxConcurrentFaults / maxScheduledFaults |

每层配置独立，上层组合下层；例如 `PlayerFactoryConfig` 持有 `PlayerPolicy`，而 `PlayerConfig` 明确不包含 adapter/session/lifecycle 引用。

### 3.2 不可变性与派生

- 简单配置类（`PlayerConfig`、`BugModeConfig`、`FaultConfig`、`PlayerFactoryConfig`、`RecordingConfig`、`RendererConfig`、`ScreenshotConfig`、`DiagnosticsConfig`、`MusicDownloadConfig`、`AudioPlaybackConfig`）统一实现 `Equatable`，提供 `copyWith` 以及大量语义化 `withXxx` / `asXxx` 方法（如 `withVolume`、`withAutoPlay`、`asAudioOnly`、`asSafe`、`asChaos` 等）。
- 字段较多的配置类（`PlayerAdapterConfig`、`PlayerPoolConfig`）改用 `freezed_annotation` + `@freezed` 生成 `copyWith` 与相等性比较，并通过 `part 'xxx.freezed.dart'` 引入。
- 所有配置类都提供 `toString()` 输出完整字段，便于诊断日志。

### 3.3 默认值与预设

- `PlayerConfig` 暴露 `defaults`、`minimal`、`audioOnly`、`videoOnly`、`audioVideo` 五个静态常量预设。
- `PlayerAdapterConfig.defaults()` 返回默认构造实例。
- `BugModeConfig.disabled` / `safe` / `normal` / `aggressive` / `chaos` 五个预置模式，对应不同级别的 fault 注入强度。

### 3.4 验证策略

- 构造时断言：`PlayerConfig` 在构造函数中对 `volume`、`playbackRate`、`maxRecoveryAttempts`、`maxFallbackAttempts` 执行 `assert(...)` 校验。
- 运行时验证：`BugModeConfig.validate()` 收集错误列表，`validateOrThrow()` 抛出 `StateError`；`PlayerAdapterConfigExtension.isValid` 检查 volume/rate/timeout/buffer 范围。
- 控制器强制校验：`BugModeController.setConfig` 在替换配置前调用 `value.validateOrThrow()`，并在 `_ensureNotDisposed()` 中防止已 dispose 的对象被修改。

### 3.5 可变运行时配置（仅 Bug Mode）

`BugModeController` 是唯一一个持有可变状态并广播配置的组件：内部用 `StreamController<BugModeConfig>.broadcast()` 暴露 `onConfigChanged`，所有 setter（`setConfig` / `enable` / `disable` / `setMode` / `setSafeMode` / `update` 等）都会先校验再发射新配置。其他配置类本身不可变，不存在全局单例配置中心。

### 3.6 平台/后端选项透传

`PlayerAdapterConfig.options` 为 `Map<String, Object?>`，用于向后端传递具体实现相关的键值对（如 `preferredDecoder: 'h264'`），由各个 backend adapter（media_kit、better_player、ijk_player、fvp 等）自行解析。

## 4. 约定与约束

- **配置即数据**：每个 `*Config` 类都是不可变的数据载体，不持有运行时句柄；文档注释明确声明其职责边界（“It does not: create player / select backend / manage lifecycle”）。
- **不可变派生**：新增字段必须同时更新 `copyWith`、`props`（Equatable）、`toString`；freezed 生成的类除外。
- **默认值集中**：常用常量（如 `PlayerConstants.defaultVolume`、`defaultPlaybackRate`、`maxRecoveryAttempts`）从 `player_constants.dart` 读取，避免魔法数字散落。
- **验证入口统一**：可抛错验证走 `validateOrThrow()`，非抛错验证走 `validate()` 返回 `List<String>`；`PlayerAdapterConfig` 使用 getter `isValid` 作为轻量校验。
- **无外部配置文件**：仓库未发现 `.yaml`/`.toml`/`.env` 形式的运行时配置加载逻辑；所有配置通过 Dart 构造参数或 `const` 预设注入。
- **Workspace 级构建配置**：根 `pubspec.yaml` 中的 `workspace:`、`melos.scripts`、`dependency_overrides` 是工作区统一的构建/依赖版本锁定方式，不是应用运行时配置。
- **示例应用直接构造**：example 中的 demo 直接使用 `const DownloadConfig(...)`、`config: const ...` 等字面量构造配置，没有中间配置加载层。