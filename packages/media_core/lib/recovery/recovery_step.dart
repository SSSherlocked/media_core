import 'package:equatable/equatable.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/source/player_source.dart';

/// One rung of the recovery ladder.
///
/// The ladder escalates through a fixed order of step kinds; it never
/// invents a kind at runtime. Executing a step is the recovery target's
/// job — the kind only says *what* is being attempted, not how.
enum RecoveryStepKind {
  /// Close and reopen the current source on the current backend.
  ///
  /// The cheapest step: a stalled or broken stream often recovers by
  /// re-opening, without touching the backend or the source list.
  sameBackendReopen,

  /// Open another candidate source on the current backend.
  ///
  /// Only possible when the caller supplied alternative sources (live
  /// streams carry several lines).
  nextLine,

  /// Attach and open another backend, preserving position and play state.
  nextBackend,

  /// Wait before rescanning the ladder from its first step.
  ///
  /// The only step kind with no physical operation: it exists so a
  /// transient outage gets time to clear instead of burning the whole
  /// budget in a tight loop.
  backoff,
}

/// A concrete attempt produced by the ladder.
///
/// A step is inert data: the ladder builds it, the recovery target
/// executes it. It carries everything the target needs to know about
/// the attempt — the kind, how many attempts of that kind were already
/// made, the source to open (for [RecoveryStepKind.nextLine]) and the
/// backend to attach (for [RecoveryStepKind.nextBackend]).
final class RecoveryStep extends Equatable {
  /// Creates a step.
  const RecoveryStep({
    required this.kind,
    required this.index,
    this.source,
    this.backendId,
    this.delay = Duration.zero,
  });

  /// Creates a same-backend reopen step.
  const RecoveryStep.reopen({required int index, PlayerSource? source})
    : this(kind: RecoveryStepKind.sameBackendReopen, index: index, source: source);

  /// Creates a next-line step.
  const RecoveryStep.nextLine({required int index, required PlayerSource source})
    : this(kind: RecoveryStepKind.nextLine, index: index, source: source);

  /// Creates a next-backend step.
  const RecoveryStep.nextBackend({required int index, required String backendId})
    : this(kind: RecoveryStepKind.nextBackend, index: index, backendId: backendId);

  /// Creates a backoff step.
  const RecoveryStep.backoff({required int index, required Duration delay})
    : this(kind: RecoveryStepKind.backoff, index: index, delay: delay);

  /// Kind of attempt.
  final RecoveryStepKind kind;

  /// Zero-based attempt number within this kind.
  ///
  /// Lets a target and a log reader tell the first reopen from the
  /// third one without keeping their own counter.
  final int index;

  /// Source to open, for steps that replace the source.
  final PlayerSource? source;

  /// Backend to attach, for [RecoveryStepKind.nextBackend].
  final String? backendId;

  /// How long to wait, for [RecoveryStepKind.backoff].
  final Duration delay;

  /// Whether executing this step touches a backend.
  ///
  /// Backoff is pure timing; every other kind is a physical operation
  /// the recovery target must perform.
  bool get isPhysical => kind != RecoveryStepKind.backoff;

  /// Source identifier this step targets, when it has one.
  SourceId? get sourceId => source?.id;

  /// Short diagnostic label.
  String get label {
    return switch (kind) {
      RecoveryStepKind.sameBackendReopen => 'sameBackendReopen#${index + 1}',
      RecoveryStepKind.nextLine => 'nextLine#${index + 1}${source == null ? '' : '(${source!.uri})'}',
      RecoveryStepKind.nextBackend => 'nextBackend#${index + 1}${backendId == null ? '' : '($backendId)'}',
      RecoveryStepKind.backoff => 'backoff#${index + 1}(${delay.inMilliseconds}ms)',
    };
  }

  @override
  List<Object?> get props => <Object?>[kind, index, source?.id, backendId, delay];

  @override
  String toString() => 'RecoveryStep($label)';
}
