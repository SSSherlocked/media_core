import 'package:equatable/equatable.dart';
import 'package:media_core/playback/buffer_range.dart';

/// Everything the engine currently reports as buffered.
///
/// A progress bar paints a timeline, not a list of ranges, so the
/// merge and reachability questions live here: [PlaybackBuffer.normalize]
/// turns whatever an engine reported (overlapping, adjacent, out of
/// order, inverted) into canonical contiguous stretches, and
/// [bufferedEndAt] answers the one question UI actually asks — "how
/// far from the playhead will playback continue without waiting".
///
/// Responsibilities:
///
/// - canonicalize reported ranges
/// - answer reachability questions from a position
///
/// It does not:
///
/// - know the playhead (PlaybackController owns that)
/// - cache bytes
///
/// Those belong to:
///
/// - PlaybackController
/// - the cache module
final class PlaybackBuffer extends Equatable {
  /// Creates a buffer from raw reported [ranges].
  const PlaybackBuffer({required this.ranges});

  /// A buffer that holds nothing.
  const PlaybackBuffer.empty() : ranges = const <BufferRange>[];

  /// Reported stretches, in whatever order the engine reported them.
  final List<BufferRange> ranges;

  /// The canonical view: empty ranges dropped, overlaps and adjacency
  /// merged, sorted by start.
  ///
  /// Merging is what makes a progress bar honest. Two adjacent
  /// stretches painted as one is the truth an engine cannot express —
  /// each incremental report ends exactly where the next begins, and
  /// a renderer that drew them separately would look identical, but
  /// a hit test against the list would miss the seam.
  PlaybackBuffer normalize() {
    final meaningful = ranges.where((range) => !range.isEmpty).toList()..sort((a, b) => a.start.compareTo(b.start));

    if (meaningful.isEmpty) {
      return const PlaybackBuffer.empty();
    }

    final merged = <BufferRange>[meaningful.first];
    for (final next in meaningful.skip(1)) {
      final last = merged.last;
      if (last.touches(next)) {
        merged[merged.length - 1] = last.unite(next);
      } else {
        merged.add(next);
      }
    }
    return PlaybackBuffer(ranges: List<BufferRange>.unmodifiable(merged));
  }

  /// Whether [time] is inside any reported stretch.
  bool covers(Duration time) => ranges.any((range) => range.covers(time));

  /// The end of the contiguous stretch containing or following [time].
  ///
  /// Returns [time] itself when nothing is buffered at or ahead of
  /// the position — a progress bar reads this as "no ahead fill",
  /// never as a lie about data that does not exist. A gap between
  /// stretches stops the walk: data past the gap will stall, so
  /// painting it as buffered would mislead the very gesture that
  /// relies on the bar.
  Duration bufferedEndAt(Duration time) {
    final canonical = normalize();
    var reach = time;
    for (final range in canonical.ranges) {
      if (range.covers(time)) {
        reach = range.end;
      } else if (!range.isEmpty && range.start <= reach) {
        // Contiguously reachable from where we already stand.
        if (range.end > reach) {
          reach = range.end;
        }
      } else if (range.start > reach) {
        break;
      }
    }
    return reach;
  }

  /// Total buffered media time across all stretches.
  Duration get bufferedDuration {
    var total = Duration.zero;
    for (final range in normalize().ranges) {
      total += range.duration;
    }
    return total;
  }

  @override
  List<Object?> get props => <Object?>[ranges];
}
