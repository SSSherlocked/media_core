import 'package:equatable/equatable.dart';

/// Immutable state for backend fallback.
///
/// [candidates] contains only candidates that have not yet been selected.
///
/// [exhausted] means that no candidate remains after a failed attempt.
/// Selecting the final candidate does not itself make the state exhausted.
final class BackendFallbackState extends Equatable {
  /// Creates backend fallback state from explicit field values.
  const BackendFallbackState({
    required this.currentBackend,
    required this.candidates,
    required this.attempt,
    required this.active,
    required this.completed,
    required this.exhausted,
  });

  /// Reconstructs state from its [toMap] serialization, tolerating
  /// missing or malformed entries by falling back to idle defaults.
  factory BackendFallbackState.fromMap(Map<String, dynamic> map) {
    final Object? candidatesValue = map['candidates'];

    return BackendFallbackState(
      currentBackend: map['currentBackend'] as String?,
      candidates: candidatesValue is List
          ? List<String>.unmodifiable(candidatesValue.whereType<String>())
          : const <String>[],
      attempt: (map['attempt'] as num?)?.toInt() ?? 0,
      active: map['active'] as bool? ?? false,
      completed: map['completed'] as bool? ?? false,
      exhausted: map['exhausted'] as bool? ?? false,
    );
  }

  /// Creates the idle starting state with no attempt made yet.
  const BackendFallbackState.initial({String? currentBackend, List<String> candidates = const <String>[]})
    : this(
        currentBackend: currentBackend,
        candidates: candidates,
        attempt: 0,
        active: false,
        completed: false,
        exhausted: false,
      );

  /// The backend currently selected, or `null` before one is chosen.
  final String? currentBackend;

  /// The backends that have not yet been selected, in fallback order.
  final List<String> candidates;

  /// How many backends have been selected so far.
  final int attempt;

  /// Whether a fallback lifecycle is currently in progress.
  final bool active;

  /// Whether a backend succeeded, ending fallback.
  final bool completed;

  /// Whether no candidate remains after a failed attempt.
  final bool exhausted;

  /// Whether another candidate is still available to fall back to.
  bool get canFallback {
    return !completed && !exhausted && candidates.isNotEmpty;
  }

  /// The candidate to try next, or `null` when fallback cannot continue.
  String? get nextBackend {
    if (!canFallback) {
      return null;
    }

    return candidates.first;
  }

  /// Begins a new fallback lifecycle over [candidates], optionally
  /// recording [currentBackend] as already in use.
  BackendFallbackState start({required List<String> candidates, String? currentBackend}) {
    return BackendFallbackState(
      currentBackend: currentBackend,
      candidates: List<String>.unmodifiable(candidates),
      attempt: 0,
      active: true,
      completed: false,
      exhausted: candidates.isEmpty,
    );
  }

  /// Marks [backend] as the chosen candidate, removing it from the pool
  /// and bumping [attempt]; returns this state unchanged when selecting
  /// is not permitted (inactive, completed, exhausted, or unknown backend).
  BackendFallbackState select(String backend) {
    if (!active || completed || exhausted) {
      return this;
    }

    if (!candidates.contains(backend)) {
      return this;
    }

    final remaining = List<String>.from(candidates)..remove(backend);

    return BackendFallbackState(
      currentBackend: backend,
      candidates: List<String>.unmodifiable(remaining),
      attempt: attempt + 1,
      active: true,
      completed: false,
      exhausted: false,
    );
  }

  /// Records the current attempt as failed, deactivating the lifecycle and
  /// marking [exhausted] when no candidate is left to try.
  BackendFallbackState markFailed() {
    return BackendFallbackState(
      currentBackend: currentBackend,
      candidates: candidates,
      attempt: attempt,
      active: false,
      completed: false,
      exhausted: candidates.isEmpty,
    );
  }

  /// Marks the current backend as successfully completed, ending fallback.
  BackendFallbackState complete() {
    return BackendFallbackState(
      currentBackend: currentBackend,
      candidates: candidates,
      attempt: attempt,
      active: false,
      completed: true,
      exhausted: false,
    );
  }

  /// Discards the remaining candidates and marks fallback exhausted.
  BackendFallbackState exhaust() {
    return BackendFallbackState(
      currentBackend: currentBackend,
      candidates: const <String>[],
      attempt: attempt,
      active: false,
      completed: false,
      exhausted: true,
    );
  }

  /// Returns to the idle initial state.
  BackendFallbackState reset() {
    return const BackendFallbackState.initial();
  }

  /// Returns a copy with the given fields replaced.
  BackendFallbackState copyWith({
    String? currentBackend,
    List<String>? candidates,
    int? attempt,
    bool? active,
    bool? completed,
    bool? exhausted,
  }) {
    return BackendFallbackState(
      currentBackend: currentBackend ?? this.currentBackend,
      candidates: candidates != null ? List<String>.unmodifiable(candidates) : this.candidates,
      attempt: attempt ?? this.attempt,
      active: active ?? this.active,
      completed: completed ?? this.completed,
      exhausted: exhausted ?? this.exhausted,
    );
  }

  /// Serializes the state for persistence, readable back via `fromMap`.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'currentBackend': currentBackend,
      'candidates': candidates,
      'attempt': attempt,
      'active': active,
      'completed': completed,
      'exhausted': exhausted,
    };
  }

  @override
  List<Object?> get props => <Object?>[currentBackend, candidates, attempt, active, completed, exhausted];

  @override
  String toString() {
    return 'BackendFallbackState('
        'currentBackend: $currentBackend, '
        'candidates: $candidates, '
        'attempt: $attempt, '
        'active: $active, '
        'completed: $completed, '
        'exhausted: $exhausted'
        ')';
  }
}
