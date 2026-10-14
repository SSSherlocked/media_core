import 'package:clock/clock.dart';
import 'package:media_core/recording/recording_backend.dart';
import 'package:media_core/recording/recording_config.dart';
import 'package:media_core/recording/recording_error.dart';
import 'package:media_core/recording/recording_result.dart';
import 'package:media_core/recording/recording_source.dart';
import 'package:media_core/recording/recording_state.dart';
import 'package:rxdart/rxdart.dart';

/// Represents one recording lifecycle session.
///
/// A [RecordingSession] owns one logical recording lifecycle from start
/// through completion, failure, or cancellation.
///
/// Responsibilities:
///
/// - maintain recording state
/// - coordinate one recording source and configuration
/// - delegate recording operations to a backend
/// - expose reactive recording state
/// - produce the final recording result
///
/// It does not:
///
/// - implement media encoding
/// - write media data directly
/// - select a platform recording API
/// - manage multiple recording sessions
///
/// Those responsibilities belong to:
///
/// - RecordingBackend
/// - RecordingManager
final class RecordingSession {
  /// Creates a recording session.
  RecordingSession({required this.source, required this.config, required RecordingBackend backend})
    : _backend = backend;

  /// Media source used by this recording session.
  final RecordingSource source;

  /// Configuration used by this recording session.
  final RecordingConfig config;

  /// Backend responsible for the actual recording work.
  final RecordingBackend _backend;

  /// Current recording state.
  RecordingState _state = const RecordingState();

  /// Reactive state controller.
  final BehaviorSubject<RecordingState> _stateSubject = BehaviorSubject<RecordingState>();

  /// Whether this session has been disposed.
  bool _disposed = false;

  /// Time at which recording actually started.
  DateTime? _startedAt;

  /// Current recording state.
  RecordingState get state {
    return _state;
  }

  /// Reactive stream of recording state changes.
  Stream<RecordingState> get states {
    return _stateSubject.stream;
  }

  /// Whether the recording lifecycle is currently active.
  bool get isActive {
    return _state.status.isActive;
  }

  /// Whether this session has completed recording.
  bool get isCompleted {
    return _state.status == RecordingStatus.completed;
  }

  /// Starts the recording session.
  ///
  /// The backend performs the actual recording operation. This session only
  /// coordinates lifecycle state and guards against invalid transitions.
  Future<void> start() async {
    _ensureNotDisposed();

    if (_state.status != RecordingStatus.idle) {
      throw StateError('RecordingSession can only be started from the idle state.');
    }

    if (!_backend.isAvailable) {
      const error = RecordingError.backendUnavailable(message: 'The recording backend is unavailable.');

      _setState(_state.copyWith(status: RecordingStatus.error, error: error));

      throw StateError(error.message);
    }

    _setState(_state.copyWith(status: RecordingStatus.starting));

    try {
      await _backend.start(source, config);

      _startedAt = clock.now();

      _setState(_state.copyWith(status: RecordingStatus.recording, duration: Duration.zero, bytesWritten: 0));
    } catch (error) {
      final recordingError = error is RecordingError
          ? error
          : RecordingError.failed(message: 'Failed to start recording.', cause: error);

      _setState(_state.copyWith(status: RecordingStatus.error, error: recordingError));

      rethrow;
    }
  }

  /// Stops the recording session.
  ///
  /// Returns the final result produced by the backend.
  Future<RecordingResult> stop() async {
    _ensureNotDisposed();

    if (_state.status != RecordingStatus.recording) {
      throw StateError('RecordingSession can only be stopped while recording.');
    }

    _setState(_state.copyWith(status: RecordingStatus.stopping));

    try {
      final result = await _backend.stop();

      _setState(
        _state.copyWith(
          status: result.success ? RecordingStatus.completed : RecordingStatus.error,
          duration: result.duration,
          bytesWritten: result.bytesWritten,
          error: result.error,
        ),
      );

      return result;
    } catch (error) {
      final recordingError = error is RecordingError
          ? error
          : RecordingError.failed(message: 'Failed to stop recording.', cause: error);

      _setState(_state.copyWith(status: RecordingStatus.error, error: recordingError));

      rethrow;
    }
  }

  /// Cancels the active recording session.
  Future<void> cancel() async {
    _ensureNotDisposed();

    if (!_state.status.isActive) {
      return;
    }

    try {
      await _backend.cancel();

      _setState(_state.copyWith(status: RecordingStatus.cancelled, duration: _elapsedDuration));
    } catch (error) {
      final recordingError = error is RecordingError
          ? error
          : RecordingError.failed(message: 'Failed to cancel recording.', cause: error);

      _setState(_state.copyWith(status: RecordingStatus.error, error: recordingError));

      rethrow;
    }
  }

  /// Updates runtime recording progress.
  ///
  /// This method is intended for backend or integration code that can provide
  /// more accurate progress information than the session clock alone.
  void updateProgress({Duration? duration, int? bytesWritten}) {
    _ensureNotDisposed();

    if (!_state.status.isActive) {
      return;
    }

    _setState(_state.copyWith(duration: duration, bytesWritten: bytesWritten));
  }

  /// Disposes this recording session.
  ///
  /// An active recording is cancelled before the backend is disposed.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    try {
      if (_state.status.isActive) {
        await _backend.cancel();
      }
    } finally {
      await _backend.dispose();
      await _stateSubject.close();
      _startedAt = null;
    }
  }

  /// Calculates the duration elapsed since recording started.
  Duration get _elapsedDuration {
    final startedAt = _startedAt;

    if (startedAt == null) {
      return _state.duration;
    }

    return clock.now().difference(startedAt);
  }

  /// Updates the current state and publishes it.
  void _setState(RecordingState state) {
    _state = state;

    if (!_stateSubject.isClosed) {
      _stateSubject.add(state);
    }
  }

  /// Ensures the session has not been disposed.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('RecordingSession has been disposed.');
    }
  }
}
