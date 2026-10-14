import 'dart:async';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart' hide Log;
import 'package:media_core/media_core.dart';

import 'package:media_core_audio/src/download/music_download_request.dart';
import 'package:media_core_audio/src/download/music_download_task.dart';

/// Tuning for [MusicDownloader].
final class MusicDownloadConfig {
  /// Creates a config.
  const MusicDownloadConfig({
    this.readTimeout = const Duration(seconds: 20),
    this.threadQueueSize = 4096,
    this.maxLogLines = 80,
    this.protocolWhitelist = 'httpproxy,udp,rtp,rtsp,rtmp,rtmps,srt,tcp,tls,data,file,http,https,crypto,pipe',
  });

  /// Network read timeout (`-rw_timeout`, in microseconds on the wire).
  ///
  /// A music CDN that accepts the connection and then stalls would otherwise
  /// keep a download "running" forever with no progress — the failure mode a
  /// timeout turns into a retryable error.
  final Duration readTimeout;

  /// Input thread queue size (`-thread_queue_size`).
  final int threadQueueSize;

  /// How many ffmpeg log lines are kept for diagnostics.
  final int maxLogLines;

  /// Protocols ffmpeg may follow (`-protocol_whitelist`).
  final String protocolWhitelist;
}

/// Downloads music with ffmpeg.
///
/// Why ffmpeg and not `http.get`: the interesting music URLs are not files.
/// They are HLS manifests, adaptive streams, signed CDN redirects, or FLAC in
/// a container the platform cannot remux by hand — and ffmpeg already does all
/// of that, including writing proper tags and picking the right codec.
///
/// This is a *download*, not a recording: there is no segment clock, no live
/// duration and no lease handling (see pure_live's recorder for that problem
/// space). One source, one output file, progress measured against the track's
/// duration.
///
/// ```dart
/// final downloader = MusicDownloader();
/// await downloader.initialize();
/// final task = await downloader.run(
///   MusicDownloadTask(id: '1', request: request),
///   onUpdate: (task) => print('${task.progress}'),
/// );
/// ```
final class MusicDownloader {
  /// Creates a downloader.
  MusicDownloader({this.config = const MusicDownloadConfig()});

  /// Tuning.
  final MusicDownloadConfig config;

  static bool _ffmpegInitialized = false;
  static Future<void>? _initializing;

  final Map<String, FFmpegSession> _sessions = <String, FFmpegSession>{};
  final Map<String, StringBuffer> _logs = <String, StringBuffer>{};

  bool _disposed = false;

  /// Number of downloads currently running.
  int get runningCount => _sessions.length;

  /// Initializes the native ffmpeg libraries.
  ///
  /// Safe to call repeatedly and from several downloaders: the plugin's
  /// initialization is process-wide, and racing it is a real crash (two
  /// concurrent `dlopen` chains on Android).
  Future<void> initialize() {
    if (_ffmpegInitialized) {
      return Future<void>.value();
    }

    return _initializing ??= FFmpegKitExtended.initialize().then((_) {
      _ffmpegInitialized = true;
    });
  }

  /// Builds the ffmpeg arguments for [request].
  ///
  /// Exposed (and pure) on purpose: it is the part worth testing and the part
  /// a host may want to inspect when a download behaves unexpectedly.
  ///
  /// Argument order matters to ffmpeg — input options must precede `-i`, output
  /// options must follow it — which is why this returns a list rather than
  /// letting callers append at will.
  List<String> buildArguments(MusicDownloadRequest request) {
    final headers = Map<String, String>.from(request.headers);
    final userAgent = request.userAgent ?? headers.remove('user-agent');
    final headerString = _buildHeader(headers);

    return <String>[
      '-hide_banner',
      '-loglevel',
      'info',
      '-nostdin',
      '-protocol_whitelist',
      config.protocolWhitelist,
      '-thread_queue_size',
      '${config.threadQueueSize}',
      '-rw_timeout',
      '${config.readTimeout.inMicroseconds}',
      // A download either produces a correct file or fails; skipping past a
      // corrupt packet would leave a file that plays with a hole in it.
      '-xerror',
      if (userAgent != null && userAgent.isNotEmpty) ...<String>['-user_agent', userAgent],
      if (headerString.isNotEmpty) ...<String>['-headers', headerString],
      '-i',
      request.url,
      // Audio only: a music download must never pull the video track of a
      // music video or an FLV stream.
      '-map',
      '0:a:0',
      '-vn',
      ..._codecArguments(request),
      if (request.title != null) ...<String>['-metadata', 'title=${request.title}'],
      if (request.artist != null) ...<String>['-metadata', 'artist=${request.artist}'],
      if (request.album != null) ...<String>['-metadata', 'album=${request.album}'],
      ...request.extraArguments,
      '-y',
      request.outputPath,
    ];
  }

  /// Runs one download to completion.
  ///
  /// [onUpdate] receives the task on every progress tick and on every status
  /// change. The returned task is the terminal one; a failure is *returned*
  /// rather than thrown, because a download that fails is a normal outcome the
  /// queue wants to retry.
  Future<MusicDownloadTask> run(MusicDownloadTask task, {void Function(MusicDownloadTask)? onUpdate}) async {
    if (_disposed) {
      return task.copyWith(status: MusicDownloadStatus.failed, error: 'Downloader disposed');
    }

    await initialize();

    final running = task.copyWith(status: MusicDownloadStatus.running, startedAt: DateTime.now(), clearError: true);

    onUpdate?.call(running);

    final logs = StringBuffer();
    _logs[task.id] = logs;

    final session = FFmpegKit.createSessionFromArguments(buildArguments(task.request));
    _sessions[task.id] = session;

    final completer = Completer<MusicDownloadTask>();

    session.setLogCallback((log) {
      // `Log.message` is a plain field in the plugin's current API (it read as
      // a getter in older releases).
      final message = log.message;

      if (message.trim().isNotEmpty) {
        logs.writeln(message);

        // Bounded: a long download logs thousands of lines and only the tail
        // is ever useful for diagnosing a failure.
        final lines = logs.toString().split('\n');

        if (lines.length > config.maxLogLines) {
          logs
            ..clear()
            ..writeln(lines.sublist(lines.length - config.maxLogLines).join('\n'));
        }
      }
    });

    session.setStatisticsCallback((statistics) {
      onUpdate?.call(
        running.copyWith(
          processed: Duration(milliseconds: statistics.time),
          speed: statistics.speed > 0 ? statistics.speed : 0,
          bytesWritten: statistics.size,
          sessionId: session.sessionId.toString(),
        ),
      );
    });

    session.setCompleteCallback((completed) {
      _sessions.remove(task.id);
      _logs.remove(task.id);

      final code = completed.getReturnCode();
      final finishedAt = DateTime.now();

      if (_cancelled.contains(task.id)) {
        _cancelled.remove(task.id);

        if (!completer.isCompleted) {
          completer.complete(running.copyWith(status: MusicDownloadStatus.cancelled, finishedAt: finishedAt));
        }

        return;
      }

      // ffmpeg's success code is 0; a negative code is a signal (SIGKILL from
      // cancel, SIGTERM from the OS) and anything positive is an ffmpeg error.
      if (code == 0) {
        if (!completer.isCompleted) {
          completer.complete(running.copyWith(status: MusicDownloadStatus.completed, finishedAt: finishedAt));
        }

        return;
      }

      final tail = logs.toString().trim();
      final reason = _extractError(tail) ?? 'ffmpeg exited with code $code';

      MediaCoreLog.warning(
        LogCategory.error,
        'music download failed: ${task.request.outputPath}',
        fields: <String, Object?>{'code': code, 'url': task.request.url},
      );

      if (!completer.isCompleted) {
        completer.complete(running.copyWith(status: MusicDownloadStatus.failed, error: reason, finishedAt: finishedAt));
      }
    });

    try {
      await session.executeAsync();
    } on Object catch (error) {
      _sessions.remove(task.id);
      _logs.remove(task.id);

      if (!completer.isCompleted) {
        completer.complete(running.copyWith(status: MusicDownloadStatus.failed, error: error.toString()));
      }
    }

    return await completer.future;
  }

  /// Cancels a running download.
  ///
  /// The task is only reported cancelled once ffmpeg's completion callback
  /// arrives: ffmpeg removes its own partial output, and marking the task
  /// terminal earlier would let a queue start the next attempt while the file
  /// is still being written.
  Future<void> cancel(String taskId) async {
    final session = _sessions[taskId];

    if (session == null) {
      return;
    }

    _cancelled.add(taskId);

    FFmpegKit.cancel(session);
  }

  /// Whether [taskId] was cancelled and is waiting for ffmpeg to confirm.
  bool isCancelling(String taskId) => _cancelled.contains(taskId);

  /// Releases sessions and log buffers.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    for (final session in _sessions.values) {
      try {
        FFmpegKit.cancel(session);
      } on Object catch (_) {
        // Best effort: a session that is already gone needs no cancel.
      }
    }

    _sessions.clear();
    _logs.clear();
    _cancelled.clear();
  }

  final Set<String> _cancelled = <String>{};

  /// Codec/output arguments for the requested format.
  List<String> _codecArguments(MusicDownloadRequest request) {
    return switch (request.format) {
      MusicDownloadFormat.copy => const <String>['-c:a', 'copy'],
      MusicDownloadFormat.mp3 => <String>['-c:a', 'libmp3lame', '-b:a', '${request.bitrateKbps}k'],
      MusicDownloadFormat.m4a => <String>[
        '-c:a',
        'aac',
        '-b:a',
        '${request.bitrateKbps}k',
        // Puts the index at the front so the file is seekable while it is
        // still being copied around.
        '-movflags',
        '+faststart',
      ],
      MusicDownloadFormat.flac => const <String>['-c:a', 'flac'],
      MusicDownloadFormat.ogg => <String>['-c:a', 'libvorbis', '-b:a', '${request.bitrateKbps}k'],
      MusicDownloadFormat.wav => const <String>['-c:a', 'pcm_s16le'],
    };
  }

  /// Joins [headers] into the CRLF block ffmpeg's `-headers` option expects.
  ///
  /// Validation is the framework's, not this package's: see
  /// [HttpHeaderSanitizer] for why a header that cannot be sent exactly as
  /// given is an error rather than something to rewrite or drop.
  String _buildHeader(Map<String, String> headers) {
    return HttpHeaderSanitizer.ffmpegBlock(HttpHeaderSanitizer.sanitize(headers));
  }

  /// Picks the most useful line out of an ffmpeg log tail.
  static String? _extractError(String logs) {
    if (logs.isEmpty) {
      return null;
    }

    final lines = logs.split('\n').reversed;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.contains('Server returned') ||
          trimmed.contains('HTTP error') ||
          trimmed.contains('Invalid data found') ||
          trimmed.contains('No such file') ||
          trimmed.contains('Permission denied') ||
          trimmed.contains('Error opening') ||
          trimmed.contains('failed')) {
        return trimmed;
      }
    }

    return null;
  }
}
