---
kind: external_dependency
name: very_good_analysis（共享 lint 规则集）
slug: very-good-analysis
category: external_dependency
category_hints:
    - framework_behavior
scope:
    - '**'
---

### very_good_analysis
- 根 `analysis_options.yaml` 直接 include `package:very_good_analysis/analysis_options.yaml`，并通过 `public_member_api_docs: true` 强制要求公共成员必须有 API 文档注释，且配置注释明确"不得削弱共享规则，例外需在 docs/decisions/ 记录"。
- 格式化宽度设为 120 列，`lines_longer_than_80_chars` 被显式关闭。
- 生成文件（`.freezed.dart`、`.g.dart`）与 `build/` 目录被排除分析。