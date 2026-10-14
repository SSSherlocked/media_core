---
kind: external_dependency
name: better_player_plus（轻量纯 Flutter 后端）
slug: better-player-plus
category: external_dependency
category_hints:
    - vendor_identity
scope:
    - '**'
---

### better_player_plus
- 通过 `BetterPlayerAdapterFactory` 注册为可选后端，定位轻量、纯 Flutter 生态路径，与 media_kit/ijk/fvp 并列。
- 与 media_kit 在 `wakelock_plus`、`code_assets`、`hooks` 等依赖上存在版本冲突，需通过根 `dependency_overrides` 统一解析。