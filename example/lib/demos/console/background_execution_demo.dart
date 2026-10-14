import 'dart:async';

import 'package:example/demos/module_demo.dart';
import 'package:media_core_native/media_core_native.dart';

/// Holding a background-execution session, and what its notification can say.
///
/// The demo acquires two sessions, moves a progress bar, releases them one at a
/// time, and prints every step — so on Android the notification shade and the
/// output tell the same story: one notification, owned by the newest job, with a
/// `+1` for the other, and a bar that fills while the download runs.
class BackgroundExecutionDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'background-execution';

  @override
  ModuleCategory get category => ModuleCategory.capability;

  @override
  String get nameZh => '后台保活（通知 / 唤醒锁 / 进度）';

  @override
  String get nameEn => 'Background keep-alive (notification, wake lock, progress)';

  @override
  String get purposeZh =>
      '录制和下载是"用户要了就不再盯着"的任务：屏幕一关，系统几秒内就冻结或杀掉进程，任务只留下一个说不清原因的退出码。会话对象把"谁负责收回这份保护"变成一次 release，同时它就是通知的句柄 —— 标题、正文、图标、进度都由宿主给，跑起来以后还能随时 update。Android 上是一条前台服务通知加一把部分唤醒锁，iOS/macOS/Windows 是"别睡"的断言（没有通知可设），Linux 还没有实现（如实返回 null）。';

  @override
  String get purposeEn =>
      'Recording and downloading are jobs the user asked for and then stopped watching: without a session the platform freezes or kills the process seconds after the screen goes off, leaving nothing but an exit code that explains nothing. A session object makes "who releases this protection" one release call, and it doubles as the handle on the notification: title, text, icon and progress all come from the host and can be replaced while the job runs. On Android that is a foreground-service notification plus a partial wake lock; on iOS/macOS/Windows it is a sleep assertion with no notification to describe; on Linux there is nothing yet (null, honestly reported).';

  @override
  List<String> get pointsZh => const <String>[
    'BackgroundNotification 描述通知：title / text / kind（决定内置图标）/ icon（宿主自己的 drawable 名）/ progress',
    'BackgroundProgress 有"已知总量"和"未知总量"两种形状，直播录制没有总量，就不该画一根假装有意义的进度条',
    'session.update(description.copyWith(...)) 是长任务刷新的方式：录制每秒推一次已录时长与字节数',
    '两个任务共享一条通知：最新启动的那个拥有它（正文标 +1），先释放一个不会拆掉另一个的保护',
    'Android 13+ 的通知权限由这个包自己在有 Activity 时弹出；拒绝也照跑 —— 唤醒锁还在，只是看不到通知',
    'iOS 拿到的是"转场窗口"（约 30 秒），不是无限时间；长时间录制要应用自己声明 audio 后台模式',
    '按钮 / 通知渠道名不在可配范围：前者要一条回调进 Dart 的通道，后者是整库一个，好让用户一次静音掉所有后台任务',
  ];

  @override
  List<String> get pointsEn => const <String>[
    "BackgroundNotification describes the notification: title / text / kind (picks the built-in glyph) / icon (a drawable of the host's own) / progress",
    'BackgroundProgress has two shapes — a known total and an unknown one — because a live recording has no total and a bar pretending otherwise would mean nothing',
    'session.update(description.copyWith(...)) is how a long job refreshes it: a recording pushes elapsed time and bytes written once a second',
    "Two jobs share one notification: the one started last owns it (the text carries +1), and releasing one does not take the other's protection apart",
    'On Android 13+ this package asks for the notification permission itself while an activity is attached; a refusal still runs the job — the wake lock holds, only the notification stays hidden',
    "On iOS the assertion buys the transition window (about 30 seconds), not unlimited time; a long recording needs the app's own audio background mode",
    'Buttons and the channel name are deliberately not configurable: the first needs a callback path into Dart, the second is one per library so a user can silence all background work at once',
  ];

  @override
  String get snippet => '''
final session = await BackgroundExecution.acquire(
  notification: const BackgroundNotification(
    title: '正在录制',
    text: 'room-42',
    kind: BackgroundJobKind.record,
    icon: 'ic_stat_record',                            // 宿主 res/drawable 里的名字
    progress: BackgroundProgress.indeterminate(),      // 直播录制没有总量
  ),
);

// 跑起来以后还能改：
await session?.update(
  BackgroundNotification(
    title: '正在下载',
    text: 'demo.flv · 42%',
    kind: BackgroundJobKind.download,
    progress: const BackgroundProgress.determinate(current: 42, total: 100),
  ),
);

// ... and when the job ends:
await session?.release();   // 通知随会话消失
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer()..writeln('BackgroundExecution.isSupported: ${BackgroundExecution.isSupported}');

    if (!BackgroundExecution.isSupported) {
      buffer
        ..writeln('这个平台没有实现：任务照跑，只是没有保护（不是失败）。')
        ..writeln('No implementation here: the job still runs, just unprotected (not a failure).');
      return buffer.toString();
    }

    buffer.writeln('— 取录制会话（未知总量：转圈 + 已录时长）/ recording session (indeterminate) —');

    final recording = await BackgroundExecution.acquire(
      notification: const BackgroundNotification(
        title: '演示：保存直播',
        text: 'demo_recording',
        kind: BackgroundJobKind.record,
        progress: BackgroundProgress.indeterminate(),
      ),
    );

    buffer.writeln('acquire -> $recording');

    if (recording == null) {
      buffer
        ..writeln('平台拒绝了前台服务：任务仍会继续，只是屏幕一关就可能被冻结。')
        ..writeln(
          'The platform refused the foreground service: the job continues, but may be frozen once the screen goes off.',
        );
      return buffer.toString();
    }

    try {
      buffer
        ..writeln()
        ..writeln('通知栏现在应该有一条常驻通知（Android），正文是 demo_recording。')
        ..writeln('A persistent notification should be in the shade now (Android), reading demo_recording.')
        ..writeln('— 再取一个下载会话，它会"接管"这条通知 / a download session takes the notification over —');

      final download = await BackgroundExecution.acquire(
        notification: const BackgroundNotification(
          title: '演示：下载大文件',
          text: 'demo_download · 0%',
          kind: BackgroundJobKind.download,
          progress: BackgroundProgress.determinate(current: 0, total: 100),
        ),
      );

      buffer
        ..writeln('acquire -> $download')
        ..writeln('一条通知只能描述一个任务：最新启动的这个拥有它，录制那笔写在正文的 +1 里。')
        ..writeln('One notification describes one job: the newest owns it, the recording shows up as +1 in the text.');

      for (final step in const <int>[20, 40, 60, 80, 100]) {
        await download?.update(
          BackgroundNotification(
            title: '演示：下载大文件',
            text: 'demo_download · $step%',
            kind: BackgroundJobKind.download,
            progress: BackgroundProgress.determinate(current: step, total: 100),
          ),
        );
        buffer.writeln('update -> $step%');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      buffer
        ..writeln()
        ..writeln('— 释放下载：通知回到还在跑的那个录制上 —');
      await download?.release();
      buffer.writeln('released -> $download');

      await Future<void>.delayed(const Duration(seconds: 2));
    } finally {
      // Every path out of here releases, which is the whole point of a session
      // object: the protection cannot outlive the job that asked for it.
      await recording.release();
      buffer
        ..writeln()
        ..writeln('— 全部释放，通知消失 —')
        ..writeln('released -> $recording');
    }

    return buffer.toString();
  }
}
