import 'package:equatable/equatable.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/platform/platform_capabilities.dart';
import 'package:media_core/policy/player_policy.dart';
import 'package:media_core/source/player_source.dart';

/// Runtime context of a player session.
///
/// [SessionContext] contains immutable dependencies
/// required during one playback session.
///
/// Responsibilities:
///
/// - provide session identity
/// - provide source information
/// - provide runtime policies
/// - provide platform capabilities
///
/// It does not:
///
/// - execute playback
/// - manage lifecycle
///
/// Those belong to:
///
/// - PlayerSession
/// - SessionController
final class SessionContext extends Equatable {
  /// Creates a session context.
  const SessionContext({
    required this.playerId,

    required this.sessionId,

    required this.generationId,

    required this.sourceId,

    required this.source,

    this.policy = const PlayerPolicy(),

    this.platform = const PlatformCapabilities(),
  });

  /// PlayerIdentity identity.
  final PlayerId playerId;

  /// Session identity.
  final SessionId sessionId;

  /// Current session generation.
  final GenerationId generationId;

  /// Source identity.
  final SourceId sourceId;

  /// Current media source.
  final PlayerSource source;

  /// PlayerIdentity policies.
  final PlayerPolicy policy;

  /// Platform capabilities.
  final PlatformCapabilities platform;

  /// Creates a new context with changed values.
  SessionContext copyWith({
    PlayerId? playerId,

    SessionId? sessionId,

    GenerationId? generationId,

    SourceId? sourceId,

    PlayerSource? source,

    PlayerPolicy? policy,

    PlatformCapabilities? platform,
  }) {
    return SessionContext(
      playerId: playerId ?? this.playerId,

      sessionId: sessionId ?? this.sessionId,

      generationId: generationId ?? this.generationId,

      sourceId: sourceId ?? this.sourceId,

      source: source ?? this.source,

      policy: policy ?? this.policy,

      platform: platform ?? this.platform,
    );
  }

  /// Whether context belongs to another generation.
  bool isGeneration(GenerationId id) {
    return generationId == id;
  }

  @override
  List<Object?> get props => [playerId, sessionId, generationId, sourceId, source, policy, platform];

  @override
  String toString() {
    return 'SessionContext('
        'player=$playerId, '
        'session=$sessionId, '
        'source=$sourceId'
        ')';
  }
}
