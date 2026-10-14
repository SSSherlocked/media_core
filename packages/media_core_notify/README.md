# media_core_notify

User-facing notifications for `media_core`: what a download or a recording ended
with, and one line that says what is running right now.

## Responsibility

**Owns**

- `MediaCoreNotify` — the on/off switch, the permission question, and posting an
  event. Every call is incapable of failing the job it reports for.
- `NotifyTone` — what an event is allowed to do to the user (sound, banner,
  importance, whether it can be swiped away), decided in one table instead of at
  each call site.
- `ForegroundJobs` — several running jobs sharing **one** notification line,
  newest first with the others counted, reposted at most once per second.
- `LocalNotificationClient` — the seam. `FlutterLocalNotificationsClient` is the
  default implementation; nothing above that file touches the plugin.

**Does not own**

- The **media** notification (playback controls, artwork, lock screen, SMTC,
  MPRIS). That is [`media_core_mediasession`](../media_core_mediasession), which
  publishes it through `audio_service`. Two packages drawing one media
  notification is a doubled tray, so the boundary is by surface, not by
  convenience.
- **Process protection.** Keeping a recording or download alive with the screen
  off needs an Android wake lock, an iOS background assertion, macOS
  idle-sleep prevention and `SetThreadExecutionState` on Windows. None of that is
  a notification, and `flutter_local_notifications` offers none of it: it is
  [`media_core_native`](../media_core_native).
- On Android, the **foreground-service notification** stays with
  `media_core_native`'s own service. `startForeground()` must be called by the
  process that owns the service, so handing it to the plugin's service would mean
  either giving up the wake lock or running two services and showing two lines.

## Who may depend on it

Leaf capability package, like `media_core_mediasession` and
`media_core_presentation`: business modules may reference it through a policy
value (`NotifyOn`) and a callback, and only an app or a module that actually
posts events should take the dependency. Nothing in `media_core` depends on it.

## Dependencies and platform requirements

- [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) `^22.3.2` —
  which requires Dart `^3.10.0` and Flutter `>=3.38.1`. This package's SDK floor
  is that constraint, not a choice.
- [`media_core_native`](../media_core_native) `^0.2.0` — for the job vocabulary
  (`BackgroundNotification`, `BackgroundJobKind`, `BackgroundProgress`) and for
  the Android small-icon drawables this package references by name
  (`ic_stat_media_core_record`, `_download`, `_task`).

| platform | a posted event | the running line |
| --- | --- | --- |
| Android | notification on a named channel | native's foreground-service notification |
| iOS / macOS | notification centre entry | a non-dismissible notification, no banner per update |
| Windows | toast | a normal notification (no service exists here) |
| Linux | desktop notification where a server exists | dropped silently where none does |
| web | no-op reporting `false` | no-op |

### Setup

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MediaCoreNotify.enable();          // register channels, install the tap handler
  await MediaCoreNotify.requestPermission(); // Android 13+: POST_NOTIFICATIONS
  runApp(const MyApp());
}
```

To let a tap open something, pass `NotifySetup(onTap: ...)` to `enable`. On
Android, `POST_NOTIFICATIONS` is already declared by `media_core_native`; if you
also want the plugin's own foreground service (you probably do not — see
*Does not own* above), that is the `AndroidManifest.xml` step in the
`flutter_local_notifications` README.

## Public entry point

`package:media_core_notify/media_core_notify.dart` — `MediaCoreNotify`,
`NotifyEvent`, `NotifyTone`, `NotifyChannel`, `NotifyOn`, `NotifySetup`,
`ForegroundJobs`, `LocalNotificationClient`, `FlutterLocalNotificationsClient`.

## Usage

```dart
// A module that reports outcomes, filtered by what the host asked for:
await MediaCoreNotify.postOutcome(
  NotifyEvent(
    title: '下载完成',
    body: '${task.fileName} · ${task.sizeInBytes} B',
    tone: NotifyTone.success,
    kind: BackgroundJobKind.download,
    id: task.notificationId, // the progress line becomes the result in place
  ),
  policy: notifyOn,
);

// A running job takes part of the shared line:
final job = await ForegroundJobs.start(
  const BackgroundNotification(title: '正在录制', text: 'room-42 · 00:12'),
);
await job.update(notification.copyWith(text: 'room-42 · 01:30'));
await job.release(); // the line falls with the last job, not the first
```

## Testing

```powershell
flutter test          # 21 cases, no platform required
flutter analyze
dart ..\tool\validate_packages.dart
```

`LocalNotificationClient` is why the suite needs no device: it records the
events that *would* have been shown, so the foreground rules are tested as
behaviour — one start for many jobs, the newest text plus a count, a repost at
most once per second, exactly one stop, and a released job unable to resurrect
the line.

## Known limitations

- **Not verified on a device.** No case here proves how a real notification
  head, sounds or groups on a given Android version; the tone mapping is asserted
  as far as the client sees it.
- The timer churn saved by `ForegroundJobs` (one repost per window instead of
  one per report) is observable in tests; the equivalent saving inside
  `FlutterLocalNotificationsClient` is not, because that file is the boundary.
- No notification actions (buttons). A stop button needs a callback path into a
  running isolate, which is a feature of its own.
- Channel *names* are English-with-Chinese strings chosen here; a host that ships
  localized settings text should pass its own `NotifySetup(channels: ...)`.
