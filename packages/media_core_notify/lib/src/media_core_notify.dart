/// The one entry point a host uses: say yes once, then describe events.
///
/// Everything here is deliberately *unable* to break the job it reports for. A
/// notification is how the user finds out what is happening; it is not the thing
/// happening. So calls before [MediaCoreNotify.enable] do nothing, calls the
/// platform refuses do nothing, and nothing in this file throws at a caller that
/// was only trying to be informative.
library;

import 'package:media_core_notify/src/flutter_local_notifications_client.dart';
import 'package:media_core_notify/src/job_reporting.dart';
import 'package:media_core_notify/src/notification_client.dart';
import 'package:media_core_notify/src/notify_event.dart';

/// What a host may ask to be told about.
///
/// Passed to a module as a policy rather than a pile of flags: a host that never
/// wants a tray full of chatter passes [NotifyOn.nothing] and keeps only the
/// running-jobs line, if it asked for that separately.
enum NotifyOn {
  /// Nothing but the running-jobs line.
  nothing,

  /// Outcomes only: finished, partially finished, failed.
  results,

  /// Outcomes plus the moment a job starts.
  startsAndResults,
}

/// User-facing notifications for media_core.
abstract final class MediaCoreNotify {
  static LocalNotificationClient? _client;
  static NotifySetup _setup = const NotifySetup();
  static int _nextId = kFirstPostedNotificationId;

  /// Whether [enable] has run and left a client behind.
  static bool get enabled => _client != null;

  /// The client in use, for a host that wants to talk to the mechanism directly.
  static LocalNotificationClient? get client => _client;

  /// The setup [enable] was given.
  static NotifySetup get setup => _setup;

  /// Turns notifications on, and reports whether the platform accepted them.
  ///
  /// ```dart
  /// await MediaCoreNotify.enable();
  /// ```
  ///
  /// [client] defaults to [FlutterLocalNotificationsClient]. Passing another one
  /// is how a host with its own pipeline — or a test with no platform at all —
  /// joins in. Calling this twice replaces the client rather than stacking two.
  ///
  /// [jobOutcomes] is also the policy the download and recording packages report
  /// through: enabling notifications installs [JobNotifications] into the core's
  /// `MediaJobReporting` slot, which is how a finished file or an interrupted
  /// recording reaches the tray without either package depending on this one.
  /// [NotifyOn.nothing] keeps the reporter in place but posts nothing for a job
  /// that ends, while the running line stays as asked.
  ///
  /// A `false` return is not a failure to act on: it means the platform has no
  /// notification pipeline here, and every other call keeps working as a no-op.
  static Future<bool> enable({
    LocalNotificationClient? client,
    NotifySetup setup = const NotifySetup(),
    NotifyOn jobOutcomes = NotifyOn.results,
  }) async {
    _setup = setup;

    final chosen = client ?? FlutterLocalNotificationsClient();
    _client = chosen;
    JobNotifications.installed(policy: jobOutcomes);

    return await _ask<bool>(() => chosen.configure(setup), fallback: false);
  }

  /// Forgets the client. Used by tests, and by a host tearing a process down.
  static void disable() {
    _client = null;
    _setup = const NotifySetup();
    _nextId = kFirstPostedNotificationId;
    JobNotifications.uninstall();
  }

  /// Asks the platform for permission, where it has a question to ask.
  static Future<bool> requestPermission() {
    final client = _client;

    if (client == null) {
      return Future<bool>.value(false);
    }

    return _ask<bool>(client.requestPermission, fallback: false);
  }

  /// Whether notifications would reach the user right now, without asking again.
  static Future<bool> notificationsEnabled() {
    final client = _client;

    if (client == null) {
      return Future<bool>.value(false);
    }

    return _ask<bool>(client.notificationsEnabled, fallback: false);
  }

  /// Shows one event. Returns whether it reached the client.
  ///
  /// An event without an [NotifyEvent.id] is given one here rather than by the
  /// client, so the id a caller might later [dismiss] is part of this package's
  /// contract and the same for every backend — and so a progress line and the
  /// result that replaces it are the same notification only if somebody outside
  /// the plugin can see which one it is.
  static Future<bool> post(NotifyEvent event) {
    final client = _client;

    if (client == null) {
      return Future<bool>.value(false);
    }

    final id = event.id ?? _nextId++;

    return _run(() => client.post(event.copyWith(id: id)));
  }

  /// Removes a notification by id.
  static Future<bool> dismiss(int id) {
    final client = _client;

    if (client == null) {
      return Future<bool>.value(false);
    }

    return _run(() => client.dismiss(id));
  }

  /// Posts [event] only if [policy] covers it, and says whether it did.
  ///
  /// [isStart] separates "a job began" from "a job ended", because a host that
  /// wants to know when something finishes rarely wants a line for every file
  /// that begins.
  static Future<bool> postOutcome(NotifyEvent event, {required NotifyOn policy, bool isStart = false}) {
    final wanted = switch (policy) {
      NotifyOn.nothing => false,
      NotifyOn.results => !isStart,
      NotifyOn.startsAndResults => true,
    };

    if (!wanted) {
      return Future<bool>.value(false);
    }

    return post(event);
  }

  static Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();

      return true;
    } on Exception {
      // No plugin registered on this platform, the channel refused, the service
      // was not declared. The job the notification was describing is unaffected.
      return false;
    }
  }

  static Future<R> _ask<R>(Future<R> Function() action, {required R fallback}) async {
    try {
      return await action();
    } on Exception {
      return fallback;
    }
  }
}
