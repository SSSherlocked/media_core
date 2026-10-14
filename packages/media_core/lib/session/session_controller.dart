import 'dart:async';

import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/session/player_session.dart';
import 'package:media_core/session/session_generation.dart';
import 'package:media_core/session/session_state.dart';

/// Controls a player session lifecycle.
///
/// [SessionController] coordinates operations on a
/// [PlayerSession].
///
/// Responsibilities:
///
/// - session state transitions
/// - generation management
/// - lifecycle operations
///
/// It does not:
///
/// - create player instances
/// - access media backend directly
///
/// Those belong to:
///
/// - Factory
/// - Adapter
final class SessionController {
  /// Creates a session controller.
  SessionController(this.session);

  /// Managed session.
  final PlayerSession session;

  /// Current session state.
  SessionState get state {
    return session.state;
  }

  /// Current generation.
  SessionGeneration get generation {
    return session.generation;
  }

  /// Opens session.
  ///
  /// This only updates session lifecycle.
  /// Actual media opening belongs to adapter.
  Future<void> open() async {
    clearError();
    session.updateState(const SessionState.opening());

    await Future<void>.delayed(Duration.zero);

    session.updateState(const SessionState.ready());
  }

  /// Starts playback state.
  ///
  /// A session that is `stopped`, `completed` or `error` can be played again:
  /// those statuses describe what happened to the previous run, and the caller
  /// resuming playback is exactly the event that supersedes them. Refusing here
  /// silently left the session reporting `stopped`/`error` while the adapter
  /// was playing - the handle, the session and the engine disagreeing about one
  /// player.
  Future<void> play() async {
    if (!_canTransitionToPlayback) {
      return;
    }

    session.updateState(const SessionState.playing());
  }

  /// Pauses playback state.
  Future<void> pause() async {
    if (!session.state.active) {
      return;
    }

    session.updateState(const SessionState.paused());
  }

  /// Whether a play command may move the session into `playing`.
  ///
  /// `idle`/`opening` mean "no source yet" (the adapter has nothing to play),
  /// `disposed` means the session is gone; everything else may play.
  bool get _canTransitionToPlayback {
    switch (session.state.status) {
      case SessionStatus.idle:
      case SessionStatus.opening:
      case SessionStatus.disposed:
        return false;

      case SessionStatus.ready:
      case SessionStatus.playing:
      case SessionStatus.paused:
      case SessionStatus.buffering:
      case SessionStatus.stopped:
      case SessionStatus.completed:
      case SessionStatus.error:
        return true;
    }
  }

  /// Stops session.
  Future<void> stop() async {
    session.updateState(const SessionState.stopped());
  }

  /// Marks session as buffering.
  ///
  /// [buffering] false ends the condition and restores the status the session
  /// was in before it - it must not *enter* buffering, which is what happened
  /// when the ended event was forwarded blindly: the session then sat in
  /// `buffering` (with `loading == true`) after the stream had recovered.
  void setBuffering({required bool buffering}) {
    if (buffering) {
      if (session.state.active && session.state.status != SessionStatus.disposed) {
        session.updateState(const SessionState.buffering());
      }

      return;
    }

    if (session.state.status != SessionStatus.buffering) {
      return;
    }

    session.updateState(const SessionState.playing());
  }

  /// Marks session as completed.
  void complete() {
    session.updateState(const SessionState.completed());
  }

  /// Reports session error.
  void error(String message) {
    session
      ..errorMessage = message
      ..updateState(const SessionState.error());
  }

  /// Clears the recorded error.
  ///
  /// Called when a new source opens: the previous failure belongs to the
  /// previous source, and keeping it would label a healthy session as failed.
  void clearError() {
    session.errorMessage = null;
  }

  /// Records the playback facts the session reports in its snapshots.
  void updateTimeline({Duration? position, Duration? duration, bool? buffering}) {
    session.updateTimeline(position: position, duration: duration, buffering: buffering);
  }

  /// Creates a new playback generation.
  GenerationId recreateGeneration() {
    return session.nextGeneration().id;
  }

  /// Checks generation validity.
  bool isCurrentGeneration(GenerationId id) {
    return session.isCurrentGeneration(id);
  }

  /// Releases session.
  Future<void> dispose() async {
    await session.dispose();
  }
}
