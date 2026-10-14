import 'package:equatable/equatable.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/recovery/recovery_failure.dart';
import 'package:media_core/source/player_source.dart';

/// Candidate sets the ladder may draw recovery steps from.
///
/// The ladder knows *how* to escalate but not *what* to escalate to:
/// the list of alternative sources belongs to the caller (a live
/// controller holds the lines of a stream) and the list of alternative
/// backends belongs to the adapter registry. A provider is the seam
/// that keeps both out of the ladder.
final class RecoveryCandidates extends Equatable {
  /// Creates a candidate set.
  const RecoveryCandidates({
    this.sources = const <PlayerSource>[],
    this.backends = const <PlayerAdapterRegistration>[],
  });

  /// Alternative sources, best first.
  final List<PlayerSource> sources;

  /// Alternative backends, best first.
  final List<PlayerAdapterRegistration> backends;

  /// Empty candidate set.
  static const RecoveryCandidates none = RecoveryCandidates();

  /// Whether any candidate exists.
  bool get isEmpty => sources.isEmpty && backends.isEmpty;

  /// Whether at least one candidate exists.
  bool get isNotEmpty => !isEmpty;

  /// Number of candidates.
  int get length => sources.length + backends.length;

  @override
  List<Object?> get props => <Object?>[
    sources.map((source) => source.id).toList(),
    backends.map((registration) => registration.id).toList(),
  ];

  @override
  String toString() => 'RecoveryCandidates(lines: ${sources.length}, backends: ${backends.length})';
}

/// Supplies recovery candidates for a failure.
///
/// Implemented by the layer that owns the candidates — in practice the
/// player handle, which holds both the caller-supplied source list and
/// the adapter registry. The ladder stays unaware of where they come
/// from.
abstract interface class RecoveryCandidateProvider {
  /// Candidates that may be tried for [failure], best first.
  ///
  /// Must exclude whatever is currently in use: the ladder must never
  /// treat the failing source or backend as its own alternative.
  RecoveryCandidates candidatesFor(RecoveryFailure failure);
}
