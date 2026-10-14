---
kind: build_system
name: Flutter/Dart 多包工作区构建与质量门禁
category: build_system
scope:
    - '**'
source_files:
    - pubspec.yaml
    - analysis_options.yaml
    - tool/validate_packages.dart
    - .pubcheck/media_core.log
    - example/pubspec.yaml
---

## 1. 使用的系统与工具

- **Dart 3 workspace**：根 `pubspec.yaml` 通过 `workspace:` 字段声明所有子包，作为单一解析作用域（resolution scope），不再依赖 melos 的 workspace 能力。
- **melos ^8.9.0**：仅用于编排脚本（`melos scripts`），在 `pubspec.yaml` 的 `melos:` 块中定义 `gen`、`analyze`、`format`、`kareki` 四个命令，统一在工作区内执行。
- **build_runner**：由 `melos gen` 触发，对所有依赖 `build_runner` 的包运行 `dart run build_runner build --delete-conflicting-outputs`（并发=1，CI=true）。
- **very_good_analysis ^11.0.0**：根 `analysis_options.yaml` 继承该规则集，并覆盖 `formatter.page_width: 120`、关闭 `lines_longer_than_80_chars`、开启 `public_member_api_docs`。
- **kareki ^0.7.0**：工作区级死代码扫描，通过 `melos kareki` 调用 `dart run kareki --baseline .kareki-baseline.json`，新发现即失败。
- **自定义校验器**：`tool/validate_packages.dart` 是一个独立的 Dart CLI，不依赖 melos，直接检查仓库结构约束。

没有 Makefile、Dockerfile、CI pipeline 或发布脚本；跨平台编译完全交给 Flutter 自身的 Android/iOS/Linux/macOS/Windows/Web 后端。

## 2. 关键文件

- `pubspec.yaml`：workspace 声明、melos 脚本、`dependency_overrides`（`wakelock_plus`、`code_assets`、`hooks`）解决 media_kit / ffmpeg_kit 之间的版本冲突。
- `analysis_options.yaml`：统一的 lint/format 配置入口。
- `tool/validate_packages.dart`：包边界与导入边界的强制校验器。
- `.pubcheck/*.log`：每个包的 pub.dev 兼容性检查结果日志（由外部工具生成）。
- `example/pubspec.yaml` + `example/android`, `example/ios`, `example/linux`, `example/macos`, `example/windows`, `example/web`：示例应用及其各平台原生工程，作为端到端验证目标。

## 3. 架构与约定

### 3.1 工作区成员模型
根 `pubspec.yaml` 的 `workspace:` 列表是唯一的成员清单，包含 26 个 `packages/media_core_*` 包和 `example`。校验器 `tool/validate_packages.dart` 会对比磁盘上 `packages/` 下的目录与该列表，任何遗漏都会报错（§6.1）。

### 3.2 包契约（由 validate_packages.dart 强制执行）
- 根必须是 resolution scope，不能发布：要求 `publish_to: none`。
- 每个包必须声明 `resolution: workspace`。
- 包目录名必须等于 `name:`（app 除外，如 `media_core_native/example` → `media_core_native_example`）。
- 非 app 包必须拥有 `README.md`、`CHANGELOG.md`、`analysis_options.yaml`、`lib/<name>.dart`、`test/`。
- 禁止 import 其他包的 `lib/src`（私有实现），只允许 `package:media_core_xxx/` 公开 API。
- 内部依赖必须在 `dependencies:` 中显式声明，否则视为未声明导入。
- 不允许依赖环：基于 `dependencies:` 图做 DFS 检测，报告路径。
- 使用 `git:` 依赖的包必须加入白名单 `_gitDependencyExceptions = {'media_core_ijk_player', 'media_core_media_kit'}` 且声明 `publish_to: none`。

### 3.3 版本与依赖管理
- 根 `version: 1.0.0`，但 `publish_to: none`，实际发布由各子包独立管理。
- 通过 `dependency_overrides` 在 workspace 层统一提升 `wakelock_plus`、`code_assets`、`hooks` 的版本以调和 media_kit 与 better_player 之间的冲突。
- 每个子包有自己的 `pubspec.yaml`，按功能拆分（audio、ijk_player、media_kit、ui、live、feed、download、recording_ffmpeg 等）。

### 3.4 代码生成与分析流水线
```bash
# 生成代码（build_runner）
melos gen
# 静态分析
dart analyze   # 或通过 melos analyze
# 格式化
dart format .  # 或通过 melos format
# 死代码扫描
dart run kareki --baseline .kareki-baseline.json
# 包结构校验
dart tool/validate_packages.dart
```

## 4. 约定与约束

- **Workspace 唯一入口**：所有包必须出现在根 `pubspec.yaml` 的 `workspace:` 列表中，否则不会被解析、分析和测试（由 `tool/validate_packages.dart` 第 95–106 行强制）。
- **每个包必须声明 `resolution: workspace`**（校验器第 110–115 行）。
- **包命名与目录同名**（app 例外）（第 131–134 行）。
- **公共入口为 `lib/<name>.dart`**，非 app 包必须有 `test/`（第 140–148 行）。
- **禁止访问其他包的 `lib/src`**，只允许通过 `package:media_core_xxx/` 导入（第 171–188 行）。
- **内部依赖必须显式声明**，否则会报“imports without declaring them as dependencies”（第 162–168 行）。
- **禁止循环依赖**，校验器输出形如 `dependency cycle: A -> B -> A`（第 190–226 行）。
- **git 依赖白名单制**，仅 `media_core_ijk_player` 与 `media_core_media_kit` 被允许，且必须 `publish_to: none`（第 18–21、151–159 行）。
- **lint 规则来自 very_good_analysis**，page width 120，`public_member_api_docs` 强制开启（`analysis_options.yaml`）。
- **build_runner 生成文件被排除在分析之外**（`**/*.freezed.dart`、`**/*.g.dart`、`build/**`）。
- **kareki 基线文件 `.kareki-baseline.json` 存在时，只有新增的死代码才会导致失败**（melos script 描述）。
- **无 CI/CD 配置文件**：仓库中没有 `.github/workflows`、`.gitlab-ci.yml`、`Makefile`、`Dockerfile` 等持续集成或容器化脚本。
- **跨平台构建委托给 Flutter**：`example/` 下保留完整的 Android Gradle、iOS Xcode、Linux/macOS CMake、Windows CMake、Web 工程，作为各平台验证入口。