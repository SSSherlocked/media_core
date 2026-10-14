---
kind: external_dependency
name: Kareki（工作区死代码扫描）
slug: kareki
category: external_dependency
category_hints:
    - framework_behavior
scope:
    - '**'
---

### Kareki
- 工作区级死代码扫描工具，新发现会失败，已基线化的条目通过 `.kareki-baseline.json` 放行；通过 melos script `kareki` 调用。