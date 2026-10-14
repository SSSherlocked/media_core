import 'package:media_core/recording/recording_config.dart';
import 'package:media_core/recording/recording_result.dart';
import 'package:media_core/recording/recording_source.dart';
import 'package:media_core/recording/recording_state.dart';

/// Defines the backend contract used to perform a recording.
///
/// A [RecordingBackend] is the lowest-level recording abstraction exposed by
/// the recording module. Concrete implementations can connect this contract
/// to platform APIs, native media frameworks, FFmpeg, or another recording
/// implementation.
///
/// Responsibilities:
///
/// - report backend availability
/// - start recording from a [RecordingSource]
/// - stop the active recording
/// - cancel the active recording
/// - expose recording state changes
/// - release backend resources
///
/// It does not:
///
/// - manage application-level recording sessions
/// - enforce global recording concurrency
/// - choose between multiple backends
/// - define recording configuration policy
///
/// Those responsibilities belong to:
///
/// - RecordingSession
/// - RecordingManager
/// - backend selection/factory logic
abstract interface class RecordingBackend {
  /// Whether this backend can currently perform recording.
  bool get isAvailable;

  /// Current backend recording state.
  RecordingState get state;

  /// Starts recording [source] using [config].
  ///
  /// Implementations should transition through the appropriate recording
  /// states before returning the final start result.
  Future<void> start(RecordingSource source, RecordingConfig config);

  /// Stops the active recording and returns its final result.
  ///
  /// Implementations should finalize the output before returning.
  Future<RecordingResult> stop();

  /// Cancels the active recording.
  ///
  /// Cancellation should release backend resources without treating the
  /// recording as a successfully completed output.
  Future<void> cancel();

  /// Releases resources owned by the backend.
  Future<void> dispose();
}
