import 'package:equatable/equatable.dart';

/// Immutable state for playback-line fallback.
///
/// A line is removed from [candidates] once it is selected for an attempt.
///
/// [exhausted] means that there are no remaining candidates after a failed
/// attempt.
final class LineFallbackState extends Equatable {
  /// Creates line fallback state from explicit field values.
  const LineFallbackState({
    required this.currentLine,
    required this.candidates,
    required this.attempt,
    required this.active,
    required this.completed,
    required this.exhausted,
  });

  /// Reconstructs state from its [toMap] serialization, tolerating
  /// missing or malformed entries by falling back to idle defaults.
  factory LineFallbackState.fromMap(Map<String, dynamic> map) {
    final Object? candidatesValue = map['candidates'];

    return LineFallbackState(
      currentLine: map['currentLine'] as String?,
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
  const LineFallbackState.initial({String? currentLine, List<String> candidates = const <String>[]})
    : this(
        currentLine: currentLine,
        candidates: candidates,
        attempt: 0,
        active: false,
        completed: false,
        exhausted: false,
      );

  /// The line currently selected, or `null` before one is chosen.
  final String? currentLine;

  /// The lines that have not yet been selected, in fallback order.
  final List<String> candidates;

  /// How many lines have been selected so far.
  final int attempt;

  /// Whether a fallback lifecycle is currently in progress.
  final bool active;

  /// Whether a line succeeded, ending fallback.
  final bool completed;

  /// Whether no candidate remains after a failed attempt.
  final bool exhausted;

  /// Whether another candidate is still available to fall back to.
  bool get canFallback {
    return !completed && !exhausted && candidates.isNotEmpty;
  }

  /// The candidate to try next, or `null` when fallback cannot continue.
  String? get nextLine {
    if (!canFallback) {
      return null;
    }

    return candidates.first;
  }

  /// Begins a new fallback lifecycle over [candidates], optionally
  /// recording [currentLine] as already in use and removing it from the
  /// pool so the ladder can advance past it.
  LineFallbackState start({required List<String> candidates, String? currentLine}) {
    // The line currently being attempted must not remain in the candidate
    // pool: next() would hand it back and the ladder would never advance.
    final remaining = currentLine != null && candidates.contains(currentLine)
        ? (List<String>.from(candidates)..remove(currentLine))
        : List<String>.from(candidates);

    return LineFallbackState(
      currentLine: currentLine,
      candidates: List<String>.unmodifiable(remaining),
      attempt: 0,
      active: true,
      completed: false,
      exhausted: remaining.isEmpty,
    );
  }

  /// Marks [line] as the chosen candidate, removing it from the pool and
  /// bumping [attempt]; returns this state unchanged when selecting is not
  /// permitted (inactive, completed, exhausted, or unknown line).
  LineFallbackState select(String line) {
    if (!active || completed || exhausted) {
      return this;
    }

    if (!candidates.contains(line)) {
      return this;
    }

    final remaining = List<String>.from(candidates)..remove(line);

    return LineFallbackState(
      currentLine: line,
      candidates: List<String>.unmodifiable(remaining),
      attempt: attempt + 1,
      active: true,
      completed: false,
      exhausted: false,
    );
  }

  /// Records the current attempt as failed, marking [exhausted] when no
  /// candidate is left; unlike backend fallback it stays active so the
  /// caller can advance to the next line.
  LineFallbackState markFailed() {
    // A failed attempt must not deactivate the state machine: the caller
    // immediately calls next() to advance to the following line. Marking
    // the state inactive here would make select() a no-op and the same
    // line would be handed back forever.
    return LineFallbackState(
      currentLine: currentLine,
      candidates: candidates,
      attempt: attempt,
      active: active,
      completed: false,
      exhausted: candidates.isEmpty,
    );
  }

  /// Marks the current line as successfully completed, ending fallback.
  LineFallbackState complete() {
    return LineFallbackState(
      currentLine: currentLine,
      candidates: candidates,
      attempt: attempt,
      active: false,
      completed: true,
      exhausted: false,
    );
  }

  /// Discards the remaining candidates and marks fallback exhausted.
  LineFallbackState exhaust() {
    return LineFallbackState(
      currentLine: currentLine,
      candidates: const <String>[],
      attempt: attempt,
      active: false,
      completed: false,
      exhausted: true,
    );
  }

  /// Returns to the idle initial state.
  LineFallbackState reset() {
    return const LineFallbackState.initial();
  }

  /// Returns a copy with the given fields replaced.
  LineFallbackState copyWith({
    String? currentLine,
    List<String>? candidates,
    int? attempt,
    bool? active,
    bool? completed,
    bool? exhausted,
  }) {
    return LineFallbackState(
      currentLine: currentLine ?? this.currentLine,
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
      'currentLine': currentLine,
      'candidates': candidates,
      'attempt': attempt,
      'active': active,
      'completed': completed,
      'exhausted': exhausted,
    };
  }

  @override
  List<Object?> get props => <Object?>[currentLine, candidates, attempt, active, completed, exhausted];

  @override
  String toString() {
    return 'LineFallbackState('
        'currentLine: $currentLine, '
        'candidates: $candidates, '
        'attempt: $attempt, '
        'active: $active, '
        'completed: $completed, '
        'exhausted: $exhausted'
        ')';
  }
}
