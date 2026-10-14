import 'package:clock/clock.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/session/session_context.dart';
import 'package:media_core/session/session_generation.dart';
import 'package:media_core/session/session_snapshot.dart';
import 'package:media_core/session/session_state.dart';
import 'package:rxdart/rxdart.dart';

/// Represents one playback lifecycle session.
///
/// A [PlayerSession] owns one logical playback lifecycle.
///
/// Responsibilities:
///
/// - maintain session state
/// - manage generation changes
/// - expose session snapshots
///
/// It does not:
///
/// - create adapters
/// - execute backend commands
///
/// Those belong to:
///
/// - PlayerFactory
/// - PlayerAdapter
/// - PlaybackController
final class PlayerSession {
  /// Creates a player session.
  PlayerSession({required SessionContext context})
    : _context = context,
      _generation = SessionGeneration.initial(),
      _state = const SessionState.idle() {
    _snapshotController.add(_createSnapshot());
  }

  /// Current session context.
  SessionContext get context {
    return _context;
  }

  /// Current generation.
  SessionGeneration get generation {
    return _generation;
  }

  /// Current session state.
  SessionState get state {
    return _state;
  }

  /// Snapshot stream.
  Stream<SessionSnapshot> get snapshots {
    return _snapshotController.stream;
  }

  /// Latest snapshot.
  SessionSnapshot get snapshot {
    return _createSnapshot();
  }

  SessionContext _context;

  SessionGeneration _generation;

  SessionState _state;

  final BehaviorSubject<SessionSnapshot> _snapshotController = BehaviorSubject<SessionSnapshot>();

  /// Updates session state.
  void updateState(SessionState state) {
    _state = state;

    _emitSnapshot();
  }

  /// Moves to next generation.
  SessionGeneration nextGeneration() {
    _generation = _generation.next();

    _emitSnapshot();

    return _generation;
  }

  /// Replaces session context.
  void updateContext(SessionContext context) {
    _context = context;

    _emitSnapshot();
  }

  /// Checks whether generation is current.
  bool isCurrentGeneration(GenerationId id) {
    return _generation.id == id;
  }

  /// Latest playback position reported by the runtime.
  Duration _position = Duration.zero;

  /// Latest media duration reported by the runtime.
  Duration? _duration;

  /// Whether the runtime reports a buffering condition.
  bool _buffering = false;

  /// Message of the last error, cleared when the session opens again.
  String? errorMessage;

  /// Records the playback facts the session reports but does not own.
  ///
  /// The runtime feeds these in: position and duration belong to the
  /// playback controller, while the session is the one place a consumer can
  /// ask for "everything about this session". Without them the snapshot
  /// published here contradicted itself - `hasError == false` beside a state
  /// that was `error`, and a position that was always zero.
  void updateTimeline({Duration? position, Duration? duration, bool? buffering}) {
    if (position != null) {
      _position = position;
    }

    if (duration != null) {
      _duration = duration;
    }

    if (buffering != null) {
      _buffering = buffering;
    }
  }

  /// Creates snapshot.
  SessionSnapshot _createSnapshot() {
    return SessionSnapshot(
      playerId: _context.playerId,

      sessionId: _context.sessionId,

      generationId: _generation.id,

      sourceId: _context.sourceId,

      state: _state,

      position: _position,

      duration: _duration,

      buffering: _buffering,

      hasError: _state.hasError,

      errorMessage: errorMessage,

      timestamp: clock.now(),
    );
  }

  /// Emits snapshot.
  void _emitSnapshot() {
    _snapshotController.add(_createSnapshot());
  }

  /// Disposes session.
  Future<void> dispose() async {
    _state = const SessionState.disposed();

    _emitSnapshot();

    await _snapshotController.close();
  }
}
