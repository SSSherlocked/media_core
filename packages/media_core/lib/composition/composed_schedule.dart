import 'package:equatable/equatable.dart';
import 'package:media_core/composition/media_segment.dart';
import 'package:media_core/composition/playback_schedule.dart' show PlaybackSchedule;
import 'package:media_core/composition/schedule_clip.dart';

/// One clip placed at an absolute position on the combined timeline.
///
/// [ScheduledSegment] is the atomic answer to "what is playing at
/// time t": a clip, and where it starts and ends on the single clock
/// the player reports. The composer produces these; nothing else
/// assigns coordinates, which keeps the placement arithmetic in one
/// auditable place.
final class ScheduledSegment extends Equatable {
  /// Creates a placed segment.
  const ScheduledSegment({required this.clip, required this.start, required this.end, this.programTime})
    : assert(end >= start, 'A scheduled segment cannot end before it starts.');

  /// The clip occupying this span.
  final ScheduleClip clip;

  /// Combined-timeline time at which the segment begins.
  final Duration start;

  /// Combined-timeline time at which the segment ends.
  final Duration end;

  /// Program time this segment resumes at or cuts out of, for content
  /// segments.
  ///
  /// Null for non-content clips. For content segments this is the
  /// program time at [start]; a content segment never spans a break
  /// (the composer splits it at every cut), so mapping forward is
  /// always `programTime + (combinedTime - start)` within the
  /// segment — which is what makes a seek on a broken timeline
  /// resolvable without walking the whole segment list.
  final Duration? programTime;

  /// Length of this segment on the combined timeline.
  Duration get duration => end - start;

  /// The segment's [MediaSegment] geometry, for overlay layers that
  /// only need ranges and labels.
  MediaSegment toMediaSegment() => MediaSegment(
    start: start,
    duration: duration,
    label: clip.kind.name,
    attributes: <String, Object?>{if (clip.id != null) 'clipId': clip.id, ...clip.attributes},
  );

  /// Whether [time] falls inside this segment, end-exclusive.
  bool covers(Duration time) => time >= start && time < end;

  /// Program time for [time] inside this content segment.
  ///
  /// Returns null for a non-content segment or a [time] outside it —
  /// a wrong answer here would silently resume the program at the
  /// wrong place, so an out-of-range ask gets no answer.
  Duration? programTimeAt(Duration time) {
    if (!covers(time) || programTime == null) {
      return null;
    }
    return programTime! + (time - start);
  }

  @override
  List<Object?> get props => <Object?>[clip, start, end, programTime];
}

/// Where the playhead is on a composed schedule.
///
/// The navigator and the host read the same fact from here: which
/// clip is under the playhead, where inside that clip the playhead
/// sits, and — for content — what program time that corresponds to
/// (resume position, progress bars, DVR mapping, analytics).
final class SchedulePosition extends Equatable {
  /// Creates a position.
  const SchedulePosition({required this.segment, required this.localTime, this.programTime});

  /// The segment under the playhead.
  final ScheduledSegment segment;

  /// Time since the segment began.
  final Duration localTime;

  /// Program time under the playhead, when the segment is content.
  final Duration? programTime;

  /// The clip under the playhead.
  ScheduleClip get clip => segment.clip;

  /// What kind of clip is playing.
  ClipKind get kind => segment.clip.kind;

  @override
  List<Object?> get props => <Object?>[segment, localTime, programTime];
}

/// A [PlaybackSchedule] resolved onto one absolute timeline.
///
/// The composer's product: ordered, non-overlapping [segments] that
/// tile the whole combined clock, plus [totalDuration]. Consumers ask
/// it questions only — the playhead never moves anything.
///
/// Responsibilities:
///
/// - answer position and boundary questions in constant or linear time
///
/// It does not:
///
/// - re-plan (it is immutable by construction)
/// - observe the playhead
///
/// Those belong to:
///
/// - TimelineComposer
/// - ScheduleNavigator
final class ComposedSchedule extends Equatable {
  /// Creates a composed schedule from placed [segments].
  ComposedSchedule({required this.segments})
    : assert(_tilesWithoutGaps(segments), 'Composed segments must be ordered and gap-free.');

  /// The empty schedule: no clips, no timeline.
  static final ComposedSchedule empty = ComposedSchedule(segments: const []);

  /// Every clip in placement order, tiling the combined clock.
  final List<ScheduledSegment> segments;

  /// Total length of the combined timeline.
  Duration get totalDuration {
    if (segments.isEmpty) {
      return Duration.zero;
    }
    return segments.last.end;
  }

  /// The segment under [time], or null when past the end.
  ScheduledSegment? segmentAt(Duration time) {
    for (final segment in segments) {
      if (segment.covers(time)) {
        return segment;
      }
    }
    return null;
  }

  /// Where the playhead is on this schedule.
  ///
  /// A [time] past the end clamps into the final segment's end and is
  /// reported at that boundary — the navigator treats "at the end" as
  /// a completed playhead, not a miss.
  SchedulePosition positionAt(Duration time) {
    if (segments.isEmpty) {
      throw StateError('positionAt called on an empty ComposedSchedule.');
    }
    final clamped = time < Duration.zero ? Duration.zero : time;
    for (final segment in segments) {
      if (segment.covers(clamped)) {
        return SchedulePosition(
          segment: segment,
          localTime: clamped - segment.start,
          programTime: segment.programTimeAt(clamped),
        );
      }
    }
    final last = segments.last;
    return SchedulePosition(segment: last, localTime: last.duration, programTime: last.programTimeAt(last.end));
  }

  /// The next segment boundary at or after [time].
  ///
  /// The navigator's wake-up signal: this is the combined time at
  /// which the playing clip changes, and the only time a correct
  /// schedule demands the host act.
  Duration? nextBoundary(Duration time) {
    for (final segment in segments) {
      if (segment.end > time) {
        return segment.end;
      }
    }
    return null;
  }

  static bool _tilesWithoutGaps(List<ScheduledSegment> segments) {
    var cursor = Duration.zero;
    for (final segment in segments) {
      if (segment.start != cursor) {
        return false;
      }
      if (segment.end <= segment.start) {
        return false;
      }
      cursor = segment.end;
    }
    return true;
  }

  @override
  List<Object?> get props => <Object?>[segments];
}
