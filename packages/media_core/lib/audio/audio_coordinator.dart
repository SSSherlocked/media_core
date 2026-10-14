import 'dart:async';
import 'package:media_core/audio/audio_focus.dart';
import 'package:media_core/audio/audio_focus_state.dart';
import 'package:media_core/audio/audio_manager.dart' show AudioManager;
import 'package:media_core/audio/audio_session.dart';
import 'package:media_core/audio/audio_session_state.dart';
import 'package:rxdart/rxdart.dart';

/// Coordinates the relationship between an audio session and audio focus.
///
/// [AudioCoordinator] sits one level above [AudioFocus] and [AudioSession].
/// It defines the lifecycle ordering required by the media core without
/// depending on any platform-specific audio API.
///
/// The coordinator is deliberately separate from [AudioManager]:
///
/// - [AudioFocus] owns the focus abstraction.
/// - [AudioSession] owns the session abstraction.
/// - [AudioCoordinator] coordinates their state and lifecycle.
/// - [AudioManager] exposes the higher-level audio subsystem lifecycle.
///
/// The coordinator is useful when focus and session implementations can emit
/// independent asynchronous events and those events must be reconciled into a
/// consistent core state.
final class AudioCoordinator {
  /// Creates an audio coordinator.
  AudioCoordinator({required AudioFocus focus, required AudioSession session}) : _focus = focus, _session = session;

  final AudioFocus _focus;
  final AudioSession _session;

  Future<void> _operation = Future<void>.value();

  bool _disposed = false;
  bool _sessionActive = false;
  bool _focusActive = false;

  int _generation = 0;

  final BehaviorSubject<AudioFocusState> _focusStateSubject = BehaviorSubject<AudioFocusState>.seeded(
    const AudioFocusState.idle(),
  );

  final BehaviorSubject<AudioSessionState> _sessionStateSubject = BehaviorSubject<AudioSessionState>.seeded(
    const AudioSessionState.inactive(),
  );

  /// Current audio-focus state.
  ValueStream<AudioFocusState> get focusState => _focusStateSubject.stream;

  /// Current audio-session state.
  ValueStream<AudioSessionState> get sessionState => _sessionStateSubject.stream;

  /// Returns whether the audio session is active.
  bool get isSessionActive => _sessionActive;

  /// Returns whether audio focus is currently held.
  bool get hasFocus => _focusActive;

  /// Returns the current lifecycle generation.
  int get generation => _generation;

  /// Returns whether this coordinator has been disposed.
  bool get isDisposed => _disposed;

  /// Activates the audio session and then acquires audio focus.
  ///
  /// The ordering is intentional: the session must be active before focus is
  /// requested. If focus acquisition fails, the session is rolled back.
  Future<void> activate() {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (_sessionActive && _focusActive) {
        return;
      }

      final generation = ++_generation;

      if (!_sessionActive) {
        _sessionStateSubject.add(AudioSessionState.activating(generation: generation));

        try {
          await _session.activate();
          _sessionActive = true;

          _sessionStateSubject.add(AudioSessionState.active(generation: generation));
        } catch (error) {
          _sessionStateSubject.add(AudioSessionState.error(generation: generation));
          rethrow;
        }
      }

      if (!_focusActive) {
        _focusStateSubject.add(AudioFocusState.requesting(generation: generation));

        try {
          await _focus.request();
          _focusActive = true;

          _focusStateSubject.add(AudioFocusState.focused(generation: generation));
        } catch (error) {
          _focusStateSubject.add(AudioFocusState.error(generation: generation));

          await _deactivateSessionAfterFocusFailure(generation);
          rethrow;
        }
      }
    });
  }

  /// Deactivates focus and then the audio session.
  ///
  /// Focus is released before the session is deactivated so that native audio
  /// resources are relinquished in a deterministic order.
  Future<void> deactivate() {
    return _enqueue(() async {
      _ensureNotDisposed();
      await _deactivateInternal();
    });
  }

  /// Requests audio focus while preserving an already active session.
  ///
  /// If the session is inactive, the complete [activate] lifecycle is used.
  Future<void> requestFocus() {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!_sessionActive) {
        await _activateSession();
      }

      if (_focusActive) {
        return;
      }

      final generation = ++_generation;

      _focusStateSubject.add(AudioFocusState.requesting(generation: generation));

      try {
        await _focus.request();
        _focusActive = true;

        _focusStateSubject.add(AudioFocusState.focused(generation: generation));
      } catch (error) {
        _focusStateSubject.add(AudioFocusState.error(generation: generation));
        rethrow;
      }
    });
  }

  /// Abandons focus while keeping the audio session active.
  Future<void> abandonFocus() {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!_focusActive) {
        return;
      }

      final generation = ++_generation;

      try {
        await _focus.abandon();
        _focusActive = false;

        _focusStateSubject.add(AudioFocusState.abandoned(generation: generation));
      } catch (error) {
        _focusStateSubject.add(AudioFocusState.error(generation: generation));
        rethrow;
      }
    });
  }

  /// Updates the focus state when an external platform event is received.
  ///
  /// This method does not call the platform focus API. It only reconciles an
  /// externally observed state into the core state model.
  ///
  /// [state] is ignored when its generation is older than the current
  /// lifecycle generation.
  void updateFocusState(AudioFocusState state) {
    _ensureNotDisposed();

    if (state.generation < _generation) {
      return;
    }

    if (state.generation > _generation) {
      _generation = state.generation;
    }

    _focusActive = state.hasFocus;
    _focusStateSubject.add(state);
  }

  /// Updates the session state when an external platform event is received.
  ///
  /// This method only updates the core representation; it does not invoke
  /// native session APIs.
  void updateSessionState(AudioSessionState state) {
    _ensureNotDisposed();

    if (state.generation < _generation) {
      return;
    }

    if (state.generation > _generation) {
      _generation = state.generation;
    }

    _sessionActive = state.isActive;
    _sessionStateSubject.add(state);
  }

  Future<void> _activateSession() async {
    final generation = ++_generation;

    _sessionStateSubject.add(AudioSessionState.activating(generation: generation));

    try {
      await _session.activate();
      _sessionActive = true;

      _sessionStateSubject.add(AudioSessionState.active(generation: generation));
    } catch (error) {
      _sessionStateSubject.add(AudioSessionState.error(generation: generation));
      rethrow;
    }
  }

  Future<void> _deactivateSessionAfterFocusFailure(int generation) async {
    if (!_sessionActive) {
      return;
    }

    try {
      _sessionStateSubject.add(AudioSessionState.deactivating(generation: generation));

      await _session.deactivate();
      _sessionActive = false;

      _sessionStateSubject.add(AudioSessionState.inactive(generation: generation));
    } on Object catch (_) {
      _sessionStateSubject.add(AudioSessionState.error(generation: generation));
    }
  }

  Future<void> _deactivateInternal() async {
    final generation = ++_generation;

    Object? firstError;
    StackTrace? firstStackTrace;

    if (_focusActive) {
      try {
        await _focus.abandon();
        _focusActive = false;

        _focusStateSubject.add(AudioFocusState.abandoned(generation: generation));
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;

        _focusStateSubject.add(AudioFocusState.error(generation: generation));
      }
    }

    if (_sessionActive) {
      try {
        _sessionStateSubject.add(AudioSessionState.deactivating(generation: generation));

        await _session.deactivate();
        _sessionActive = false;

        _sessionStateSubject.add(AudioSessionState.inactive(generation: generation));
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;

        _sessionStateSubject.add(AudioSessionState.error(generation: generation));
      }
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  /// Serializes asynchronous lifecycle operations.
  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operation.then((_) => operation());

    _operation = next.catchError((Object _) {});

    return next;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('AudioCoordinator has already been disposed.');
    }
  }

  /// Disposes the coordinator and releases all owned resources.
  ///
  /// Disposal is idempotent. The coordinator waits for previously queued
  /// operations before releasing the active focus/session resources.
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

    _focusStateSubject.add(AudioFocusState.disposed(generation: _generation));

    _sessionStateSubject.add(AudioSessionState.disposed(generation: _generation));

    await _focusStateSubject.close();
    await _sessionStateSubject.close();

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}
