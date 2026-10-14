import 'dart:async';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';

/// One progress report from FFmpeg.
///
/// Only the members a recording actually uses are carried over: duration,
/// output size and the two rate figures a host may want to show. The rest of
/// FFmpeg's statistics (frame numbers, quality, duplicate counts) are
/// transcoding concepts and say nothing useful about a `-c copy` capture.
final class FfmpegStatistics {
  /// Creates a report of one FFmpeg statistics line.
  const FfmpegStatistics({
    this.timeMs = 0,
    this.sizeBytes = 0,
    this.bitrate = 0,
    this.speed = 0,
    this.droppedFrames = 0,
  });

  /// Media time processed, in milliseconds.
  ///
  /// For a live capture this is the recording's elapsed media time, not wall
  /// clock: a stalled input stops advancing it, which is exactly what makes it
  /// useful as progress.
  final int timeMs;

  /// Bytes written so far.
  final int sizeBytes;

  /// Output bitrate, in kbit/s.
  final double bitrate;

  /// Processing speed relative to realtime (`1` is realtime).
  final double speed;

  /// Frames dropped at the encoder. Non-zero on a `-c copy` capture means the
  /// input could not keep up with the output.
  final int droppedFrames;

  @override
  String toString() => 'FfmpegStatistics(${timeMs}ms, ${sizeBytes}B, ${speed}x)';
}

/// One FFmpeg process.
abstract interface class FfmpegExecution {
  /// Whether the process is still running.
  bool get isRunning;

  /// Completes when the process ends, with FFmpeg's exit code.
  ///
  /// `0` is success. `255` is what FFmpeg reports for a killed process, which is
  /// how an intentional stop arrives — the caller's intent decides whether that
  /// is a success or a cancellation.
  Future<int> get exitCode;

  /// Asks the process to finish.
  ///
  /// FFmpegKit offers no graceful quit for a capture, so this ends the process
  /// the same way [cancel] does; the difference is the caller's intent, which
  /// the recording backend tracks.
  Future<void> stop();

  /// Ends the process immediately.
  Future<void> cancel();
}

/// Starts FFmpeg processes.
///
/// The seam exists so the recording logic — argument construction, state
/// transitions, exit-code handling — can be tested without a native FFmpeg, and
/// so a host can drive a different build of it.
abstract interface class FfmpegExecutor {
  /// Prepares the native FFmpeg.
  ///
  /// Safe to call repeatedly. A host that warms it up early avoids paying the
  /// native load cost on the first recording action.
  Future<void> initialize();

  /// Starts a process for [arguments].
  Future<FfmpegExecution> start({
    required List<String> arguments,
    void Function(FfmpegStatistics statistics)? onStatistics,
    void Function(String message)? onLog,
  });

  /// Releases the native FFmpeg.
  Future<void> dispose();
}

/// [FfmpegExecutor] backed by `ffmpeg_kit_extended_flutter`.
final class FfmpegKitExecutor implements FfmpegExecutor {
  /// Creates the executor.
  ///
  /// [createSession] and [cancelSession] exist for tests and for hosts pinning
  /// a different plugin build; production callers omit them.
  FfmpegKitExecutor({
    FFmpegSession Function(
      List<String> arguments, {
      FFmpegSessionCompleteCallback? completeCallback,
      FFmpegLogCallback? logCallback,
      FFmpegStatisticsCallback? statisticsCallback,
    })?
    createSession,
    void Function(FFmpegSession session)? cancelSession,
  }) : _createSession = createSession ?? FFmpegSession.createFromArguments,
       _cancelSession = cancelSession ?? FFmpegKit.cancel;

  final FFmpegSession Function(
    List<String> arguments, {
    FFmpegSessionCompleteCallback? completeCallback,
    FFmpegLogCallback? logCallback,
    FFmpegStatisticsCallback? statisticsCallback,
  })
  _createSession;

  final void Function(FFmpegSession session) _cancelSession;

  bool _initialized = false;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }
    await FFmpegKitExtended.initialize();
    _initialized = true;
  }

  @override
  Future<FfmpegExecution> start({
    required List<String> arguments,
    void Function(FfmpegStatistics statistics)? onStatistics,
    void Function(String message)? onLog,
  }) async {
    if (_disposed) {
      throw StateError('FfmpegKitExecutor has been disposed.');
    }
    if (!_initialized) {
      // The plugin asserts on uninitialized use; failing here with a clear
      // message beats a native assertion three frames down.
      throw StateError('FfmpegKitExecutor is not initialized. Call initialize() first.');
    }

    final completion = Completer<void>();

    final session = _createSession(
      arguments,
      completeCallback: (session) {
        if (!completion.isCompleted) {
          completion.complete();
        }
      },
      statisticsCallback: onStatistics == null
          ? null
          : (statistics) {
              onStatistics(
                FfmpegStatistics(
                  timeMs: statistics.time,
                  sizeBytes: statistics.size,
                  bitrate: statistics.bitrate,
                  speed: statistics.speed,
                  droppedFrames: statistics.dropFrames,
                ),
              );
            },
      logCallback: onLog == null ? null : (log) => onLog(log.message),
    );

    return _FfmpegKitExecution(
      session: session..execute(),
      completion: completion.future,
      cancelSession: _cancelSession,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

final class _FfmpegKitExecution implements FfmpegExecution {
  _FfmpegKitExecution({
    required FFmpegSession session,
    required Future<void> completion,
    required void Function(FFmpegSession session) cancelSession,
  }) : _session = session,
       _cancelSession = cancelSession {
    // The exit code is only meaningful once the native call reports back, and
    // the same completion is what says the process is no longer running — the
    // plugin exposes no reliable running flag, so the process lifetime is
    // tracked here instead.
    _exitCode = completion.then((_) {
      _running = false;
      return _session.getReturnCode();
    });
  }

  final FFmpegSession _session;
  final void Function(FFmpegSession session) _cancelSession;
  late final Future<int> _exitCode;
  bool _running = true;

  @override
  bool get isRunning => _running;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  Future<void> stop() async => _cancelSession(_session);

  @override
  Future<void> cancel() async => _cancelSession(_session);
}
