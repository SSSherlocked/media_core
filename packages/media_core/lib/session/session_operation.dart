import 'package:equatable/equatable.dart';
import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/identity/session_id.dart';

/// Represents an operation executed on a player session.
///
/// A [SessionOperation] describes one action performed
/// during a session lifecycle.
///
/// It does not:
///
/// - execute the operation
/// - manage async execution
/// - retry failures
///
/// Those belong to:
///
/// - SessionController
/// - OperationTracker
final class SessionOperation extends Equatable {
  /// Creates a session operation.
  const SessionOperation({
    required this.id,
    required this.sessionId,
    required this.type,
    this.state = SessionOperationState.pending,
    this.error,
    this.startedAt,
    this.completedAt,
  });

  /// Operation identity.
  final OperationId id;

  /// Related session identity.
  final SessionId sessionId;

  /// Operation type.
  final SessionOperationType type;

  /// Current operation state.
  final SessionOperationState state;

  /// Error message.
  final String? error;

  /// Start time.
  final DateTime? startedAt;

  /// Completion time.
  final DateTime? completedAt;

  /// Whether operation is running.
  bool get running {
    return state == SessionOperationState.running;
  }

  /// Whether operation completed successfully.
  bool get completed {
    return state == SessionOperationState.completed;
  }

  /// Whether operation failed.
  bool get failed {
    return state == SessionOperationState.failed;
  }

  /// Creates updated operation.
  SessionOperation copyWith({SessionOperationState? state, String? error, DateTime? startedAt, DateTime? completedAt}) {
    return SessionOperation(
      id: id,
      sessionId: sessionId,
      type: type,
      state: state ?? this.state,
      error: error ?? this.error,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  List<Object?> get props => [id, sessionId, type, state, error, startedAt, completedAt];

  @override
  String toString() {
    return 'SessionOperation('
        'type=$type, '
        'state=$state'
        ')';
  }
}

/// Type of session operation.
enum SessionOperationType {
  /// Open media source.
  open,

  /// Start playback.
  play,

  /// Pause playback.
  pause,

  /// Stop playback.
  stop,

  /// Change media source.
  switchSource,

  /// Reload current source.
  reload,

  /// Release session.
  release,
}

/// State of session operation.
enum SessionOperationState {
  /// Waiting to execute.
  pending,

  /// Currently running.
  running,

  /// Finished successfully.
  completed,

  /// Failed.
  failed,

  /// Cancelled.
  cancelled,
}
