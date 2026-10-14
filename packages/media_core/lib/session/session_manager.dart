import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/session/player_session.dart';
import 'package:media_core/session/session_context.dart';

/// Manages player sessions.
///
/// [SessionManager] owns creation and lookup of
/// runtime player sessions.
///
/// Responsibilities:
///
/// - create sessions
/// - store sessions
/// - remove sessions
/// - dispose sessions
///
/// It does not:
///
/// - execute playback
/// - control adapters
///
/// Those belong to:
///
/// - SessionController
/// - PlayerAdapter
final class SessionManager {
  /// Creates a session manager.
  SessionManager();

  final Map<SessionId, PlayerSession> _sessions = <SessionId, PlayerSession>{};

  /// Number of active sessions.
  int get length {
    return _sessions.length;
  }

  /// Whether manager contains a session.
  bool contains(SessionId id) {
    return _sessions.containsKey(id);
  }

  /// Creates and registers a session.
  PlayerSession create(SessionContext context) {
    final session = PlayerSession(context: context);

    _sessions[context.sessionId] = session;

    return session;
  }

  /// Gets a session by id.
  PlayerSession? get(SessionId id) {
    return _sessions[id];
  }

  /// Removes a session.
  Future<void> remove(SessionId id) async {
    final session = _sessions.remove(id);

    if (session != null) {
      await session.dispose();
    }
  }

  /// Gets all sessions.
  List<PlayerSession> get all {
    return List<PlayerSession>.unmodifiable(_sessions.values);
  }

  /// Removes sessions belonging to player.
  Future<void> removeByPlayer(PlayerId playerId) async {
    final targets = _sessions.values.where((session) => session.context.playerId == playerId).toList();

    for (final session in targets) {
      await remove(session.context.sessionId);
    }
  }

  /// Disposes all sessions.
  Future<void> dispose() async {
    final sessions = List<PlayerSession>.from(_sessions.values);

    _sessions.clear();

    for (final session in sessions) {
      await session.dispose();
    }
  }
}
