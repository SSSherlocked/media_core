import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';

/// Context for preload execution.
final class PreloadContext {
  /// Creates a preload context, optionally tagged with the originating
  /// player and session.
  const PreloadContext({this.playerId, this.sessionId});

  /// The player that requested the preload, when known.
  final PlayerId? playerId;

  /// The playback session the preload belongs to, when known.
  final SessionId? sessionId;
}
