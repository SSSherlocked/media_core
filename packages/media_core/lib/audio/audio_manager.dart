import 'dart:async';
import 'package:media_core/audio/audio_focus.dart';
import 'package:media_core/audio/audio_session.dart';
import 'package:rxdart/rxdart.dart';

/// Coordinates the lifecycle and high-level state of audio playback.
///
/// [AudioManager] is intentionally platform-agnostic. It does not directly
/// access Android AudioManager, iOS AVAudioSession, Windows audio APIs, or
/// any other platform-specific audio framework.
///
/// Platform-specific behavior belongs behind [AudioFocus] and [AudioSession].
/// This keeps the media core reusable across Flutter platforms and makes the
/// manager straightforward to test.
///
/// Responsibilities:
/// - Coordinate audio-session activation/deactivation.
/// - Coordinate audio-focus acquisition/release.
/// - Track whether the audio subsystem is enabled.
/// - Expose reactive lifecycle state.
/// - Serialize asynchronous lifecycle transitions.
/// - Make disposal idempotent.
///
/// Non-responsibilities:
/// - Selecting a physical audio device.
/// - Implementing platform audio focus APIs.
/// - Applying volume to a native player.
/// - Deciding application-specific audio policy.
/// - Owning player instances.
///
/// The manager should normally be owned by the player/core coordinator and
/// have the same lifetime as the corresponding media engine.
final class AudioManager {
  /// Creates an audio manager.
  ///
  /// [focus] provides the platform-independent audio-focus abstraction.
  /// [session] provides the platform-independent audio-session abstraction.
  AudioManager({required AudioFocus focus, required AudioSession session}) : _focus = focus, _session = session;

  final AudioFocus _focus;
  final AudioSession _session;

  /// Serializes lifecycle operations.
  ///
  /// Audio focus and session activation are asynchronous on some platforms.
  /// Without serialization, calls such as `activate()`, `deactivate()`, and
  /// `dispose()` could race with each other.
  Future<void> _operation = Future<void>.value();

  /// Whether the manager has been disposed.
  bool _disposed = false;

  /// Whether audio management is currently enabled.
  bool _enabled = true;

  /// Whether an audio session is currently active.
  bool _active = false;

  /// Whether audio focus is currently held.
  bool _focused = false;

  final BehaviorSubject<bool> _enabledSubject = BehaviorSubject<bool>.seeded(true);

  final BehaviorSubject<bool> _activeSubject = BehaviorSubject<bool>.seeded(false);

  final BehaviorSubject<bool> _focusedSubject = BehaviorSubject<bool>.seeded(false);

  /// Emits whether audio management is enabled.
  ///
  /// This is a hot, replaying stream whose latest value is always available
  /// to new subscribers.
  ValueStream<bool> get enabled => _enabledSubject.stream;

  /// Emits whether the audio session is currently active.
  ValueStream<bool> get active => _activeSubject.stream;

  /// Emits whether audio focus is currently held.
  ValueStream<bool> get focused => _focusedSubject.stream;

  /// Returns the current enabled state synchronously.
  bool get isEnabled => _enabled;

  /// Returns whether the audio session is currently active.
  bool get isActive => _active;

  /// Returns whether audio focus is currently held.
  bool get hasFocus => _focused;

  /// Returns whether this manager has been disposed.
  bool get isDisposed => _disposed;

  /// Enables or disables audio management.
  ///
  /// Disabling an already-active manager first releases the currently held
  /// focus and deactivates the session. This prevents a disabled manager from
  /// accidentally retaining platform audio resources.
  ///
  /// Enabling does not automatically activate the audio session. Activation
  /// remains an explicit lifecycle operation.
  Future<void> setEnabled({required bool value}) {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (_enabled == value) {
        return;
      }

      if (!value) {
        await _deactivateInternal();
      }

      _enabled = value;
      _enabledSubject.add(value);
    });
  }

  /// Activates the audio subsystem.
  ///
  /// Activation is idempotent. Calling this method while already active has
  /// no effect.
  ///
  /// The operation first activates the audio session and then acquires audio
  /// focus. If focus acquisition fails after the session has been activated,
  /// the session is rolled back to the inactive state.
  Future<void> activate() {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!_enabled || (_active && _focused)) {
        return;
      }

      // A previous [abandonFocus] can leave the session active without focus.
      // Reuse it instead of activating twice, and only roll back the session
      // when this call is the one that activated it.
      final activatedSession = !_active;
      if (activatedSession) {
        await _session.activate();
        _active = true;
        _activeSubject.add(true);
      }

      if (_focused) {
        return;
      }

      try {
        await _focus.request();
      } catch (_) {
        if (activatedSession) {
          _active = false;
          _activeSubject.add(false);
          await _session.deactivate();
        }
        rethrow;
      }

      _focused = true;
      _focusedSubject.add(true);
    });
  }

  /// Releases audio focus and deactivates the audio session.
  ///
  /// The operation is idempotent and safe to call when the manager is already
  /// inactive.
  Future<void> deactivate() {
    return _enqueue(() async {
      _ensureNotDisposed();
      await _deactivateInternal();
    });
  }

  /// Releases only audio focus while keeping the audio session active.
  ///
  /// This is useful when playback temporarily loses the right to own audio
  /// focus but the underlying audio session should remain configured.
  Future<void> abandonFocus() {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!_focused) {
        return;
      }

      await _focus.abandon();

      _focused = false;
      _focusedSubject.add(false);
    });
  }

  /// Requests audio focus again for an active session.
  ///
  /// If the session is inactive, this method activates the complete audio
  /// subsystem instead.
  Future<void> requestFocus() {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!_enabled) {
        return;
      }

      // Activating the session here makes this method able to bootstrap the
      // whole subsystem, so a failed focus request has to undo it: otherwise
      // the manager would report an active session that nobody holds focus for.
      final activatedSession = !_active;
      if (activatedSession) {
        await _session.activate();
        _active = true;
        _activeSubject.add(true);
      }

      if (_focused) {
        return;
      }

      try {
        await _focus.request();
      } catch (_) {
        if (activatedSession) {
          _active = false;
          _activeSubject.add(false);
          await _session.deactivate();
        }
        rethrow;
      }

      _focused = true;
      _focusedSubject.add(true);
    });
  }

  /// Executes an operation while preserving the manager's lifecycle ordering.
  ///
  /// Every asynchronous lifecycle transition is chained onto the previous
  /// one. If an earlier operation fails, the queue is reset so a later
  /// operation can still proceed.
  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operation.then((_) => operation());

    _operation = next.catchError((Object _) {});

    return next;
  }

  /// Deactivates the audio subsystem without checking the disposed state.
  ///
  /// This is used internally by both [deactivate] and [setEnabled].
  Future<void> _deactivateInternal() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    if (_focused) {
      try {
        await _focus.abandon();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }

      _focused = false;
      _focusedSubject.add(false);
    }

    if (_active) {
      try {
        await _session.deactivate();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }

      _active = false;
      _activeSubject.add(false);
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  /// Throws when a public lifecycle operation is attempted after disposal.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('AudioManager has already been disposed.');
    }
  }

  /// Releases all resources owned by this manager.
  ///
  /// Disposal is idempotent. The manager first waits for all previously
  /// queued lifecycle operations, then releases focus and the audio session,
  /// and finally closes its reactive streams.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      await _operation;
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    try {
      await _deactivateInternal();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    await _enabledSubject.close();
    await _activeSubject.close();
    await _focusedSubject.close();

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}
