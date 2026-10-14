import 'package:media_core/media_core.dart' show TaskId, TaskPriority;

import 'package:media_core_download/src/download_config.dart';
import 'package:media_core_download/src/download_progress.dart';
import 'package:media_core_download/src/download_status.dart';

/// One file to download.
///
/// The task is the unit the viewer sees: it carries what to fetch, where it
/// goes, how far along it is and why it stopped. The manager owns when it runs.
final class DownloadTask {
  /// Creates a task for [url] destined for [filePath], starting in [status].
  DownloadTask({
    required this.id,
    required this.url,
    required this.filePath,
    this.priority = TaskPriority.normal,
    this.headers = const <String, String>{},
    this.title,
    this.status = DownloadStatus.idle,
    this.progress = const DownloadProgress(),
    this.error,
  });

  /// Task identity, from the core task model.
  ///
  /// A [TaskId] rather than a string so a download is the same kind of thing as
  /// every other task in the framework: the queue, its metrics and any host code
  /// that already handles task ids work on it unchanged.
  final TaskId id;

  /// Queue priority.
  ///
  /// The core queue orders by this, so a viewer can ask for one item to jump the
  /// line without the download package inventing its own ordering.
  final TaskPriority priority;

  /// Source URL.
  final String url;

  /// Absolute destination path.
  ///
  /// A path, not a directory plus a name: file naming is a template decision
  /// made by the host before the task exists, and splitting it here would make
  /// the manager second-guess the template.
  final String filePath;

  /// Extra request headers (referer, cookies, tokens).
  final Map<String, String> headers;

  /// Display label.
  final String? title;

  /// Current status.
  DownloadStatus status;

  /// Transfer state.
  DownloadProgress progress;

  /// Last failure, cleared when the task is retried.
  Object? error;

  /// Whether the task is moving bytes.
  bool get isRunning => status.isRunning;

  /// Whether it has finished, one way or another.
  bool get isTerminal => status.isTerminal;

  /// File name without the directory.
  String get fileName {
    final separator = filePath.contains(r'\') ? r'\' : '/';
    final index = filePath.lastIndexOf(separator);
    return index < 0 ? filePath : filePath.substring(index + 1);
  }

  /// Whether a retry is still allowed under [config].
  bool canRetry(DownloadConfig config) => progress.attempt < config.maxAttempts;

  /// Copies the task with new transfer state.
  DownloadTask copyWith({
    DownloadStatus? status,
    TaskPriority? priority,
    DownloadProgress? progress,
    Object? error,
    bool clearError = false,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      priority: priority ?? this.priority,
      filePath: filePath,
      headers: headers,
      title: title,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  String toString() => 'DownloadTask($id, ${status.name}, $fileName)';
}
