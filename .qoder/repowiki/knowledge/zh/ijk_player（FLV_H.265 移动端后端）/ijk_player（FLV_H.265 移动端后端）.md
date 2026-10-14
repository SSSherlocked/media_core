---
kind: external_dependency
name: ijk_player（FLV/H.265 移动端后端）
slug: ijk-player
category: external_dependency
category_hints:
    - vendor_identity
scope:
    - '**'
---

### ijk_player (flv_lzc)
- 通过 `IjkPlayerAdapterFactory` 注册为可选后端，面向 FLV / H.265 移动端场景，与 media_kit、better_player、fvp 并列由 `PlayerAdapterSelector` 按协议/格式/直播能力打分选择。