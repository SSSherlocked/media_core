import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/policy/player_policy.dart';
import 'package:media_core/session/player_session.dart';
import 'package:media_core/session/session_context.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/testing/test_source_factory.dart';

/// Builds [PlayerSession] and [SessionContext] values for tests.
final class TestSessionFactory {
  const TestSessionFactory._();

  /// Builds a session context for a http mp4 source.
  static SessionContext context({
    String playerId = 'test-player',
    String sessionId = 'test-session',
    String generationId = 'gen-1',
    PlayerPolicy policy = const PlayerPolicy(),
  }) {
    final source = TestSourceFactory.httpMp4();
    return SessionContext(
      playerId: PlayerId(playerId),
      sessionId: SessionId(sessionId),
      generationId: GenerationId(generationId),
      sourceId: source.id,
      source: source,
      policy: policy,
    );
  }

  /// Builds a session context for an arbitrary [source].
  static SessionContext contextFor(
    PlayerSource source, {
    String playerId = 'test-player',
    String sessionId = 'test-session',
    String generationId = 'gen-1',
  }) {
    return SessionContext(
      playerId: PlayerId(playerId),
      sessionId: SessionId(sessionId),
      generationId: GenerationId(generationId),
      sourceId: source.id,
      source: source,
    );
  }

  /// Builds a ready to use session.
  static PlayerSession session({String playerId = 'test-player', String sessionId = 'test-session'}) {
    return PlayerSession(
      context: context(playerId: playerId, sessionId: sessionId),
    );
  }

  /// Builds [count] sessions with distinct ids.
  static List<PlayerSession> sessions(int count) {
    return List<PlayerSession>.generate(
      count,
      (index) => session(playerId: 'player-$index', sessionId: 'session-$index'),
      growable: false,
    );
  }
}
