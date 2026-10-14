---
kind: dependency_management
name: 基于 Dart workspace + melos 的多包依赖管理
category: dependency_management
scope:
    - '**'
source_files:
    - pubspec.yaml
    - pubspec.lock
    - tool/validate_packages.dart
    - packages/media_core/pubspec.yaml
    - packages/media_core_ijk_player/pubspec.yaml
    - packages/media_core_media_kit/pubspec.yaml
    - example/pubspec.yaml
---

## 1. 使用的系统与工具

仓库是一个 Flutter/Dart 多包工作区，采用以下组合进行依赖管理：

- **Dart 原生 workspace**（`pubspec.yaml` 中的 `workspace:` 字段），而非传统的 Melos-only 模式。根 `pubspec.yaml` 显式列出 28 个包路径，所有子包的 `pubspec.yaml` 均声明 `resolution: workspace`，使同一工作区内对内部包的引用走本地解析。
- **melos**（`dev_dependencies: melos: ^8.9.0`）作为工作区脚本编排器，在根 `pubspec.yaml` 的 `melos.scripts` 中定义 `gen`、`analyze`、`format`、`kareki` 等命令，通过 `packageFilters.dependsOn` 筛选目标包执行。
- **very_good_analysis**（`^11.0.0`）作为统一的 lint 规则集，由根 `analysis_options.yaml` 引入。
- **kareki**（`^0.7.0`）用于工作区范围的死代码扫描，配合 `.kareki-baseline.json` 基线文件。
- **自定义校验脚本** `tool/validate_packages.dart`，以退出码 1/2 报告违规，是 CI 可集成的硬性检查入口。

没有发现私有 registry、`pubspec_overrides.yaml`、`packages/flutter_tools` 或 vendored 第三方源码目录；第三方依赖统一从 pub.dev 解析，仅极少数包使用 `git:` 引用。

## 2. 关键文件

| 文件 | 作用 |
|---|---|
| `pubspec.yaml` | 工作区根，声明 `workspace:` 列表、`dependency_overrides`、melos 脚本 |
| `pubspec.lock` | 工作区级锁定文件（已提交），记录所有包与第三方依赖的精确版本 |
| `packages/*/pubspec.yaml` | 各模块的依赖声明，统一带 `resolution: workspace` |
| `tool/validate_packages.dart` | 强制约束工作区结构、依赖边界、循环、git 依赖白名单 |
| `example/pubspec.yaml` | 示例应用，聚合全部 media_core 能力模块 |
| `.pubcheck/*.log` | 每个包独立的依赖检查日志输出目录 |

## 3. 架构与约定

### 3.1 工作区与内部依赖

根 `pubspec.yaml` 的 `workspace:` 块集中声明所有成员包，新增包必须同时添加到该列表，否则 `validate_packages.dart` 会报 `§6.1` 违规（"has a pubspec.yaml but is not in the root workspace list"）。所有子包统一添加 `resolution: workspace`，确保内部依赖在工作区内解析而非去 pub.dev 拉取。

内部包之间通过 `dependencies:` 直接声明彼此名称（如 `media_core_audio` 依赖 `media_core`、`media_core_logging`），而不是通过相对路径引用。

### 3.2 版本策略

- 工作区 SDK 约束为 `sdk: ">=3.9.0 <4.0.0"`，Flutter 约束为 `flutter: ">=3.35.0"`，所有子包沿用相同范围。
- 内部包之间使用语义化版本范围（如 `media_core: ^0.1.0`），不固定到具体 patch。
- 外部依赖普遍使用 `^x.y.z` 宽松范围，由 `pubspec.lock` 锁定实际解析结果。
- 根 `pubspec.yaml` 使用 `dependency_overrides` 解决后端冲突：将 `wakelock_plus`、`code_assets`、`hooks` 提升到兼容两个后端的最小公共版本，注释明确说明这是为让 `media_kit_video` 与 `better_player_plus` 在同一工作区共存。

### 3.3 git 依赖白名单

`tool/validate_packages.dart` 维护一个硬编码白名单：

```dart
const Set<String> _gitDependencyExceptions = <String>{'media_core_ijk_player', 'media_core_media_kit'};
```

只有这两个包允许携带 `git:` 依赖。当前仓库中：
- `media_core_ijk_player` 依赖 `flv_lzc`（指向 `liuchuancong/flv_lzc.git` 的特定 commit `162030d...`）。
- `media_core_media_kit` 依赖 `Predidit/media-kit.git` 的 `media_kit` 与 `media_kit_video` 子路径，同样 pin 到 commit `803c4a2...`。

这些包都声明 `publish_to: none`，因为 pub.dev 不允许发布含 `git:` 依赖的包。

### 3.4 依赖边界与循环检测

`validate_packages.dart` 强制执行以下规则（对应文档 `docs/engineering/package-standards.md`）：

- **§6.1**：工作区根必须 `publish_to: none`；`packages/` 下每个有 `pubspec.yaml` 的目录必须出现在根 `workspace:` 列表中。
- **§6.2**：每个包必须声明 `resolution: workspace`。
- **§6.3**：导入内部包必须在 `dependencies:` 中声明，否则会报 "imports X without declaring them as dependencies"。
- **§7.1 rule 6**：禁止内部依赖环——脚本构建依赖图并做 DFS 检测，报告形如 `A -> B -> A` 的环。
- **§7.1 rule 7**：禁止跨包 import 其他包的 `lib/src/` 私有目录，只允许通过公开 API 访问。
- **§17**：非白名单包不得出现 `git:` 依赖。

### 3.5 包元数据规范

脚本还要求每个包（除 app）具备：`README.md`、`CHANGELOG.md`、`analysis_options.yaml`、`lib/<name>.dart` 入口、`test/` 目录。包名必须与目录名一致（app 例外）。

## 4. 约定与约束总结

- **约定（描述性）**：
  - 所有内部依赖通过 `dependencies:` 按包名引用，并使用 `^0.1.0` 这类语义化范围。
  - 所有子包统一声明 `resolution: workspace`。
  - 第三方依赖使用 `^x.y.z` 宽松范围，实际版本由 `pubspec.lock` 锁定。
  - 需要 fork 上游依赖时，使用 `git:` + 固定 `ref` commit，并在注释中说明原因。
  - 示例应用 `example/` 聚合全部功能模块作为演示入口。

- **约束（被 enforce）**：
  - 新增包必须加入根 `pubspec.yaml` 的 `workspace:` 列表（由 `tool/validate_packages.dart` 在 §6.1 检查）。
  - 每个包必须声明 `resolution: workspace`（§6.2）。
  - 内部依赖必须在 `dependencies:` 中显式声明（§6.3）。
  - 禁止跨包 import `lib/src/` 私有实现（§7.1 rule 7）。
  - 禁止内部依赖环（§7.1 rule 6）。
  - 仅 `media_core_ijk_player` 与 `media_core_media_kit` 可使用 `git:` 依赖，且必须 `publish_to: none`（§17）。
  - 根 `pubspec.yaml` 必须 `publish_to: none`（§6.1）。
  - 每个包必须具备 `README.md`、`CHANGELOG.md`、`analysis_options.yaml`、`lib/<name>.dart`、`test/`（§5、§8.2、§12）。

- **工具链**：`dart tool/validate_packages.dart` 是单一入口，成功返回 0，任何违规返回 1，无法读取工作区返回 2，便于接入 CI。

- **未发现的机制**：仓库中没有私有 registry 配置、`pubspec_overrides.yaml`、vendored 第三方源码或自动升级依赖的脚本；`.pubcheck/*.log` 目录存在但为空，尚未集成自动化依赖审计流程。