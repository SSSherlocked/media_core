/// Offline media downloads for media_core.
///
/// A task queue with a concurrency limit, resumable transfers and a retry
/// budget:
///
/// ```dart
/// final manager = DownloadManager();
/// manager.onTaskChanged.listen((task) => print('${task.fileName}: ${task.progress.percent}%'));
///
/// manager.add(DownloadTask(
///   id: roomId,
///   url: streamUrl,
///   filePath: '$downloadsDir/$roomId.ts',
///   headers: {'Referer': pageUrl},
/// ));
/// ```
///
/// The two decisions worth reading about are on [DownloadManager]: a bounded
/// queue, and a resume that verifies the partial file before appending to it
/// (see [DownloadResumePlanner]).
library;

import 'package:media_core_download/media_core_download.dart' show DownloadManager, DownloadResumePlanner;

export 'package:media_core_download/src/download_config.dart';
export 'package:media_core_download/src/download_file_sink.dart';
export 'package:media_core_download/src/download_manager.dart';
export 'package:media_core_download/src/download_progress.dart';
export 'package:media_core_download/src/download_resume.dart';
export 'package:media_core_download/src/download_status.dart';
export 'package:media_core_download/src/download_task.dart';
export 'package:media_core_download/src/download_transport.dart';
