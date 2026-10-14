import 'package:equatable/equatable.dart';

/// Immutable state for quality fallback.
///
/// A quality candidate is removed when it is selected for an attempt.
///
/// The state becomes exhausted only after the current attempt fails and there
/// are no remaining candidates.
final class QualityFallbackState extends Equatable {
  /// Creates quality fallback state from explicit field values.
  const QualityFallbackState({
    required this.currentQuality,
    required this.candidates,
    required this.attempt,
    required this.active,
    required this.completed,
    required this.exhausted,
  });

  /// Reconstructs state from its [toMap] serialization, tolerating
  /// missing or malformed entries by falling back to idle defaults.
  factory QualityFallbackState.fromMap(Map<String, dynamic> map) {
    final Object? candidatesValue = map['candidates'];

    return QualityFallbackState(
      currentQuality: map['currentQuality'] as String?,
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
  const QualityFallbackState.initial({String? currentQuality, List<String> candidates = const <String>[]})
    : this(
        currentQuality: currentQuality,
        candidates: candidates,
        attempt: 0,
        active: false,
        completed: false,
        exhausted: false,
      );

  /// The quality currently selected, or `null` before one is chosen.
  final String? currentQuality;

  /// The qualities that have not yet been selected, in fallback order.
  final List<String> candidates;

  /// How many qualities have been selected so far.
  final int attempt;

  /// Whether a fallback lifecycle is currently in progress.
  final bool active;

  /// Whether a quality succeeded, ending fallback.
  final bool completed;

  /// Whether no candidate remains after a failed attempt.
  final bool exhausted;

  /// Whether another candidate is still available to fall back to.
  bool get canFallback {
    return !completed && !exhausted && candidates.isNotEmpty;
  }

  /// The candidate to try next, or `null` when fallback cannot continue.
  String? get nextQuality {
    if (!canFallback) {
      return null;
    }

    return candidates.first;
  }

  /// Begins a new fallback lifecycle over [candidates], optionally
  /// recording [currentQuality] as already in use.
  QualityFallbackState start({required List<String> candidates, String? currentQuality}) {
    return QualityFallbackState(
      currentQuality: currentQuality,
      candidates: List<String>.unmodifiable(candidates),
      attempt: 0,
      active: true,
      completed: false,
      exhausted: candidates.isEmpty,
    );
  }

  /// Marks [quality] as the chosen candidate, removing it from the pool and
  /// bumping [attempt]; returns this state unchanged when selecting is not
  /// permitted (inactive, completed, exhausted, or unknown quality).
  QualityFallbackState select(String quality) {
    if (!active || completed || exhausted) {
      return this;
    }

    if (!candidates.contains(quality)) {
      return this;
    }

    final remaining = List<String>.from(candidates)..remove(quality);

    return QualityFallbackState(
      currentQuality: quality,
      candidates: List<String>.unmodifiable(remaining),
      attempt: attempt + 1,
      active: true,
      completed: false,
      exhausted: false,
    );
  }

  /// Records the current attempt as failed, deactivating the lifecycle and
  /// marking [exhausted] when no candidate is left to try.
  QualityFallbackState markFailed() {
    return QualityFallbackState(
      currentQuality: currentQuality,
      candidates: candidates,
      attempt: attempt,
      active: false,
      completed: false,
      exhausted: candidates.isEmpty,
    );
  }

  /// Marks the current quality as successfully completed, ending fallback.
  QualityFallbackState complete() {
    return QualityFallbackState(
      currentQuality: currentQuality,
      candidates: candidates,
      attempt: attempt,
      active: false,
      completed: true,
      exhausted: false,
    );
  }

  /// Discards the remaining candidates and marks fallback exhausted.
  QualityFallbackState exhaust() {
    return QualityFallbackState(
      currentQuality: currentQuality,
      candidates: const <String>[],
      attempt: attempt,
      active: false,
      completed: false,
      exhausted: true,
    );
  }

  /// Returns to the idle initial state.
  QualityFallbackState reset() {
    return const QualityFallbackState.initial();
  }

  /// Returns a copy with the given fields replaced.
  QualityFallbackState copyWith({
    String? currentQuality,
    List<String>? candidates,
    int? attempt,
    bool? active,
    bool? completed,
    bool? exhausted,
  }) {
    return QualityFallbackState(
      currentQuality: currentQuality ?? this.currentQuality,
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
      'currentQuality': currentQuality,
      'candidates': candidates,
      'attempt': attempt,
      'active': active,
      'completed': completed,
      'exhausted': exhausted,
    };
  }

  @override
  List<Object?> get props => <Object?>[currentQuality, candidates, attempt, active, completed, exhausted];

  @override
  String toString() {
    return 'QualityFallbackState('
        'currentQuality: $currentQuality, '
        'candidates: $candidates, '
        'attempt: $attempt, '
        'active: $active, '
        'completed: $completed, '
        'exhausted: $exhausted'
        ')';
  }
}
