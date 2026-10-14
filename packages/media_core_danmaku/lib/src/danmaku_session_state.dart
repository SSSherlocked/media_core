import 'package:equatable/equatable.dart';

import 'package:media_core_danmaku/src/danmaku_failure.dart';

/// Lifecycle phase of one danmaku session.
enum DanmakuSessionPhase {
  /// No transport installed yet.
  idle,

  /// A handshake is in flight; the room is owned but not delivering.
  connecting,

  /// The transport is attached and delivering.
  connected,

  /// The transport lost the room and is repairing it.
  reconnecting,

  /// A previous session ended and nothing owns the room.
  closed,

  /// The last attempt failed; the room is not owned.
  failed,
}

/// Immutable snapshot of a danmaku session.
///
/// Responsibilities:
///
/// - report the lifecycle phase
/// - identify the room and transport the phase belongs to
/// - expose the last failure
///
/// It does not:
///
/// - connect or disconnect anything
/// - hold messages
/// - decide when to reconnect
///
/// Those responsibilities belong to:
///
/// - DanmakuController
/// - DanmakuTransport
final class DanmakuSessionState extends Equatable {
  /// A snapshot, defaulting to the idle phase with nothing installed.
  const DanmakuSessionState({
    this.phase = DanmakuSessionPhase.idle,
    this.roomKey,
    this.roomId,
    this.platform,
    this.transportId,
    this.generation = 0,
    this.failure,
    this.installed = false,
  });

  /// The lifecycle phase captured in this snapshot.
  final DanmakuSessionPhase phase;

  /// Session key of the room this snapshot describes, when one is owned.
  final String? roomKey;

  /// Platform room id, when one is known. Not the local session key: hosts
  /// display this one.
  final String? roomId;

  /// Platform identifier the room belongs to, when known.
  final String? platform;

  /// Transport identifier currently installed.
  final String? transportId;

  /// Increments for every accepted session. Lets a host drop events that
  /// belong to a session it has already moved on from.
  final int generation;

  /// Last failure, cleared when a new session is accepted.
  final DanmakuFailure? failure;

  /// Whether a transport has been installed at all.
  ///
  /// A controller with no transport cannot connect, and a host must not treat
  /// that as an error: several platforms have no chat integration, and the
  /// caller simply never installs one.
  final bool installed;

  /// Whether the session's transport is attached and delivering.
  bool get isConnected => phase == DanmakuSessionPhase.connected;

  /// Whether a handshake is currently in flight.
  bool get isConnecting => phase == DanmakuSessionPhase.connecting;

  /// Whether anything currently owns the room.
  bool get ownsRoom => roomKey != null && phase != DanmakuSessionPhase.closed && phase != DanmakuSessionPhase.failed;

  /// A copy with the given fields replaced; [clearFailure] and [clearRoom]
  /// drop those values instead of replacing them.
  DanmakuSessionState copyWith({
    DanmakuSessionPhase? phase,
    String? roomKey,
    String? roomId,
    String? platform,
    String? transportId,
    int? generation,
    DanmakuFailure? failure,
    bool? installed,
    bool clearFailure = false,
    bool clearRoom = false,
  }) {
    return DanmakuSessionState(
      phase: phase ?? this.phase,
      roomKey: clearRoom ? null : (roomKey ?? this.roomKey),
      roomId: clearRoom ? null : (roomId ?? this.roomId),
      platform: clearRoom ? null : (platform ?? this.platform),
      transportId: transportId ?? this.transportId,
      generation: generation ?? this.generation,
      failure: clearFailure ? null : (failure ?? this.failure),
      installed: installed ?? this.installed,
    );
  }

  @override
  List<Object?> get props => [phase, roomKey, roomId, platform, transportId, generation, failure, installed];

  @override
  String toString() =>
      'DanmakuSessionState(${phase.name}${roomKey == null ? '' : ' $roomKey'}'
      '${transportId == null ? '' : ' via $transportId'}, generation: $generation)';
}
