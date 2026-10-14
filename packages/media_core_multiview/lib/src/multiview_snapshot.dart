import 'package:media_core/media_core.dart';

import 'package:media_core_multiview/src/multiview_cell.dart';
import 'package:media_core_multiview/src/multiview_layout.dart';

/// How much quality a cell wants, relative to the best available.
enum MultiviewQualityPreference {
  /// Best available: worth looking at.
  best,

  /// Middle of the ladder: recognisable without costing the most.
  balanced,

  /// Lowest available.
  ///
  /// What a non-focused wall cell should use: the viewer needs to see that
  /// something is happening in that room, not to read the scoreboard.
  lowest,
}

/// Resolves [source] at the quality [preference] asks for.
///
/// A callback rather than an implementation because only the host knows how to
/// ask its sites for another rendition. Without one the wall plays what it was
/// given and the quality policy is inert — which is stated rather than silently
/// pretended.
typedef MultiviewQualityResolver =
    Future<MultiviewCellSource> Function(MultiviewCellSource source, MultiviewQualityPreference preference);

/// Immutable view of the wall, for a host that renders from state.
final class MultiviewSnapshot {
  /// Creates a snapshot of the wall's current cells, layout and focus.
  const MultiviewSnapshot({
    required this.cells,
    required this.layout,
    required this.focusedIndex,
    required this.audioIndex,
    required this.pressure,
    required this.budgetExceeded,
  });

  /// The cells, in grid order. A copy: safe to render without the wall mutating underneath.
  final List<MultiviewCell> cells;

  /// The layout the wall is currently rendered at.
  final MultiviewLayout layout;

  /// Cell the viewer is looking at.
  final int focusedIndex;

  /// Cell that is audible, or `null` when nothing is.
  final int? audioIndex;

  /// Latest resource pressure.
  final ResourcePressure pressure;

  /// Whether the wall is currently past its decode budget.
  final bool budgetExceeded;

  /// Cells that are playing.
  int get playingCount => cells.where((cell) => cell.isPlaying).length;

  /// Cells with a room assigned.
  int get assignedCount => cells.where((cell) => !cell.isEmpty).length;

  @override
  String toString() => 'MultiviewSnapshot(${layout.name}, $playingCount playing, focus $focusedIndex)';
}
