import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/session/session_state.dart';

part 'session_snapshot.freezed.dart';

/// Immutable snapshot of a player session.
///
/// [SessionSnapshot] represents the observable state of a session
/// at a specific point in time.
///
/// It is intended for:
///
/// - diagnostics
/// - state reconciliation
/// - debugging
/// - restoration
/// - testing
///
/// It does not:
///
/// - control playback
/// - manage lifecycle
/// - execute session operations
@freezed
abstract class SessionSnapshot with _$SessionSnapshot {
  /// Creates a session snapshot.
  const factory SessionSnapshot({
    /// PlayerIdentity identity.
    required PlayerId playerId,

    /// Session identity.
    required SessionId sessionId,

    /// Current generation identity.
    required GenerationId generationId,

    /// Time at which this snapshot was created.
    required DateTime timestamp,

    /// Current source identity.
    SourceId? sourceId,

    /// Current session state.
    @Default(SessionState.idle()) SessionState state,

    /// Current playback position.
    @Default(Duration.zero) Duration position,

    /// Total media duration.
    Duration? duration,

    /// Whether media is currently buffering.
    @Default(false) bool buffering,

    /// Whether playback has encountered an error.
    @Default(false) bool hasError,

    /// Error description, when available.
    String? errorMessage,
  }) = _SessionSnapshot;
}

/// Serialization helpers for [SessionSnapshot].
extension SessionSnapshotSerialization on SessionSnapshot {
  /// Returns the snapshot as a flat map, with identities and durations
  /// reduced to their serializable representations.
  Map<String, Object?> toMap() => {
    'playerId': playerId.value,
    'sessionId': sessionId.value,
    'generationId': generationId.value,
    'sourceId': sourceId?.value,
    'state': state.toString(),
    'positionMs': position.inMilliseconds,
    'durationMs': duration?.inMilliseconds,
    'buffering': buffering,
    'hasError': hasError,
    'errorMessage': errorMessage,
    'timestamp': timestamp.toIso8601String(),
  };
}
