import 'dart:async';

import 'package:media_core/media_core.dart' show MediaJobKind, MediaJobOutcome, MediaJobReporter, MediaJobReporting;
import 'package:media_core_native/media_core_native.dart' show BackgroundJobKind;
import 'package:media_core_notify/src/media_core_notify.dart';
import 'package:media_core_notify/src/notify_event.dart';

/// The reporter that turns a finished job into a notification.
///
/// `MediaCoreNotify.enable` installs it and `MediaCoreNotify.disable` removes it,
/// which is what lets `media_core_download` and `media_core_recording_ffmpeg`
/// report their outcomes without either one depending on a notification plugin:
/// they call the core's `MediaJobReporting` slot, and a host that never enables
/// this package simply has nothing in it.
final class JobNotifications implements MediaJobReporter {
  /// Creates the reporter with the policy that decides what counts as telling.
  const JobNotifications({this.policy = NotifyOn.results});

  /// Creates one and puts it in the core's slot, replacing whatever was there.
  ///
  /// This is the wiring a host does once at startup when it wants job outcomes
  /// without the rest of the facade; [MediaCoreNotify.enable] calls it.
  JobNotifications.installed({this.policy = NotifyOn.results}) {
    MediaJobReporting.reporter = this;
  }

  /// Which outcomes are posted.
  ///
  /// [NotifyOn.results] by default: the viewer waiting for a file wants to know
  /// when it is there, and rarely wants a second line for when it started.
  final NotifyOn policy;

  /// Removes a reporter this class installed, leaving a host's own in place.
  static void uninstall() {
    if (MediaJobReporting.reporter is JobNotifications) {
      MediaJobReporting.reset();
    }
  }

  @override
  void report(MediaJobOutcome outcome) {
    // Fire and forget, and never rethrown: the job is already done, and a tray
    // that refuses the line must not become a failure of the download.
    unawaited(MediaCoreNotify.postOutcome(_eventFor(outcome), policy: policy));
  }

  static NotifyEvent _eventFor(MediaJobOutcome outcome) {
    final error = outcome.error;
    final details = <String>[
      outcome.label,
      if (outcome.elapsed != null && outcome.elapsed! > Duration.zero) _clock(outcome.elapsed!),
      if (outcome.bytesWritten != null && outcome.bytesWritten! > 0) _size(outcome.bytesWritten!),
      if (!outcome.success && error != null) '$error',
    ];

    return NotifyEvent(
      title: _title(outcome),
      body: details.join(' · '),
      tone: outcome.success ? NotifyTone.success : NotifyTone.failure,
      kind: switch (outcome.kind) {
        MediaJobKind.download => BackgroundJobKind.download,
        MediaJobKind.recording => BackgroundJobKind.record,
      },
    );
  }

  static String _title(MediaJobOutcome outcome) => switch (outcome.kind) {
    MediaJobKind.download => outcome.success ? '下载完成' : '下载失败',
    MediaJobKind.recording => outcome.success ? '录制完成' : '录制中断',
  };

  static String _clock(Duration elapsed) {
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }

    return '$bytes B';
  }
}
