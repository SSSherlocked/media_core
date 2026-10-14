/// The `flutter_local_notifications` implementation of [LocalNotificationClient].
///
/// All of the plugin's surface that this package needs lives here, so the tone
/// mapping (what an event is allowed to do to the user) is one table rather than
/// scattered decisions, and so a host can replace the whole mechanism by passing
/// a different client.
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:media_core_native/media_core_native.dart' show BackgroundJobKind;

import 'package:media_core_notify/src/notification_client.dart';
import 'package:media_core_notify/src/notify_event.dart';

/// The client backed by `flutter_local_notifications`.
final class FlutterLocalNotificationsClient implements LocalNotificationClient {
  /// Creates a client. A second instance is harmless: the plugin it wraps is a
  /// singleton, so both talk to the same pipeline.
  FlutterLocalNotificationsClient({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  NotifySetup _setup = const NotifySetup();
  int _nextId = kFirstPostedNotificationId;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> configure(NotifySetup setup) async {
    _setup = setup;

    final initialization = InitializationSettings(
      android: AndroidInitializationSettings(setup.androidSmallIcon),
      // Permission questions are asked explicitly through [requestPermission];
      // initialising must not raise one on first launch.
      iOS: const DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: const DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    final started = await _plugin.initialize(
      settings: initialization,
      onDidReceiveNotificationResponse: (response) {
        setup.onTap?.call(NotifyTap(id: response.id ?? 0, payload: response.payload, actionId: response.actionId));
      },
    );

    final android = _android;

    if (android != null) {
      for (final channel in setup.channels) {
        await android.createNotificationChannel(
          AndroidNotificationChannel(
            channel.id,
            channel.name,
            description: channel.description,
            importance: _importanceOf(channel.tone),
            // The running-jobs line is a status, not an interruption: it must
            // never ring, whatever the tone of the moment it was created with.
            playSound: channel.tone != NotifyTone.progress,
          ),
        );
      }
    }

    return started ?? true;
  }

  @override
  Future<bool> requestPermission() async {
    if (kIsWeb) {
      return false;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => await _android?.requestNotificationsPermission() ?? false,
      TargetPlatform.iOS =>
        await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false,
      TargetPlatform.macOS =>
        await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false,
      // No question to ask: Linux and Windows report what they already allow.
      _ => await notificationsEnabled(),
    };
  }

  @override
  Future<bool> notificationsEnabled() async {
    if (kIsWeb) {
      return false;
    }

    final android = _android;

    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }

    // Where the plugin cannot answer, assume yes: a Linux desktop with no
    // notification server fails at post time, and that is reported there.
    return true;
  }

  @override
  Future<void> post(NotifyEvent event) async {
    final id = event.id ?? _nextId++;

    await _plugin.show(
      id: id,
      title: event.title,
      body: event.body,
      payload: event.payload,
      notificationDetails: _detailsFor(event.copyWith(id: id), ongoing: false),
    );
  }

  @override
  Future<void> dismiss(int id) => _plugin.cancel(id: id);

  @override
  Future<void> startForeground(NotifyEvent event) async {
    final ongoing = event.copyWith(id: kForegroundNotificationId, tone: NotifyTone.progress);
    final android = _android;

    if (android == null) {
      // No foreground service exists off Android. The line is still worth
      // showing (a recording on macOS says so), and the process protection is
      // `media_core_native`'s job, not this client's.
      await _plugin.show(
        id: kForegroundNotificationId,
        title: ongoing.title,
        body: ongoing.body,
        payload: ongoing.payload,
        notificationDetails: _detailsFor(ongoing, ongoing: true),
      );

      return;
    }

    await android.startForegroundService(
      id: kForegroundNotificationId,
      title: ongoing.title,
      body: ongoing.body,
      payload: ongoing.payload,
      notificationDetails: _androidDetails(ongoing, ongoing: true),
      // A service that outlives a crash would show a line for work nobody is
      // doing, so the system is allowed to drop it.
      startType: AndroidServiceStartType.startNotSticky,
      foregroundServiceTypes: _foregroundTypes(_setup.foregroundServiceTypes),
    );
  }

  @override
  Future<void> updateForeground(NotifyEvent event) => _plugin.show(
    id: kForegroundNotificationId,
    title: event.title,
    body: event.body,
    payload: event.payload,
    notificationDetails: _detailsFor(
      event.copyWith(id: kForegroundNotificationId, tone: NotifyTone.progress),
      ongoing: true,
    ),
  );

  @override
  Future<void> stopForeground() async {
    await _android?.stopForegroundService();

    // The notification goes with the service, but a posted line on another
    // platform has no service to end and must be cleared by hand.
    await _plugin.cancel(id: kForegroundNotificationId);
  }

  // ---------------------------------------------------------------------------
  // Tone mapping
  // ---------------------------------------------------------------------------

  NotificationDetails _detailsFor(NotifyEvent event, {required bool ongoing}) {
    return NotificationDetails(
      android: _androidDetails(event, ongoing: ongoing),
      iOS: _darwinDetails(event.tone),
      macOS: _darwinDetails(event.tone),
    );
  }

  AndroidNotificationDetails _androidDetails(NotifyEvent event, {required bool ongoing}) {
    final progress = event.tone == NotifyTone.progress;

    return AndroidNotificationDetails(
      event.channel.id,
      event.channel.name,
      channelDescription: event.channel.description,
      importance: _importanceOf(event.tone),
      priority: _priorityOf(event.tone),
      playSound: !progress,
      silent: progress,
      // A progress line is reposted several times a second; without this the
      // shelf re-animates on every one of them.
      onlyAlertOnce: progress,
      ongoing: ongoing,
      autoCancel: !ongoing,
      visibility: progress ? NotificationVisibility.public : NotificationVisibility.private,
      icon: _iconFor(event.kind),
      groupKey: 'media_core.jobs',
    );
  }

  DarwinNotificationDetails _darwinDetails(NotifyTone tone) {
    final progress = tone == NotifyTone.progress;

    return DarwinNotificationDetails(
      // iOS and macOS banner a notification every time it is posted, so a
      // progress line would fire a banner per update. It stays in the centre
      // without interrupting.
      presentAlert: !progress,
      presentSound: tone != NotifyTone.info && !progress,
      presentBadge: !progress,
      presentBanner: !progress,
      presentList: true,
      interruptionLevel: progress ? InterruptionLevel.passive : InterruptionLevel.timeSensitive,
    );
  }

  Importance _importanceOf(NotifyTone tone) => switch (tone) {
    NotifyTone.progress => Importance.low,
    NotifyTone.info => Importance.defaultImportance,
    NotifyTone.success => Importance.high,
    NotifyTone.warning => Importance.high,
    NotifyTone.failure => Importance.max,
  };

  Priority _priorityOf(NotifyTone tone) => switch (tone) {
    NotifyTone.progress => Priority.min,
    NotifyTone.info => Priority.defaultPriority,
    NotifyTone.success => Priority.high,
    NotifyTone.warning => Priority.high,
    NotifyTone.failure => Priority.max,
  };

  /// The small icon for a job kind, using the glyphs `media_core_native`
  /// already ships in its Android resources.
  String? _iconFor(BackgroundJobKind? kind) => switch (kind) {
    BackgroundJobKind.record => '@drawable/ic_stat_media_core_record',
    BackgroundJobKind.download => '@drawable/ic_stat_media_core_download',
    BackgroundJobKind.task => '@drawable/ic_stat_media_core_task',
    null => null,
  };

  Set<AndroidServiceForegroundType>? _foregroundTypes(Set<String> names) {
    if (names.isEmpty) {
      return null;
    }

    return {
      for (final name in names)
        switch (name) {
          'dataSync' => AndroidServiceForegroundType.foregroundServiceTypeDataSync,
          'mediaPlayback' => AndroidServiceForegroundType.foregroundServiceTypeMediaPlayback,
          'location' => AndroidServiceForegroundType.foregroundServiceTypeLocation,
          'camera' => AndroidServiceForegroundType.foregroundServiceTypeCamera,
          'microphone' => AndroidServiceForegroundType.foregroundServiceTypeMicrophone,
          _ => AndroidServiceForegroundType.foregroundServiceTypeDataSync,
        },
    };
  }
}
