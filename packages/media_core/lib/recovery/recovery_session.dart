import 'package:equatable/equatable.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/recovery/recovery_failure.dart';
import 'package:media_core/source/player_source.dart';

/// Everything the ladder needs to know to make a recovery decision.
///
/// A session is the immutable decision context of one ladder run: what
/// failed ([failure]), what is playing right now (source, position, play
/// state, volume, rate), and what could be tried instead
/// ([sourceCandidates] and [backendCandidates]).
///
/// It is built by the recovery target, because only the target owns the
/// live playback state, and handed back to it with every step so the
/// target can restore that state after the step succeeded.
///
/// It carries no policy and no execution: it is the input to a decision,
/// not the decision.
final class RecoverySession extends Equatable {
  /// Creates a session.
  const RecoverySession({
    required this.failure,
    this.source,
    this.sourceCandidates = const <PlayerSource>[],
    this.backendCandidates = const <PlayerAdapterRegistration>[],
    this.position = Duration.zero,
    this.wasPlaying = false,
    this.volume = 1.0,
    this.rate = 1.0,
    this.backendId,
    this.generationId,
    this.attempt = 0,
  });

  /// Failure that opened this session.
  final RecoveryFailure failure;

  /// Source currently playing, when one is open.
  final PlayerSource? source;

  /// Alternative sources to try, best first.
  ///
  /// Excludes the source currently playing.
  final List<PlayerSource> sourceCandidates;

  /// Alternative backends to try, best first.
  ///
  /// Excludes the backend currently attached.
  final List<PlayerAdapterRegistration> backendCandidates;

  /// Playback position to restore after a successful step.
  final Duration position;

  /// Whether playback should be running after a successful step.
  ///
  /// Taken from the caller's declared play intent when there is one, and
  /// from the observed playback state otherwise. The distinction matters:
  /// an engine that autoplays reports "paused" until something asks it to
  /// play, so the observed state alone would bring a recovered live stream
  /// back paused.
  final bool wasPlaying;

  /// Volume to restore after a successful step.
  final double volume;

  /// Playback rate to restore after a successful step.
  final double rate;

  /// Backend attached when the failure was observed.
  final String? backendId;

  /// Session generation this session belongs to.
  final GenerationId? generationId;

  /// Attempt number within the current ladder run.
  final int attempt;

  /// Whether a source is currently open.
  bool get hasSource => source != null;

  /// Whether another source can be tried.
  bool get hasSourceCandidates => sourceCandidates.isNotEmpty;

  /// Whether another backend can be tried.
  bool get hasBackendCandidates => backendCandidates.isNotEmpty;

  /// Whether anything at all can be tried besides reopening in place.
  bool get hasAlternatives => hasSourceCandidates || hasBackendCandidates;

  /// Short diagnostic label of the failing unit.
  String get label {
    final uri = source?.uri.toString() ?? failure.uri ?? '-';

    return '$uri@${backendId ?? '-'}';
  }

  /// Creates a copy with selected values replaced.
  RecoverySession copyWith({
    RecoveryFailure? failure,
    PlayerSource? source,
    List<PlayerSource>? sourceCandidates,
    List<PlayerAdapterRegistration>? backendCandidates,
    Duration? position,
    bool? wasPlaying,
    double? volume,
    double? rate,
    String? backendId,
    GenerationId? generationId,
    int? attempt,
  }) {
    return RecoverySession(
      failure: failure ?? this.failure,
      source: source ?? this.source,
      sourceCandidates: sourceCandidates ?? this.sourceCandidates,
      backendCandidates: backendCandidates ?? this.backendCandidates,
      position: position ?? this.position,
      wasPlaying: wasPlaying ?? this.wasPlaying,
      volume: volume ?? this.volume,
      rate: rate ?? this.rate,
      backendId: backendId ?? this.backendId,
      generationId: generationId ?? this.generationId,
      attempt: attempt ?? this.attempt,
    );
  }

  /// Serialises the session for diagnostics and persistence.
  ///
  /// Candidates are reduced to URIs and backend ids so the map stays small enough to log.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'label': label,
      'positionMs': position.inMilliseconds,
      'wasPlaying': wasPlaying,
      'volume': volume,
      'rate': rate,
      'generationId': generationId?.value,
      'sourceCandidates': sourceCandidates.map((source) => source.uri.toString()).toList(),
      'backendCandidates': backendCandidates.map((registration) => registration.id).toList(),
      'failure': failure.toMap(),
    };
  }

  @override
  List<Object?> get props => <Object?>[
    failure,
    source?.id,
    sourceCandidates.map((source) => source.id).toList(),
    backendCandidates.map((registration) => registration.id).toList(),
    position,
    wasPlaying,
    volume,
    rate,
    backendId,
    generationId,
    attempt,
  ];

  @override
  String toString() {
    return 'RecoverySession('
        'label=$label, '
        'position=${position.inMilliseconds}ms, '
        'wasPlaying=$wasPlaying, '
        'lines=${sourceCandidates.length}, '
        'backends=${backendCandidates.length}'
        ')';
  }
}
