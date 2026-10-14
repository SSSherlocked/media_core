import 'package:equatable/equatable.dart';
import 'package:media_core/visibility/visibility_state.dart';

/// Immutable visibility snapshot.
final class VisibilitySnapshot extends Equatable {
  /// Creates a snapshot from explicit values.
  const VisibilitySnapshot({required this.state, this.updatedAt});

  /// Snapshot of the default hidden state.
  factory VisibilitySnapshot.initial() {
    return const VisibilitySnapshot(state: VisibilityState());
  }

  /// Visibility state captured with this snapshot.
  final VisibilityState state;

  /// When the snapshot was taken; null for hand-built snapshots.
  final DateTime? updatedAt;

  /// Whether the player was visible when the snapshot was taken.
  bool get visible => state.visible;

  /// Share of the player that was on screen, from 0.0 to 1.0.
  double get ratio => state.visibility;

  /// Creates a copy with the supplied values replaced.
  VisibilitySnapshot copyWith({VisibilityState? state, DateTime? updatedAt}) {
    return VisibilitySnapshot(state: state ?? this.state, updatedAt: updatedAt ?? this.updatedAt);
  }

  @override
  List<Object?> get props => [state, updatedAt];
}
