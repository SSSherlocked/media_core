import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/session/session_state.dart';

/// Represents an event emitted by a player session.
///
/// Session events describe changes happening during
/// a session lifecycle.
///
/// They are intended for:
///
/// - event bus
/// - diagnostics
/// - coordinator
/// - logging
///
/// They do not:
///
/// - execute operations
/// - modify session state
///
/// Those belong to:
///
/// - SessionController
/// - PlayerSession
final class SessionEvent extends Equatable {
  /// Creates a session event.
  const SessionEvent({
    required this.sessionId,
    required this.type,
    required this.timestamp,
    this.state,
    this.sourceId,
    this.message,
  });

  /// Creates session created event.
  factory SessionEvent.created(SessionId sessionId) {
    return SessionEvent(sessionId: sessionId, type: SessionEventType.created, timestamp: clock.now());
  }

  /// Creates state changed event.
  factory SessionEvent.stateChanged(SessionId sessionId, SessionState state) {
    return SessionEvent(
      sessionId: sessionId,
      type: SessionEventType.stateChanged,
      state: state,
      timestamp: clock.now(),
    );
  }

  /// Creates source changed event.
  factory SessionEvent.sourceChanged(SessionId sessionId, SourceId sourceId) {
    return SessionEvent(
      sessionId: sessionId,
      type: SessionEventType.sourceChanged,
      sourceId: sourceId,
      timestamp: clock.now(),
    );
  }

  /// Creates error event.
  factory SessionEvent.error(SessionId sessionId, String message) {
    return SessionEvent(sessionId: sessionId, type: SessionEventType.error, message: message, timestamp: clock.now());
  }

  /// Creates disposed event.
  factory SessionEvent.disposed(SessionId sessionId) {
    return SessionEvent(sessionId: sessionId, type: SessionEventType.disposed, timestamp: clock.now());
  }

  /// Session identity.
  final SessionId sessionId;

  /// Event type.
  final SessionEventType type;

  /// Related session state.
  final SessionState? state;

  /// Related source.
  final SourceId? sourceId;

  /// Optional message.
  final String? message;

  /// Event timestamp.
  final DateTime timestamp;

  @override
  List<Object?> get props => [sessionId, type, state, sourceId, message, timestamp];

  @override
  String toString() {
    return 'SessionEvent('
        'type=$type, '
        'session=$sessionId'
        ')';
  }
}

/// Types of session events.
enum SessionEventType {
  /// Session created.
  created,

  /// Session state changed.
  stateChanged,

  /// Media source changed.
  sourceChanged,

  /// Session error occurred.
  error,

  /// Session disposed.
  disposed,
}
