/// One notification for several running jobs, decided in Dart.
///
/// `media_core_native` used to do this in its Android service: a recording and a
/// download share one foreground notification, the newest one's text shows, the
/// rest are counted, and ending a session reposts without re-alerting. Moving the
/// rule here means the same shape on every platform, and — the reason it matters —
/// a version of it that can be tested without a device.
///
/// The line is reposted at most once per `postGap`. A download updates its byte
/// count several times a second; a notification is not a live readout, and a
/// shelf that re-animates on every byte report is worse than one that says
/// "62%" a moment late.
library;

import 'dart:async';
import 'dart:collection';

import 'package:media_core_native/media_core_native.dart' show BackgroundJobKind, BackgroundNotification;

import 'package:media_core_notify/src/media_core_notify.dart';
import 'package:media_core_notify/src/notification_client.dart' show kForegroundNotificationId;
import 'package:media_core_notify/src/notify_event.dart';

/// A job that is being shown in the running-jobs line.
final class ForegroundJobHandle {
  ForegroundJobHandle._(this.id, this.kind, this._title);

  /// This session's identity within the group.
  final int id;

  /// What the job is, which decides the small icon.
  final BackgroundJobKind kind;

  final String _title;

  bool _released = false;

  /// Whether [release] has run.
  bool get released => _released;

  /// Replaces what this session contributes to the line.
  ///
  /// A no-op after [release], so a late tick from a job that already ended
  /// cannot resurrect the line.
  Future<void> update(BackgroundNotification notification) async {
    if (_released) {
      return;
    }

    await ForegroundJobs._describe(id, notification);
  }

  /// Ends this session. The line stays while another session is running and goes
  /// with the last one.
  Future<void> release() async {
    if (_released) {
      return;
    }

    _released = true;

    await ForegroundJobs._drop(id);
  }

  @override
  String toString() => 'ForegroundJobHandle($id, ${kind.name}, "$_title"${_released ? ', released' : ''})';
}

/// The running-jobs group.
abstract final class ForegroundJobs {
  /// How often the line may be reposted.
  static const Duration postGap = Duration(seconds: 1);

  static final LinkedHashMap<int, BackgroundNotification> _sessions = LinkedHashMap<int, BackgroundNotification>();
  static final List<int> _unused = <int>[];

  static int _nextId = 1;
  static Timer? _gap;
  static bool _dirty = false;
  static bool _showingLine = false;

  /// Sessions currently contributing to the line, oldest first.
  static int get runningCount => _sessions.length;

  /// Whether the platform has been told to show a line at all.
  static bool get isShowingLine => _showingLine;

  /// The text the group would show right now, newest session first.
  ///
  /// Exposed because it is the whole rule of this class, and a test should read
  /// the rule rather than a screenshot of it.
  static String? get lineBody {
    final newest = _newest;

    if (newest == null) {
      return null;
    }

    return _compose(newest);
  }

  /// Shows the line for [notification] and returns the handle that ends it.
  ///
  /// The first session starts the platform's foreground affordance (Android's
  /// foreground service); the ones after it only update the text, so a second job
  /// never takes a second notification — or another service — from the first.
  static Future<ForegroundJobHandle> start(BackgroundNotification notification) async {
    final id = _unused.isNotEmpty ? _unused.removeLast() : _nextId++;
    final kind = notification.kind;
    final handle = ForegroundJobHandle._(id, kind, notification.title);

    _sessions[id] = notification;

    if (_sessions.length == 1) {
      _showingLine = true;
      _dirty = false;
      _gap?.cancel();
      _gap = null;

      await _startLine(handle, notification);
    } else {
      _repaint();
    }

    return handle;
  }

  /// Ends every session and the line, whatever is still running.
  ///
  /// For teardown, not for a job's own exit: a host shutting a page down must not
  /// leave a foreground notification pointing at work that has stopped.
  static Future<void> stopAll() async {
    _gap?.cancel();
    _gap = null;
    _dirty = false;
    _sessions.clear();
    _unused.clear();
    _showingLine = false;

    await MediaCoreNotify.client?.stopForeground();
  }

  /// Forgets the group's state without touching the platform. Test-only.
  static void resetForTest() {
    _gap?.cancel();
    _gap = null;
    _dirty = false;
    _showingLine = false;
    _sessions.clear();
    _unused.clear();
    _nextId = 1;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static BackgroundNotification? get _newest => _sessions.isEmpty ? null : _sessions.values.last;

  static Future<void> _describe(int id, BackgroundNotification notification) async {
    if (!_sessions.containsKey(id)) {
      return;
    }

    _sessions[id] = notification;

    _repaint();
  }

  static Future<void> _drop(int id) async {
    _sessions.remove(id);
    _unused.add(id);

    if (_sessions.isEmpty) {
      _gap?.cancel();
      _gap = null;
      _dirty = false;
      _showingLine = false;

      await MediaCoreNotify.client?.stopForeground();

      return;
    }

    // The newest session changed, so the line has to be redrawn even when the
    // gap is still running: the repost is what carries the new text.
    _repaint();
  }

  /// Posts the aggregated line, at most once per [postGap].
  ///
  /// A repaint request that arrives inside an open window marks it dirty and the
  /// deadline re-posts the newest content — one timer per window, whatever number
  /// of byte reports came in between.
  static void _repaint() {
    if (_gap != null) {
      _dirty = true;

      return;
    }

    _dirty = false;

    unawaited(_flush());

    _gap = Timer(postGap, _onDeadline);
  }

  static void _onDeadline() {
    _gap = null;

    if (_dirty) {
      _dirty = false;

      _repaint();
    }
  }

  static Future<void> _flush() async {
    final newest = _newest;

    if (newest == null || !MediaCoreNotify.enabled) {
      return;
    }

    final client = MediaCoreNotify.client;

    if (client == null) {
      return;
    }

    try {
      await client.updateForeground(_eventFor(newest, _titleOf(newest)));
    } on Exception {
      // A refused repost must not strand the group's timer state.
    }
  }

  static Future<void> _startLine(ForegroundJobHandle handle, BackgroundNotification notification) async {
    final client = MediaCoreNotify.client;

    if (client == null) {
      return;
    }

    try {
      await client.startForeground(_eventFor(notification, _titleOf(notification)));
    } on Exception {
      // No notification server: the job keeps running, and on Android the
      // service simply was not started, which `BackgroundExecution` still covers.
    }

    // The first window opens with the line, so a burst of updates right after
    // start does not repost twice within a few milliseconds.
    _gap = Timer(postGap, _onDeadline);
    _dirty = false;
  }

  static NotifyEvent _eventFor(BackgroundNotification notification, String title) {
    return NotifyEvent(
      title: title,
      body: _compose(notification),
      tone: NotifyTone.progress,
      channel: MediaCoreNotify.setup.jobsChannel,
      kind: notification.kind,
      id: kForegroundNotificationId,
    );
  }

  static String _titleOf(BackgroundNotification notification) => notification.title;

  /// Newest text, plus a count of what else is running.
  static String? _compose(BackgroundNotification newest) {
    final others = _sessions.length - 1;
    final text = newest.text;

    if (others <= 0) {
      return (text == null || text.isEmpty) ? null : text;
    }

    final suffix = '还有 $others 个任务';

    if (text == null || text.isEmpty) {
      return suffix;
    }

    return '$text  ($suffix)';
  }
}
