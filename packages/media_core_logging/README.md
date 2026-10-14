# media_core_logging

`media_core` 的分级日志模块。一条日志管线,分类开关,可插拔 sink。

## 为什么单独成包

日志是唯一一个**每个模块都要用、但不该由任何模块拥有**的能力:内核要记恢复决策,下载要记重试预算,多画面要记逐格健康度,而它们都不应该为了写一行日志去依赖彼此。把它抽成独立包之后,依赖方向只有一个:`media_core` 与各能力包 → `media_core_logging`。

同时它解决了原来的三个实际问题:

- **全局开关过粗**:以前只有"开/关",现在可以只把出问题的分类开到 `trace`,其余保持安静。
- **只有一个出口**:以前只能打到控制台。现在控制台、内存环形缓冲(给应用内日志页/复制诊断)、轮转文件(给反馈报告)可以同时挂。
- **看不出上下文**:同一个 `roomId` 要穿过会话、播放、适配器四层才能到日志里。`LogScope` 让它一次声明、层级内自动带上。

## 用法

```dart
// 1. 开启。默认什么都不打,生产环境零成本。
MediaCoreLog.level = LogLevel.warning;
MediaCoreLog.setCategoryLevel(LogCategory.pool, LogLevel.trace); // 只调高播放器池

// 2. 选出口。可以同时挂多个,控制台默认已在。
final memory = MediaCoreLog.attachMemorySink(capacity: 500);
MediaCoreLog.attachFileSink(File('${dir}/media_core.log'), maxBytes: 2 << 20, maxFiles: 3);

// 3. 打日志。模块持有绑定分类的 logger。
final _log = MediaCoreLog.of(LogCategory.playback);
_log.info('opened', fields: {'uri': uri});
if (_log.isDebugEnabled) _log.debug('per-frame detail', fields: {'position': position}); // 热路径先判断

// 4. 把上下文放进作用域,作用域内每条记录都会带上。
LogScope.run({'roomId': room.id, 'engine': 'media_kit'}, () {
  await player.open(source);
});

// 5. 出问题时收窄:只看某个分类、或只搜关键词。
MediaCoreLog.filter = LogFilter(categories: {LogCategory.fallback}, keyword: 'signed');
```

## 等级与分类

等级从低到高:`trace < debug < info < warning < error < critical`,外加 `nothing`(静音)。记录在**不低于该分类的有效最低等级**时才会产生。有效等级 = 该分类的覆盖值,否则全局值。

分类与模块一一对应,便于按子系统过滤:`player`、`playback`、`buffering`、`session`、`source`、`renderer`、`audio`、`presentation`、`recovery`、`fallback`、`cache`、`recording`、`danmaku`、`multiview`、`pool`、`download`、`visibility`、`lifecycle`、`network`、`performance`、`memory`、`logging`、`diagnostics`、`error`、`general`。

## sink

| sink | 用途 |
| --- | --- |
| `consoleLogSink()` | 默认出口,走 `dart:developer`,在 `flutter run` 与 DevTools 里都可见 |
| `MemoryLogSink` | 有界环形缓冲,供应用内日志页或"复制诊断"读取 |
| `LogFileSink` | 追加写文件,按 `maxBytes` 轮转、保留 `maxFiles` 份;带缓冲,避免逐帧同步落盘 |

自定义出口只要满足 `LogSink`(`void call(PlayerLogRecord)`),用 `MediaCoreLog.addSink` 挂上即可。`MemoryLogSink` 与 `LogFileSink` 也实现了它。

## 其余能力

- `LogFilter` —— 开发者侧收窄:限定分类、按关键词搜索(消息与字段一起搜)。
- `LogThrottle` —— 给逐帧路径限流;被丢弃的条数会附在下一条通过的记录上(`suppressed=1234`),因此"发生一次"和"发生四千次"在读日志时能区分开。
- `LogFormatter` —— 控制台与文件 sink 共用同一种单行格式,时间戳、定宽等级、补齐后的分类、字段、可选堆栈。
- `PlayerLogger.records` —— 已接受记录的广播流,给实时日志界面用。
- `MediaCoreLog.of(category)` —— `LogModule`,调用点不再重复写分类,并暴露 `isEnabled`/`isDebugEnabled` 供热路径提前判断。

## 设计约束

- **默认静默**:未配置的宿主拿不到任何输出;`nothing` 是默认等级。
- **关闭时零成本**:被丢弃的记录只付一次枚举比较,不构造字符串、不构造 map —— 所以调用点传值而不是拼接好的消息。
- **sink 抛异常不影响被记录的代码**:文件 sink 内部吞掉写盘错误,丢一行日志是正确取舍。
- **等级提升以分类为单位**:`levelResolver` 让分类覆盖真正生效,而不是先被全局等级挡掉。

## 测试

```bash
flutter test   # 37 项:等级/分类覆盖、多 sink、过滤、节流与 suppressed、作用域合并、内存/文件 sink、格式化
```
