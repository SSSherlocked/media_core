import 'package:media_core/recording/recording_backend.dart';
import 'package:media_core/recording/recording_config.dart';
import 'package:media_core/recording/recording_result.dart';
import 'package:media_core/recording/recording_session.dart';
import 'package:media_core/recording/recording_source.dart';

/// Coordinates recording sessions for the media core.
///
/// A [RecordingManager] is the high-level owner of recording lifecycles.
/// It creates at most one active [RecordingSession] and delegates the actual
/// recording work to the configured [RecordingBackend].
///
/// Responsibilities:
///
/// - own the recording backend
/// - create recording sessions
/// - enforce a single active recording session
/// - start and stop recording
/// - cancel active recording
/// - manage recording session lifetime
///
/// It does not:
///
/// - encode media
/// - write media data directly
/// - implement platform-specific recording APIs
/// - provide backend-specific recording behavior
///
/// Those responsibilities belong to:
///
/// - RecordingBackend
/// - RecordingSession
/// - platform-specific recording implementations
final class RecordingManager {
  /// Creates a recording manager.
  RecordingManager({required RecordingBackend backend, RecordingConfig config = const RecordingConfig()})
    : _backend = backend,
      _config = config;

  /// Recording backend used by newly created sessions.
  final RecordingBackend _backend;

  /// Default configuration for newly created recording sessions.
  RecordingConfig _config;

  /// Currently active recording session.
  RecordingSession? _activeSession;

  /// Whether this manager has been disposed.
  bool _disposed = false;

  /// Current default recording configuration.
  RecordingConfig get config {
    return _config;
  }

  /// Currently active recording session.
  ///
  /// Returns `null` when no recording is active.
  RecordingSession? get activeSession {
    return _activeSession;
  }

  /// Whether a recording session is currently active.
  bool get isRecording {
    return _activeSession?.isActive ?? false;
  }

  /// Updates the default recording configuration.
  ///
  /// The new configuration applies only to subsequently created recording
  /// sessions. An existing session keeps its original configuration.
  void updateConfig(RecordingConfig config) {
    _ensureNotDisposed();

    _config = config;
  }

  /// Starts a new recording session.
  ///
  /// Throws [StateError] when another recording session is already active.
  Future<void> start({required RecordingSource source, RecordingConfig? config}) async {
    _ensureNotDisposed();

    if (_activeSession != null) {
      throw StateError('A recording session is already active.');
    }

    final session = RecordingSession(source: source, config: config ?? _config, backend: _backend);

    _activeSession = session;

    try {
      await session.start();
    } catch (_) {
      _activeSession = null;
      await session.dispose();
      rethrow;
    }
  }

  /// Stops the active recording session.
  ///
  /// Returns the final recording result.
  Future<RecordingResult> stop() async {
    _ensureNotDisposed();

    final session = _activeSession;

    if (session == null) {
      throw StateError('No recording session is active.');
    }

    try {
      return await session.stop();
    } finally {
      _activeSession = null;
      await session.dispose();
    }
  }

  /// Cancels the active recording session.
  ///
  /// Returns `false` when there is no active recording session.
  Future<bool> cancel() async {
    _ensureNotDisposed();

    final session = _activeSession;

    if (session == null) {
      return false;
    }

    try {
      await session.cancel();
      return true;
    } finally {
      _activeSession = null;
      await session.dispose();
    }
  }

  /// Disposes the recording manager.
  ///
  /// An active recording is cancelled before the backend is released.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    final session = _activeSession;
    _activeSession = null;

    if (session != null) {
      try {
        await session.cancel();
      } finally {
        await session.dispose();
      }
    } else {
      await _backend.dispose();
    }
  }

  /// Ensures the manager has not been disposed.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('RecordingManager has been disposed.');
    }
  }
}
