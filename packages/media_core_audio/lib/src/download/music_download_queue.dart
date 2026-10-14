import 'dart:async';

import 'package:media_core_audio/src/download/music_download_request.dart';
import 'package:media_core_audio/src/download/music_download_task.dart';
import 'package:media_core_audio/src/download/music_downloader.dart';
import 'package:media_core_audio/src/track/music_track.dart';
import 'package:media_core_audio/src/track/track_source.dart';

/// A download queue with bounded concurrency and retries.
///
/// Music downloads are started from a list (select several songs, "download
/// all"), which means they arrive in bursts. Running them all at once turns a
/// rate-limited music API into a wall of failures, so the queue keeps at most
/// [maxConcurrent] ffmpeg sessions alive and retries a failed one up to
/// [maxAttempts] times — a signed URL that expired mid-download, or a CDN that
/// dropped a connection, both succeed on a second attempt with a fresh URL.
///
/// The queue owns task *status*, not task URLs: a host that needs a fresh URL
/// per attempt passes a `resolve` callback, and the queue re-resolves before
/// each retry instead of replaying a spent signature.
final class MusicDownloadQueue {
  /// Creates a queue.
  MusicDownloadQueue({
    MusicDownloader? downloader,
    this.maxConcurrent = 1,
    this.maxAttempts = 2,
    this.retryDelay = const Duration(seconds: 2),
  }) : _downloader = downloader ?? MusicDownloader();

  /// Maximum simultaneous downloads.
  final int maxConcurrent;

  /// Attempts per task, including the first.
  final int maxAttempts;

  /// Delay before a retry.
  final Duration retryDelay;

  final MusicDownloader _downloader;
  final Map<String, MusicDownloadTask> _tasks = <String, MusicDownloadTask>{};
  final Map<String, Future<void>> _running = <String, Future<void>>{};
  final StreamController<MusicDownloadTask> _updates = StreamController<MusicDownloadTask>.broadcast();

  /// Per-task URL resolvers, used by retries to obtain a fresh URL.
  final Map<String, Future<MusicDownloadRequest> Function()> _resolvers = {};

  int _sequence = 0;
  bool _disposed = false;

  /// Task updates: progress ticks and status changes.
  Stream<MusicDownloadTask> get updates => _updates.stream;

  /// All known tasks, in enqueue order.
  List<MusicDownloadTask> get tasks => List<MusicDownloadTask>.unmodifiable(_tasks.values);

  /// Tasks that reached a terminal status.
  List<MusicDownloadTask> get finished => _tasks.values.where((task) => task.isTerminal).toList(growable: false);

  /// Tasks still queued or running.
  List<MusicDownloadTask> get pending => _tasks.values.where((task) => !task.isTerminal).toList(growable: false);

  /// Whether anything is queued or running.
  bool get isActive => pending.isNotEmpty;

  /// The underlying downloader.
  MusicDownloader get downloader => _downloader;

  /// Enqueues [request].
  ///
  /// [resolve] is optional and only used for retries: pass a callback that
  /// re-resolves the track's URL when the host knows the URL is signed and
  /// short-lived.
  MusicDownloadTask enqueue(
    MusicDownloadRequest request, {
    String? id,
    Future<MusicDownloadRequest> Function()? resolve,
  }) {
    final taskId = id ?? 'dl_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
    final task = MusicDownloadTask(id: taskId, request: request);

    _tasks[taskId] = task;

    if (resolve != null) {
      _resolvers[taskId] = resolve;
    }

    _emit(task);
    unawaited(_drain());

    return task;
  }

  /// Enqueues a track resolved by [source].
  MusicDownloadTask downloadTrack({
    required MusicTrack track,
    required TrackSource source,
    required String directory,
    String pattern = '{artist} - {title}',
    MusicDownloadFormat? format,
    int bitrateKbps = 320,
    Future<MusicDownloadRequest> Function()? resolve,
  }) {
    return enqueue(
      MusicDownloadRequest.forTrack(
        track: track,
        source: source,
        directory: directory,
        pattern: pattern,
        format: format,
        bitrateKbps: bitrateKbps,
      ),
      resolve: resolve,
    );
  }

  /// Cancels a task, queued or running.
  Future<void> cancel(String taskId) async {
    final task = _tasks[taskId];

    if (task == null || task.isTerminal) {
      return;
    }

    if (!_running.containsKey(taskId)) {
      // Still queued: it never started, so there is nothing to interrupt.
      _emit(task.copyWith(status: MusicDownloadStatus.cancelled, finishedAt: DateTime.now()));

      return;
    }

    await _downloader.cancel(taskId);
  }

  /// Forgets terminal tasks.
  void clearFinished() {
    _tasks.removeWhere((id, task) {
      final remove = task.isTerminal;

      if (remove) {
        _resolvers.remove(id);
      }

      return remove;
    });
  }

  /// Runs one task to completion, retrying per [maxAttempts].
  ///
  /// Each retry may re-resolve the URL: the failure worth retrying is almost
  /// always a spent signature or a dropped CDN connection, and replaying the
  /// same expired URL would fail identically every time.
  Future<void> _run(String taskId) async {
    final queued = _tasks[taskId];

    if (queued == null) {
      return;
    }

    var task = queued;

    while (!_disposed && !task.isTerminal) {
      final finished = await _downloader.run(task, onUpdate: _emit);

      _emit(finished);

      if (finished.isCompleted || finished.status == MusicDownloadStatus.cancelled) {
        return;
      }

      if (finished.attempt >= maxAttempts) {
        return;
      }

      final nextAttempt = finished.attempt + 1;

      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }

      if (_disposed) {
        return;
      }

      var request = finished.request;
      final resolver = _resolvers[taskId];

      if (resolver != null) {
        try {
          request = await resolver();
        } on Object catch (_) {
          // Resolution failed: keep the previous request and let the next
          // attempt report the download error.
        }
      }

      task = MusicDownloadTask(id: taskId, request: request, attempt: nextAttempt, error: finished.error);

      _emit(task);
    }
  }

  /// Starts queued tasks while a slot is free.
  Future<void> _drain() async {
    if (_disposed) {
      return;
    }

    while (_running.length < maxConcurrent) {
      final next = _tasks.entries
          .where((entry) => entry.value.status == MusicDownloadStatus.queued && !_running.containsKey(entry.key))
          .map((entry) => entry.key)
          .firstOrNull;

      if (next == null) {
        return;
      }

      final completer = Completer<void>();

      _running[next] = completer.future;

      unawaited(
        _run(next).whenComplete(() {
          unawaited(_running.remove(next));
          completer.complete();

          if (!_disposed) {
            unawaited(_drain());
          }
        }),
      );
    }
  }

  void _emit(MusicDownloadTask task) {
    if (_disposed) {
      return;
    }

    _tasks[task.id] = task;

    if (!_updates.isClosed) {
      _updates.add(task);
    }
  }

  /// Cancels everything and releases the downloader.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    for (final id in _running.keys.toList(growable: false)) {
      await _downloader.cancel(id);
    }

    _running.clear();
    _resolvers.clear();

    await _downloader.dispose();
    await _updates.close();
  }
}
