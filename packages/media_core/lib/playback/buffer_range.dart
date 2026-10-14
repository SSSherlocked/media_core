import 'package:equatable/equatable.dart';
import 'package:media_core/playback/library.dart' show PlaybackBuffer, PlayerTransportState;

/// One contiguous stretch of media the engine can play without waiting.
///
/// A buffer range is expressed in the same media-local clock as
/// [PlayerTransportState.position]; it says nothing about *why* the
/// bytes are there (proloaded, cached, or fetched ahead), only that
/// the engine believes [start] through [end] will not stall.
///
/// Responsibilities:
///
/// - express one buffered stretch
///
/// It does not:
///
/// - merge with neighbors (that is [PlaybackBuffer]'s job)
/// - include byte counts
///
/// Those belong to:
///
/// - PlaybackBuffer
/// - PlayerAdapterMetrics
final class BufferRange extends Equatable {
  /// Creates a buffered stretch from [start] to [end].
  ///
  /// A zero-length or inverted range is accepted and treated as empty
  /// by [PlaybackBuffer.normalize] rather than rejected: engines
  /// report ranges at boundaries where start == end happens, and
  /// throwing there would punish a normal condition.
  const BufferRange({required this.start, required this.end});

  /// First buffered media time.
  final Duration start;

  /// One past the last buffered media time.
  final Duration end;

  /// Whether this stretch holds any media time.
  bool get isEmpty => end <= start;

  /// Length of the stretch.
  Duration get duration => isEmpty ? Duration.zero : end - start;

  /// Whether [time] lies inside this stretch, end-exclusive.
  bool covers(Duration time) => !isEmpty && time >= start && time < end;

  /// Whether this stretch touches or overlaps [other].
  ///
  /// Adjacent ranges (one ends exactly where the next begins) count
  /// as touching: on a media clock that is one continuous stretch.
  bool touches(BufferRange other) {
    if (isEmpty || other.isEmpty) {
      return true;
    }
    return other.start <= end && start <= other.end;
  }

  /// The union of this and [other], which must touch.
  BufferRange unite(BufferRange other) {
    return BufferRange(start: start < other.start ? start : other.start, end: end > other.end ? end : other.end);
  }

  @override
  List<Object?> get props => <Object?>[start, end];

  @override
  String toString() => 'BufferRange($start - $end)';
}
