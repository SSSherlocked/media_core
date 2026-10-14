---
kind: external_dependency
name: media_kit（默认后端播放器引擎）
slug: media-kit
category: external_dependency
category_hints:
    - client_constraint
scope:
    - '**'
---

### media_kit
- 作为默认首选后端通过 `MediaKitAdapterFactory` 注册到 `PlayerKernel`；协议/格式覆盖最广，自带按设备能力选择硬解或软解的解码策略。
- 仓库不随本仓库分发：按 `packages/media_core_media_kit` 内固定的 ref 从 `Predidit/media-kit` 拉取，因此不得依赖上游 PureLive 分支上的补丁（如 `setVideoOutputEnabled`、Windows 的 `frameRevision`）。
- 与 `better_player_plus` 在 `wakelock_plus` / `code_assets` / `hooks` 上存在版本冲突，需通过根 `dependency_overrides` 强制统一（见 pubspec.yaml）。