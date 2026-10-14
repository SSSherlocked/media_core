import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/geometry/geometry_snapshot.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/lifecycle/lifecycle_snapshot.dart';
import 'package:media_core/playback/playback_snapshot.dart';
import 'package:media_core/recovery/recovery_snapshot.dart';
import 'package:media_core/session/session_snapshot.dart';
import 'package:media_core/source/player_source.dart';

/// Transient aggregate snapshot of one `PlayerHandle`.
///
/// Built on demand from the handle's own modules and the runtime's
/// controllers. No stream subscription, no cache, no history — the
/// caller reads the current point-in-time values once and lets the
/// object go.
///
/// Used for:
///
/// - diagnostics and debug overlays
/// - one-shot reads that would otherwise touch five getters
/// - logging a full handle state in a single call
///
/// Does not:
///
/// - control playback
/// - mutate any state
/// - subscribe to any stream
/// - observe future changes
final class PlayerHandleSnapshot extends Equatable {
  /// Creates a snapshot.
  ///
  /// [timestamp] defaults to `clock.now()`, which keeps tests
  /// deterministic when they override the clock.
  PlayerHandleSnapshot({
    required this.playerId,
    required this.sessionId,
    required this.generationId,
    required this.backendId,
    required this.source,
    required this.session,
    required this.playback,
    required this.geometry,
    required this.lifecycle,
    required this.recovery,
    required this.disposed,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? clock.now();

  /// PlayerIdentity identity.
  final PlayerId playerId;

  /// Session identity.
  final SessionId sessionId;

  /// Playback generation identity.
  final GenerationId generationId;

  /// Identifier of the backend currently attached.
  final String backendId;

  /// Currently open source, or `null` before the first open.
  final PlayerSource? source;

  /// Session snapshot.
  final SessionSnapshot session;

  /// Playback snapshot.
  final PlaybackSnapshot playback;

  /// Geometry snapshot.
  final GeometrySnapshot geometry;

  /// Lifecycle snapshot.
  final LifecycleSnapshot lifecycle;

  /// Recovery snapshot.
  final RecoverySnapshot recovery;

  /// Whether the handle has been disposed.
  final bool disposed;

  /// Time at which this snapshot was taken.
  final DateTime timestamp;

  /// Convenience: the video is currently playing.
  bool get isPlaying => playback.isPlaying;

  /// Convenience: the video is currently buffering.
  bool get isBuffering => playback.isBuffering;

  /// Convenience: the video source carries a readable resolution.
  bool get hasGeometry => geometry.hasVideo && geometry.hasDisplay;

  /// Convenience: aspect ratio of the current source, or `0` when
  /// geometry is not yet available.
  double get aspectRatio => geometry.aspectRatio;

  /// Convenience: `true` when the source is portrait after rotation.
  bool get isPortrait => geometry.isPortrait;

  /// Converts to a flat map for logging.
  ///
  /// Nested snapshots are collapsed to their own `toMap()` output.
  /// Kept out of `==` / `hashCode`; it is a diagnostic aid only.
  Map<String, Object?> toMap() {
    return {
      'playerId': playerId.value,
      'sessionId': sessionId.value,
      'generationId': generationId.value,
      'backendId': backendId,
      'source': source?.uri.toString(),
      'session': session.toMap(),
      'playback': playback.toMap(),
      'geometry': geometry.toMap(),
      'lifecycle': lifecycle.toMap(),
      'recovery': recovery.toMap(),
      'disposed': disposed,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    playerId,
    sessionId,
    generationId,
    backendId,
    source,
    session,
    playback,
    geometry,
    lifecycle,
    recovery,
    disposed,
    timestamp,
  ];

  @override
  String toString() {
    return 'PlayerHandleSnapshot('
        'player=$playerId, '
        'backend=$backendId, '
        'session=$session, '
        'playback=$playback, '
        'geometry=$geometry, '
        'lifecycle=$lifecycle, '
        'recovery=$recovery, '
        'disposed=$disposed)';
  }
}
