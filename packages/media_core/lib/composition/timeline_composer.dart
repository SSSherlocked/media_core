import 'package:media_core/composition/composed_schedule.dart';
import 'package:media_core/composition/playback_schedule.dart';
import 'package:media_core/composition/schedule_clip.dart';

/// The pure placement engine of the composition layer.
///
/// `TimelineComposer` turns a `PlaybackSchedule` (program plus
/// breaks) into a `ComposedSchedule` (one absolute clock of placed
/// segments). It is a pure function of its input — no clock, no
/// player, no I/O — because the question "what plays at time t" has
/// exactly one answer, and the layer that computes it must be the
/// layer that can be tested without a device.
///
/// The rules the composer owns:
///
/// - breaks are ordered by their position on the program, so a feed
///   that emits an offset-90 pod and a post-roll in any order still
///   plays them in the right order;
/// - a break never moves a later break: placement is computed from
///   program time forward, combined time accumulates behind it;
/// - content is split at every cut, so a content segment's program
///   time and combined time differ by a constant inside the segment —
///   the property that makes `ScheduledSegment.programTimeAt` exact
///   and a resume after an ad land where the viewer left off;
/// - a zero-duration clip is dropped, not placed: a 15-second ad
///   reported with 0 duration by a failing tag would otherwise eat a
///   coordinate and leave an unplayable gap.
final class TimelineComposer {
  /// The composer has no state; calling it is a pure computation.
  const TimelineComposer();

  /// Places [schedule]'s clips onto one absolute clock.
  ///
  /// Passes when [schedule] has no breaks: the program is the whole
  /// timeline. Fails only on authoring errors the schedule type
  /// cannot already reject at construction (overlap with a program
  /// shorter than a declared mid-roll is checked here because the
  /// program length is the last piece to arrive).
  ComposedSchedule compose(PlaybackSchedule schedule) {
    final segments = <ScheduledSegment>[];
    var cursor = Duration.zero;

    void place(ScheduleClip clip, {Duration? programTime}) {
      if (clip.duration <= Duration.zero) {
        return;
      }
      segments.add(ScheduledSegment(clip: clip, start: cursor, end: cursor + clip.duration, programTime: programTime));
      cursor += clip.duration;
    }

    // Sort by program offset, then by pre/post identity so equal
    // offsets keep intent: a pre-roll at zero precedes a mid-roll
    // authored at zero, and a post-roll sits at the program end.
    final orderedBreaks = schedule.sortedBreaks;

    final programDuration = schedule.program.duration;
    var programConsumed = Duration.zero;

    for (final mediaBreak in orderedBreaks) {
      final cutAt = mediaBreak.position.programOffset;
      if (cutAt > programDuration) {
        // A mid-roll declared past the end of a short program is a
        // feed bug; clamping it forward would replay the tail twice.
        continue;
      }

      final contentSlice = cutAt - programConsumed;
      if (contentSlice > Duration.zero) {
        place(
          schedule.clipCoveringProgram(from: programConsumed, duration: contentSlice),
          programTime: programConsumed,
        );
        programConsumed += contentSlice;
      }

      mediaBreak.clips.forEach(place);
    }

    // The program tail after the last break — or the whole program
    // when there are none.
    final tail = programDuration - programConsumed;
    if (tail > Duration.zero) {
      place(
        schedule.clipCoveringProgram(from: programConsumed, duration: tail),
        programTime: programConsumed,
      );
    }

    if (segments.isEmpty) {
      return ComposedSchedule.empty;
    }
    return ComposedSchedule(segments: segments);
  }
}
