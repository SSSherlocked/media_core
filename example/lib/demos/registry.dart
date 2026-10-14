import 'package:example/demos/console/background_execution_demo.dart';
import 'package:example/demos/console/cache_demo.dart';
import 'package:example/demos/console/download_demo.dart';
import 'package:example/demos/console/fault_demo.dart';
import 'package:example/demos/console/list_playback_demo.dart';
import 'package:example/demos/console/logging_demo.dart';
import 'package:example/demos/console/lyric_demo.dart';
import 'package:example/demos/console/memory_demo.dart';
import 'package:example/demos/console/platform_demo.dart';
import 'package:example/demos/console/pool_demo.dart';
import 'package:example/demos/console/probe_demo.dart';
import 'package:example/demos/console/queue_demo.dart';
import 'package:example/demos/console/recording_demo.dart';
import 'package:example/demos/console/source_demo.dart';
import 'package:example/demos/console/task_demo.dart';
import 'package:example/demos/module_demo.dart';
import 'package:example/demos/runnable_demo.dart';
import 'package:example/pages/feed_demo_page.dart';
import 'package:example/pages/live_demo_page.dart';
import 'package:example/pages/media_session_demo_page.dart';
import 'package:example/pages/memory_demo_page.dart';
import 'package:example/pages/multiview_demo_page.dart';
import 'package:example/pages/music_demo_page.dart';
import 'package:example/pages/player_demo_page.dart';
import 'package:example/pages/presentation_demo_page.dart';
import 'package:example/pages/ui_styles_demo_page.dart';

/// Pages a developer interacts with.
///
/// Most create a real player, so the framework's behaviour (backend selection,
/// recovery, watchdogs, lyrics timing) is observable instead of described. Two
/// of them — the memory dashboard and the multiview wall — deliberately do not:
/// they drive fake players, which is what makes the pool's and the wall's logic
/// runnable with no backend, no network and no device.
final List<RunnableDemo> runnableDemos = <RunnableDemo>[
  RunnableDemo(
    id: 'player',
    nameZh: '播放器与生命周期',
    nameEn: 'PlayerIdentity & lifecycle',
    purposeZh: 'kernel → 注册后端 → create → open → play；含 seek / 音量 / 倍速 / 静音 / 循环与操作记录。',
    purposeEn:
        'kernel → register backend → create → open → play; with seek, volume, rate, mute, loop and operation records.',
    builder: (_) => const PlayerDemoPage(),
  ),
  RunnableDemo(
    id: 'ui-styles',
    nameZh: '界面风格：六套设计语言',
    nameEn: 'UI styles: six design languages',
    purposeZh:
        'material / cupertino / fluent / macos / yaru / neumorphic 共用一层控制逻辑，播放中切换风格不重置状态、进度与显隐策略；同页演示双指缩放、双击缩放与截图落盘。',
    purposeEn: 'material / cupertino / fluent / macos / yaru / neumorphic share one control layer, so switching mid-playback keeps state, position and visibility policy; the same page shows pinch/double-tap zoom and a saved screenshot.',
    builder: (_) => const UiStylesDemoPage(),
  ),
  RunnableDemo(
    id: 'media-session',
    nameZh: '系统媒体面：通知 / 锁屏 / SMTC',
    nameEn: 'System media surfaces: notification, lock screen, SMTC',
    purposeZh: '视频播放器接入系统媒体控件（Android 通知、iOS 锁屏、Windows SMTC、Linux MPRIS）：标题、进度、播放暂停、±10 秒、停止；按通知上的按钮会走回同一个 handle，日志里能看到状态变化。',
    purposeEn: 'A video player published to the platform surfaces (Android notification, iOS lock screen, Windows SMTC, Linux MPRIS) with title, progress, play/pause, ±10s and stop; pressing them drives the same handle, and the log shows it.',
    builder: (_) => const MediaSessionDemoPage(),
  ),
  RunnableDemo(
    id: 'live',
    nameZh: '直播多线路与引擎回退',
    nameEn: 'Live lines & engine fallback',
    purposeZh: '多线路请求：同引擎换线 → 换引擎重扫 → 都失败才 onError，一次。',
    purposeEn: 'Multi-line request: lines on one engine → next engine → a single onError when everything is spent.',
    builder: (_) => const LiveDemoPage(),
  ),
  RunnableDemo(
    id: 'feed',
    nameZh: '短视频上下滑',
    nameEn: 'Vertical feed',
    purposeZh: '共用一个播放器换源，只有当前页挂载视频控件，下一条自动预热。',
    purposeEn: 'One shared player re-opened per item; only the visible page mounts a video widget; the next item is preloaded.',
    builder: (_) => const FeedDemoPage(),
  ),
  RunnableDemo(
    id: 'music',
    nameZh: '音乐：队列 / 歌词 / 桌面歌词 / 后台 / 下载',
    nameEn: 'Music: queue, lyrics, overlay, background, download',
    purposeZh: 'media_core_audio 的全部面：音源解析、四种播放模式、歌词时间轴、桌面歌词窗口、后台播放绑定、ffmpeg 下载。',
    purposeEn: 'The whole media_core_audio surface: source resolution, four play modes, lyric timeline, desktop lyric window, background binding, ffmpeg downloads.',
    builder: (_) => const MusicDemoPage(),
  ),
  RunnableDemo(
    id: 'memory',
    nameZh: '内存监控仪表盘',
    nameEn: 'Memory dashboard',
    purposeZh: '实时报告视图：预算滑杆、按模块上报/释放、压力等级与峰值、设备实测值开关。全部离线，不需要播放器。',
    purposeEn: 'A live report view: budget slider, per-module report/release, pressure level and peaks, plus a device-provider switch. Fully offline, no player needed.',
    builder: (_) => const MemoryDemoPage(),
  ),
  RunnableDemo(
    id: 'multiview',
    nameZh: '多画面视频墙',
    nameEn: 'Multiview wall',
    purposeZh: '2×2 / 3×3 网格、焦点与唯一音频归属、解码预算降级、冻格触发看门狗重启、巡更轮巡、逐格弹幕；播放器是假的，墙的逻辑是真的。',
    purposeEn: 'A 2x2 / 3x3 grid with focus, one audible cell, budget degradation, a freezing cell that triggers the watchdog, patrol and per-cell danmaku. Fake players; real wall.',
    builder: (_) => const MultiviewDemoPage(),
  ),
  RunnableDemo(
    id: 'presentation',
    nameZh: '全屏 / 画中画 / 悬浮窗 / 弹幕',
    nameEn: 'Fullscreen, PiP, floating & danmaku',
    purposeZh: 'kernel.attachPresentation 转发展示请求；弹幕会话由假 transport 喂消息。',
    purposeEn: 'kernel.attachPresentation forwards presentation requests; the danmaku session is fed by a synthetic transport.',
    builder: (_) => const PresentationDemoPage(),
  ),
];

/// Pure-logic modules, demonstrated by running them.
///
/// A printed result is the right medium for these: no device, no network, and
/// the output *is* the evidence — a lyric table, a queue walk, the exact ffmpeg
/// argument list.
final List<ModuleDemo> moduleDemos = <ModuleDemo>[
  // Foundation: the shared infrastructure every other module reports through.
  const MemoryDemo(),
  const LoggingDemo(),
  const CacheDemo(),
  // Control and the playback chain.
  const TaskDemo(),
  const PoolDemo(),
  const ListPlaybackDemo(),
  // Failure handling.
  const FaultDemo(),
  // Capabilities.
  const DownloadDemo(),
  const RecordingDemo(),
  const BackgroundExecutionDemo(),
  // Domain demos that predate the split.
  const LyricDemo(),
  const QueueDemo(),
  const SourceDemo(),
  const PlatformDemo(),
  // What the platform itself says about this device.
  const ProbeDemo(),
];

/// Everything the catalog shows: runnable pages first, module tour second.
final Map<ModuleCategory, List<ModuleDemo>> moduleDemosByCategory = <ModuleCategory, List<ModuleDemo>>{
  for (final category in ModuleCategory.values)
    category: moduleDemos.where((demo) => demo.category == category).toList(growable: false),
};

/// Whether a category has any demo.
bool hasModuleDemos(ModuleCategory category) => (moduleDemosByCategory[category] ?? const <ModuleDemo>[]).isNotEmpty;
