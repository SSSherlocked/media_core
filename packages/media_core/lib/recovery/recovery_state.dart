import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/recovery/recovery_action.dart';

/// Immutable recovery state.
///
/// Describes the current recovery lifecycle.
///
/// The state itself does not execute recovery operations. It only records
/// the recovery decision and its lifecycle:
///
/// ```text
/// idle
///   │
///   ▼
/// active
///   │
///   ├── complete
///   │
///   └── exhaust
/// ```
///
/// The retry attempt counter belongs to the recovery lifecycle and changes only
/// through [recordAttempt], which is called when a retry actually starts.
final class RecoveryState extends Equatable {
  /// Records one point of the recovery lifecycle with all of its fields supplied at once.
  const RecoveryState({
    required this.action,
    required this.attempt,
    required this.active,
    required this.completed,
    required this.exhausted,
    required this.updatedAt,
  });

  /// Rebuilds a state from a persisted map, treating missing or malformed fields as idle.
  ///
  /// The action is not round-tripped, so a restored state always reports [RecoveryAction.none].
  factory RecoveryState.fromMap(Map<String, dynamic> map) {
    return RecoveryState(
      action: const RecoveryAction.none(),
      attempt: (map['attempt'] as num?)?.toInt() ?? 0,
      active: map['active'] as bool? ?? false,
      completed: map['completed'] as bool? ?? false,
      exhausted: map['exhausted'] as bool? ?? false,
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  /// The state before any failure has been considered: idle, with no attempts recorded.
  const RecoveryState.initial()
    : action = const RecoveryAction.none(),
      attempt = 0,
      active = false,
      completed = false,
      exhausted = false,
      updatedAt = null;

  /// Recovery action currently being executed or requested.
  final RecoveryAction action;

  /// Number of recovery attempts that have actually started.
  final int attempt;

  /// Whether recovery is currently active.
  final bool active;

  /// Whether recovery completed successfully.
  final bool completed;

  /// Whether recovery cannot continue.
  final bool exhausted;

  /// Time when this state was last changed.
  final DateTime? updatedAt;

  /// Whether the recovery state is idle.
  bool get isIdle {
    return !active && !completed && !exhausted;
  }

  /// Whether the state represents an active retry operation.
  bool get isRetrying {
    return active && action.requiresRetry;
  }

  /// Whether the recovery lifecycle reached a terminal state.
  bool get isTerminal {
    return completed || exhausted;
  }

  /// Creates a modified copy of this state.
  RecoveryState copyWith({
    RecoveryAction? action,
    int? attempt,
    bool? active,
    bool? completed,
    bool? exhausted,
    DateTime? updatedAt,
  }) {
    return RecoveryState(
      action: action ?? this.action,
      attempt: attempt ?? this.attempt,
      active: active ?? this.active,
      completed: completed ?? this.completed,
      exhausted: exhausted ?? this.exhausted,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Starts a recovery operation.
  ///
  /// The attempt counter is not incremented here because starting a recovery
  /// decision and actually starting a retry are separate lifecycle events.
  RecoveryState start({required RecoveryAction action, DateTime? updatedAt}) {
    return RecoveryState(
      action: action,
      attempt: attempt,
      active: true,
      completed: false,
      exhausted: false,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Records that one recovery attempt has actually started.
  RecoveryState recordAttempt({DateTime? updatedAt}) {
    return RecoveryState(
      action: action,
      attempt: attempt + 1,
      active: true,
      completed: false,
      exhausted: false,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Marks recovery as successfully completed.
  RecoveryState complete({DateTime? updatedAt}) {
    return RecoveryState(
      action: action,
      attempt: attempt,
      active: false,
      completed: true,
      exhausted: false,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Marks recovery as exhausted.
  RecoveryState exhaust({DateTime? updatedAt}) {
    return RecoveryState(
      action: action,
      attempt: attempt,
      active: false,
      completed: false,
      exhausted: true,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Cancels the active recovery operation.
  RecoveryState cancel({DateTime? updatedAt}) {
    return RecoveryState(
      action: const RecoveryAction.none(),
      attempt: attempt,
      active: false,
      completed: false,
      exhausted: false,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Resets the complete recovery lifecycle.
  RecoveryState reset({DateTime? updatedAt}) {
    return RecoveryState(
      action: const RecoveryAction.none(),
      attempt: 0,
      active: false,
      completed: false,
      exhausted: false,
      updatedAt: updatedAt ?? clock.now(),
    );
  }

  /// Serialises the lifecycle for diagnostics and persistence.
  ///
  /// The action is written as its text form, which [RecoveryState.fromMap] does not read back.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'action': action.toString(),
      'attempt': attempt,
      'active': active,
      'completed': completed,
      'exhausted': exhausted,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  @override
  List<Object?> get props {
    return <Object?>[action, attempt, active, completed, exhausted, updatedAt];
  }

  @override
  String toString() {
    return 'RecoveryState('
        'action: $action, '
        'attempt: $attempt, '
        'active: $active, '
        'completed: $completed, '
        'exhausted: $exhausted, '
        'updatedAt: $updatedAt'
        ')';
  }
}
