/// User-facing notifications for `media_core`.
///
/// One job's worth of vocabulary, five platforms: the outcome of a download or a
/// recording, and a single running-jobs line that several jobs share.
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await MediaCoreNotify.enable(
///     setup: const NotifySetup(onTap: (tap) => openWhateverTheUserTapped(tap)),
///   );
///   runApp(const MyApp());
/// }
/// ```
///
/// | platform | what a posted event does |
/// | --- | --- |
/// | Android | a notification on a named channel; the running line is a foreground-service notification |
/// | iOS / macOS | a notification centre entry; the running line is delivered without a banner per update |
/// | Windows | a toast; the running line is a normal notification with no service behind it |
/// | Linux | a desktop notification where a server exists; silently dropped where none does |
/// | web | not supported — every call is a no-op that reports `false` |
///
/// ## What this package does not own
///
/// The **media** notification (playback controls, artwork, lock screen) belongs
/// to `media_core_mediasession`, which publishes it through `audio_service`. Two
/// packages drawing one media notification is the classic doubled tray, so the
/// split is by surface, not by convenience.
///
/// **Process protection** on iOS, macOS and Windows belongs to
/// `BackgroundExecution` in `media_core_native`: those platforms have no
/// foreground service, and a notification there is information only. On Android
/// the running line *is* the foreground-service notification — see the setup
/// step below, which is the one thing a host has to do by hand.
///
/// ## Setup
///
/// 1. Ask for the notification permission where the platform has one:
///    `await MediaCoreNotify.requestPermission()` (Android 13+ needs
///    `POST_NOTIFICATIONS`; `media_core_native` already declares it).
/// 2. On Android, if you want the running-jobs line to protect a service, declare
///    `flutter_local_notifications`' own foreground service in your
///    `AndroidManifest.xml`:
///
///    ```xml
///    <service
///        android:name="com.dexterous.flutterlocalnotifications.ForegroundService"
///        android:exported="false"
///        android:stopWithTask="false"
///        android:foregroundServiceType="dataSync" />
///    ```
///
///    Without it the line still posts, and `media_core_native`'s service is what
///    keeps the job alive — the two are not in each other's way.
/// 3. Job outcomes need no wiring beyond this call: `enable()` installs
///    `JobNotifications` into the core's `MediaJobReporting` slot, and
///    `DownloadManager` / `FfmpegRecordingBackend` report their finished and
///    failed jobs through it. Pass `jobOutcomes: NotifyOn.nothing` to keep the
///    running line without the per-job result, or call
///    `MediaCoreNotify.post` yourself for anything this package does not know
///    about.
library;

export 'package:media_core_notify/src/flutter_local_notifications_client.dart' show FlutterLocalNotificationsClient;
export 'package:media_core_notify/src/foreground_jobs.dart' show ForegroundJobHandle, ForegroundJobs;
export 'package:media_core_notify/src/job_reporting.dart' show JobNotifications;
export 'package:media_core_notify/src/media_core_notify.dart' show MediaCoreNotify, NotifyOn;
export 'package:media_core_notify/src/notification_client.dart'
    show LocalNotificationClient, NotifySetup, kFirstPostedNotificationId, kForegroundNotificationId;
export 'package:media_core_notify/src/notify_event.dart'
    show NotifyChannel, NotifyEvent, NotifyTap, NotifyTone, kNotifyChannelJobs, kNotifyChannelResults;
