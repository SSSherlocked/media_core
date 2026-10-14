import 'package:equatable/equatable.dart';
import 'package:media_core/lifecycle/lifecycle_state.dart';

/// Immutable lifecycle snapshot.
final class LifecycleSnapshot extends Equatable {
  /// Creates a snapshot of [state] stamped with [updatedAt].
  const LifecycleSnapshot({required this.state, this.updatedAt});

  /// The snapshot of a player that has not been created yet.
  factory LifecycleSnapshot.initial() {
    return const LifecycleSnapshot(state: LifecycleState());
  }

  /// The lifecycle state captured by this snapshot.
  final LifecycleState state;

  /// When the state was last recorded, or `null` when not tracked.
  final DateTime? updatedAt;

  /// Whether the player has reached the disposed terminal state.
  bool get isDisposed {
    return state.disposed;
  }

  /// Whether the player is currently bound to a foreground surface.
  bool get isActive {
    return state.active;
  }

  /// Copies the snapshot, replacing whichever fields are provided.
  LifecycleSnapshot copyWith({LifecycleState? state, DateTime? updatedAt}) {
    return LifecycleSnapshot(state: state ?? this.state, updatedAt: updatedAt ?? this.updatedAt);
  }

  @override
  List<Object?> get props => [state, updatedAt];
}

/// Serialization helpers for [LifecycleSnapshot].
extension LifecycleSnapshotSerialization on LifecycleSnapshot {
  /// Converts the snapshot to a plain map for logging or persistence.
  Map<String, Object?> toMap() => {'state': state.toString(), 'updatedAt': updatedAt?.toIso8601String()};
}
