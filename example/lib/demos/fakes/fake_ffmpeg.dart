import 'dart:async';
import 'dart:io';

import 'package:media_core_recording_ffmpeg/media_core_recording_ffmpeg.dart';

/// An FFmpeg process that never starts.
///
/// Recording has two halves: the argument list, which is pure data and printed
/// verbatim, and the process lifecycle — state transitions, statistics, exit-code
/// attribution. The first needs nothing, the second needs a native FFmpeg, and
/// [FfmpegExecutor] is the seam between them. Faking it makes the second half
/// runnable on a machine with no FFmpeg at all, which is what a developer who
/// just cloned the repository has.
///
/// The fake also leaves the artifacts a real capture leaves — the CSV journal and
/// the segment files it names — because the backend reports a recording by what
/// is on disk, and a fake that wrote nothing could not demo a successful stop.
final class FakeFfmpegExecutor implements FfmpegExecutor {
  /// Creates a fake executor.
  new({this.statisticsInterval = const Duration(milliseconds: 120), this.segmentsToWrite = 2});

  /// How often the fake process reports progress.
  final Duration statisticsInterval;

  /// How many segments the fake leaves behind. `0` is a recording that captured
  /// nothing, which is the case an exit code cannot tell apart from a good one.
  final int segmentsToWrite;

  /// Argument lists this executor was asked to run.
  final List<List<String>> started = <List<String>>[];

  /// Whether [initialize] was called.
  bool initialized = false;

  /// Whether [dispose] was called.
  bool disposed = false;

  /// The most recent execution, for a demo that wants to end it deliberately.
  FakeFfmpegExecution? last;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<FfmpegExecution> start({
    required List<String> arguments,
    void Function(FfmpegStatistics statistics)? onStatistics,
    void Function(String message)? onLog,
  }) async {
    if (!initialized) {
      // The real executor refuses this too (the plugin asserts on an
      // uninitialized native library), and a fake that allowed it would let a
      // demo show a sequence no host can run.
      throw StateError('FakeFfmpegExecutor is not initialized. Call initialize() first.');
    }

    started.add(arguments);
    final execution = FakeFfmpegExecution(
      arguments: arguments,
      segmentsToWrite: segmentsToWrite,
      statisticsInterval: statisticsInterval,
    );
    last = execution;
    execution.run(onStatistics: onStatistics, onLog: onLog);
    return execution;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// One fake FFmpeg process.
///
/// It advances its own statistics like a real capture does — media time and
/// output size growing, drift between them — and it can be ended either way:
/// [stop] reports success (what a graceful quit looks like), [cancel] reports
/// FFmpeg's `255` (what a killed process reports).
final class FakeFfmpegExecution implements FfmpegExecution {
  /// Creates a fake process.
  new({
    this.arguments = const <String>[],
    this.segmentsToWrite = 2,
    this.bytesPerSegment = 64 * 1024,
    this.statisticsInterval = const Duration(milliseconds: 120),
  });

  /// The argument list the real FFmpeg would have run, which is where the
  /// journal path and the segment pattern come from.
  final List<String> arguments;

  /// How many segments are left on disk when the process ends.
  final int segmentsToWrite;

  /// Size of each segment the fake writes.
  final int bytesPerSegment;

  /// How often progress is reported.
  final Duration statisticsInterval;

  final Completer<int> _exitCode = Completer<int>();
  final StreamController<String> _logs = StreamController<String>.broadcast();

  Timer? _timer;
  int _ticks = 0;

  @override
  bool get isRunning => !_exitCode.isCompleted;

  @override
  Future<int> get exitCode => _exitCode.future;

  /// Log lines the process emitted.
  Stream<String> get logs => _logs.stream;

  /// How many statistic reports were emitted.
  int get reports => _ticks;

  /// Starts ticking.
  void run({void Function(FfmpegStatistics statistics)? onStatistics, void Function(String message)? onLog}) {
    _logs.add('ffmpeg started (fake)');
    onLog?.call('ffmpeg started (fake)');

    _timer = Timer.periodic(statisticsInterval, (_) {
      _ticks++;
      final statistics = FfmpegStatistics(
        timeMs: _ticks * 500,
        // A segmented capture writes in bursts; the fake grows smoothly.
        sizeBytes: _ticks * 24 * 1024,
        bitrate: 1200,
        speed: 1,
      );
      onStatistics?.call(statistics);
      _logs.add('frame=${_ticks * 30} ...');
    });
  }

  /// Ends the process as a graceful stop.
  @override
  Future<void> stop() async {
    _finish(0);
  }

  /// Ends the process the way a killed FFmpeg ends: code `255`.
  @override
  Future<void> cancel() async {
    _finish(255);
  }

  void _finish(int code) {
    _timer?.cancel();
    _timer = null;
    _leaveOutput();
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
  }

  /// Writes the journal and segments, so the output check has something to read.
  ///
  /// The demo's paths are POSIX-shaped, and a `/` separator is valid on every
  /// platform this example runs on, so the names are joined without a path
  /// package.
  void _leaveOutput() {
    final listIndex = arguments.indexOf('-segment_list');

    if (listIndex < 0 || listIndex + 1 >= arguments.length) {
      return;
    }

    final journalPath = arguments[listIndex + 1];
    final pattern = arguments.last;
    final directory = journalPath.substring(0, journalPath.lastIndexOf('/'));

    try {
      Directory(directory).createSync(recursive: true);

      final names = <String>[];

      for (final index in List<int>.generate(segmentsToWrite, (i) => i)) {
        final name = pattern
            .substring(pattern.lastIndexOf('/') + 1)
            .replaceAll('%06d', index.toString().padLeft(6, '0'));
        names.add(name);
        File('$directory/$name').writeAsBytesSync(List<int>.filled(bytesPerSegment, 0));
      }

      File(journalPath).writeAsStringSync(names.map((name) => "file,'$name'").join('\n'));
    } on Object catch (_) {
      // A demo that cannot write a file still shows the transitions; the
      // recording's own report will say the output is missing, which is honest.
    }
  }
}
