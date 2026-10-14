/// The vocabulary a notification is described in, with no reference to the
/// package that eventually draws it.
///
/// Keeping the words platform-free is what lets a test assert that a failed
/// download is louder than a finished one without a device attached, and what
/// lets a host that does not want `flutter_local_notifications` plug its own
/// client into [MediaCoreNotify].
library;

import 'package:media_core_native/media_core_native.dart' show BackgroundJobKind;
import 'package:media_core_notify/media_core_notify.dart' show MediaCoreNotify;

/// How insistent a notification is allowed to be.
///
/// The platform owns the last word (a user can silence a whole channel, and on
/// Android 13+ a refused `POST_NOTIFICATIONS` shows nothing at all), but the
/// tone says what the *event* deserves: a finished download should sound, a
/// progress line should not.
enum NotifyTone {
  /// Something the user should read and that stays until dismissed.
  info,

  /// A running job's line: visible, silent, not swipeable away.
  progress,

  /// A job ended well. Makes a noise.
  success,

  /// A job ended, but not as asked (a dropped stream, a partial file).
  warning,

  /// A job could not be done. Loud, and kept.
  failure,
}

/// A notification channel (Android) / the grouping a host silences as a unit.
///
/// Two channels ship: one for the jobs that are running, one for their
/// outcomes. A user who wants no chatter can silence outcomes and keep the
/// running line, which is the split that actually matches intent — muting
/// "download" entirely also hides the fact that a download is holding the
/// process alive.
final class NotifyChannel {
  /// Creates a channel description.
  const NotifyChannel({required this.id, required this.name, this.description, this.tone = NotifyTone.info});

  /// Stable identifier. A channel's settings are remembered by id, so this
  /// string is part of the contract with the device and must not be renamed
  /// casually.
  final String id;

  /// What the user sees in system settings.
  final String name;

  /// Secondary text in settings, where a host can explain the channel.
  final String? description;

  /// The importance the channel is created with (the tone of the loudest thing
  /// that will land on it).
  final NotifyTone tone;

  @override
  String toString() => 'NotifyChannel($id, $name, ${tone.name})';
}

/// The running-jobs channel.
const NotifyChannel kNotifyChannelJobs = NotifyChannel(
  id: 'media_core_jobs',
  name: '媒体任务 / Media jobs',
  description: '录制与下载进行中时的提示线 / Shown while a recording or download runs',
  tone: NotifyTone.progress,
);

/// The job-outcome channel.
const NotifyChannel kNotifyChannelResults = NotifyChannel(
  id: 'media_core_results',
  name: '任务结果 / Media job results',
  description: '录制与下载完成或失败的提示 / When a recording or download ends',
  tone: NotifyTone.success,
);

/// One thing to tell the user about.
///
/// ```dart
/// const NotifyEvent(
///   title: '下载完成',
///   body: 'room-42.ts · 128.4 MB',
///   tone: NotifyTone.success,
///   channel: kNotifyChannelResults,
/// )
/// ```
final class NotifyEvent {
  /// Creates an event.
  const NotifyEvent({
    required this.title,
    this.body,
    this.tone = NotifyTone.info,
    this.channel = kNotifyChannelResults,
    this.kind,
    this.payload,
    this.id,
  });

  /// First line.
  final String title;

  /// Second line: what it worked on. Null shows a bare title.
  final String? body;

  /// How insistent this is allowed to be.
  final NotifyTone tone;

  /// Which channel it lands on, i.e. what a user mutes to stop seeing it.
  final NotifyChannel channel;

  /// What the job is; decides the small icon unless the host configured one.
  final BackgroundJobKind? kind;

  /// Opaque string handed back when the notification is tapped.
  final String? payload;

  /// Notification identity: re-posting the same id replaces the line instead of
  /// stacking another one, which is how progress becomes a result in place.
  ///
  /// Null lets [MediaCoreNotify] allocate a fresh id.
  final int? id;

  /// Same event with some fields replaced.
  NotifyEvent copyWith({String? title, String? body, NotifyTone? tone, int? id, String? payload}) {
    return NotifyEvent(
      title: title ?? this.title,
      body: body ?? this.body,
      tone: tone ?? this.tone,
      channel: channel,
      kind: kind,
      payload: payload ?? this.payload,
      id: id ?? this.id,
    );
  }

  @override
  String toString() => 'NotifyEvent(${tone.name}, $channel, "$title", "$body", id: $id)';
}

/// What a tap on a notification meant.
final class NotifyTap {
  /// Creates a tap record.
  const NotifyTap({required this.id, this.payload, this.actionId});

  /// Which notification was opened.
  final int id;

  /// What the poster attached to it.
  final String? payload;

  /// A notification action's identifier, when the platform reports one.
  final String? actionId;

  @override
  String toString() => 'NotifyTap(id: $id, action: $actionId, payload: $payload)';
}
