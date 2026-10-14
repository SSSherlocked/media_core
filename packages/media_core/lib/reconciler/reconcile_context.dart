import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';

/// Context information used during reconciliation.
final class ReconcileContext {
  /// Creates a reconciliation context describing which player, session and
  /// reason the reconciliation is for.
  const ReconcileContext({this.playerId, this.sessionId, this.reason});

  /// Related player.
  final PlayerId? playerId;

  /// Related session.
  final SessionId? sessionId;

  /// Reason of reconciliation.
  final String? reason;

  /// Returns a copy with the given fields replaced.
  ReconcileContext copyWith({PlayerId? playerId, SessionId? sessionId, String? reason}) {
    return ReconcileContext(
      playerId: playerId ?? this.playerId,
      sessionId: sessionId ?? this.sessionId,
      reason: reason ?? this.reason,
    );
  }
}
