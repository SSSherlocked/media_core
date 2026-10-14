/// One running FFmpeg ingest process.
///
/// The ingest package does not ship an FFmpeg runtime: hosts already have one
/// (recording, conversion, a bundled binary) and must be able to reuse it
/// instead of linking a second copy into their dependency graph.
abstract interface class IngestFfmpegProcess {
  /// Completes with FFmpeg's exit code; a long-running ingest only ends when
  /// [stop] is called.
  Future<int> get exitCode;

  /// Asks FFmpeg to stop; safe to call more than once.
  Future<void> stop();
}

/// Starts FFmpeg with [arguments] and returns the running process.
typedef IngestFfmpegStarter = Future<IngestFfmpegProcess> Function(List<String> arguments);
