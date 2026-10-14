## Unreleased

- `MediaCoreNotify.enable()` now also turns on job outcomes. It installs `JobNotifications` into the core's `MediaJobReporting` slot, so a download that finished or a recording that stopped early reaches the tray without `media_core_download` or `media_core_recording_ffmpeg` depending on this package: 下载完成 / 下载失败 / 录制完成 / 录制中断, each with the file or prefix, the bytes, the media time actually recorded and the error when there was one. The policy is `enable`'s new `jobOutcomes` argument (`NotifyOn.results` by default, `NotifyOn.nothing` keeps the running line and drops the per-job result), and `disable()` takes back only a reporter this package installed — a reporter the host wrote itself stays where the host put it.


## 0.1.0

Initial release.

- `MediaCoreNotify`: say yes once at app start, then describe events. `post`, `dismiss`, `requestPermission`, `notificationsEnabled`, and a `NotifyOn` policy so a host can choose results only, or nothing at all. Nothing in it can fail the job it is reporting for — every platform refusal is a silent `false`.
- `NotifyTone` is what decides how insistent an event may be: a progress line is silent, only-alerts-once and non-dismissible, a result makes a noise, and a failure is loudest and stays until opened. The mapping lives in one table, so "why does this beep" has one answer.
- `ForegroundJobs`: several running jobs share one line — newest first, the rest counted — reposted at most once per second. That rule used to live inside `media_core_native`'s Android service, where nothing could see it; here it is Dart, with tests, and it behaves the same on Windows, Linux and macOS where a job line exists but no service does.
- `LocalNotificationClient` is the seam. `flutter_local_notifications` 22.x is the default implementation (`FlutterLocalNotificationsClient`) and nothing above that file touches the plugin, so a host with its own notification pipeline can pass its own client and a suite with no platform at all can assert on what would have been shown.
- The job glyphs `media_core_native` already ships (`ic_stat_media_core_record`, `_download`, `_task`) are reused as the Android small icons, so a recording never shows a download arrow.
