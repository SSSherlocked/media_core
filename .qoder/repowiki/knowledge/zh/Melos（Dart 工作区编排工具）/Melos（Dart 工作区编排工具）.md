---
kind: external_dependency
name: Melos（Dart 工作区编排工具）
slug: melos
category: external_dependency
category_hints:
    - framework_behavior
scope:
    - '**'
---

### Melos
- 用于在工作区级别运行 `gen`（build_runner）、`analyze`（dart analyze）、`format`（dart format）脚本，并发度限制为 1，CI 下设置 `env.CI=true`。
- 工作区包含 24 个包 + example，新增包需同时加入 `workspace:` 列表。