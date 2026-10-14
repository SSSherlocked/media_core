/// The seam between the notification vocabulary and whatever draws it.
///
/// One implementation ships ([FlutterLocalNotificationsClient], on top of
/// `flutter_local_notifications`). A host that already owns a notification
/// pipeline — or a test that has no platform at all — passes something else to
/// [MediaCoreNotify.enable] instead, which is why the rest of the package never
/// touches the plugin directly.
library;

import 'package:media_core_notify/media_core_notify.dart' show FlutterLocalNotificationsClient, MediaCoreNotify;

import 'package:media_core_notify/src/notify_event.dart';

/// The notification id the running-jobs line owns.
///
/// Fixed, because Android's foreground service is started against one id and
/// updates have to land on that same one. Posted events draw their own ids from
/// [kFirstPostedNotificationId], so the two never collide.
const int kForegroundNotificationId = 1;

/// Where ids for posted events start counting.
const int kFirstPostedNotificationId = 1000;

/// How a client should be set up.
final class NotifySetup {
  /// Creates a setup description.
  const NotifySetup({
    this.channels = const <NotifyChannel>[kNotifyChannelJobs, kNotifyChannelResults],
    this.androidSmallIcon = '@mipmap/ic_launcher',
    this.foregroundServiceTypes = const <String>{'dataSync'},
    this.onTap,
  });

  /// Channels to register. A platform without channels (Windows, Linux, iOS)
  /// treats this as grouping metadata only.
  final List<NotifyChannel> channels;

  /// The drawable the Android status-bar icon comes from, in the plugin's own
  /// notation (`@drawable/ic_stat_media_core_record` or `@mipmap/ic_launcher`).
  final String androidSmallIcon;

  /// Which Android foreground-service types the running-jobs notification may
  /// claim. `dataSync` covers recording and downloading; the host must declare
  /// the matching `android:foregroundServiceType` on the plugin's service.
  final Set<String> foregroundServiceTypes;

  /// Called when one of this app's notifications is opened.
  final void Function(NotifyTap tap)? onTap;

  /// The channel a job line belongs to, when one was not named.
  NotifyChannel get jobsChannel =>
      channels.firstWhere((channel) => channel.id == kNotifyChannelJobs.id, orElse: () => kNotifyChannelJobs);

  @override
  String toString() =>
      'NotifySetup(channels: ${channels.map((channel) => channel.id).toList()}, icon: $androidSmallIcon)';
}

/// What any notification backend has to be able to do.
///
/// Every method is fire-and-forget on purpose: a notification is never a reason
/// for a job to fail, so the facade swallows what these throw. A client that
/// cannot reach a platform should return normally, not throw — the caller has no
/// useful thing to do with the difference.
abstract interface class LocalNotificationClient {
  /// Registers channels and returns whether notifications can be shown at all.
  Future<bool> configure(NotifySetup setup);

  /// Asks the platform for permission to show notifications.
  ///
  /// `true` when granted. On a platform with no such question (Linux, Windows)
  /// it reports whether the mechanism is there at all.
  Future<bool> requestPermission();

  /// Whether the user currently lets notifications through, without asking.
  Future<bool> notificationsEnabled();

  /// Shows one event, replacing any earlier event with the same [NotifyEvent.id].
  Future<void> post(NotifyEvent event);

  /// Removes the notification with [id], if one is showing.
  Future<void> dismiss(int id);

  /// Starts the running-jobs line, with the platform's "this is protecting work"
  /// affordances (Android foreground service, non-dismissible elsewhere).
  Future<void> startForeground(NotifyEvent event);

  /// Replaces the running-jobs line's text. Same identity as [startForeground].
  Future<void> updateForeground(NotifyEvent event);

  /// Ends the running-jobs line and, on Android, the service behind it.
  Future<void> stopForeground();
}
