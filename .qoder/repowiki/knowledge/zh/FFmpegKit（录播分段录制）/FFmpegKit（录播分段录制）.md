---
kind: external_dependency
name: FFmpegKit（录播分段录制）
slug: ffmpeg-kit
category: external_dependency
category_hints:
    - vendor_identity
scope:
    - '**'
---

### FFmpegKit
- `media_core_recording_ffmpeg` 使用 FFmpegKit 进行分段 MPEG-TS 录制并输出 CSV 日志，失败只丢几秒而非整场；进程默认继承后台保活会话以支持熄屏继续录制。