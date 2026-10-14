import 'package:equatable/equatable.dart';
import 'package:media_core/composition/library.dart' show ScheduledSegment;
import 'package:media_core/composition/media_break.dart';
import 'package:media_core/composition/schedule_clip.dart';

/// The authoring shape of "this program, with these interruptions".
///
/// A [PlaybackSchedule] is what a feed or an ad server hands the
/// composer: a program clip, and a set of breaks attached to program
/// time. It says nothing about the combined clock — placement order
/// and absolute coordinates are TimelineComposer's job — which is
/// what lets the same schedule be validated on its own (a mid-roll
/// past the end of a short program is a feed bug, and it can be
/// caught here rather than at first playback).
///
/// Responsibilities:
///
/// - bind a program to its interruptions
/// - normalize break order by program placement
///
/// It does not:
///
/// - assign combined-timeline coordinates
/// - know which clip is playing now
///
/// Those belong to:
///
/// - TimelineComposer
/// - ScheduleNavigator
final class PlaybackSchedule extends Equatable {
  /// Creates a schedule for [program] with [breaks].
  ///
  /// The program must be a [ClipKind.content] clip; every break clip
  /// must be an interruption kind. A schedule is only an
  /// interruption model if the interruptions are not the program —
  /// putting content in a break is an authoring mistake this type
  /// refuses at construction, before it can produce a timeline with
  /// two competing definitions of "the program".
  PlaybackSchedule({required this.program, this.breaks = const <MediaBreak>[]})
    : assert(program.kind == ClipKind.content, 'A schedule program must be a content clip.'),
      assert(
        breaks.every((b) => b.clips.every((c) => c.kind != ClipKind.content)),
        'A break cannot contain content clips; append to a playlist instead.',
      ) {
    _validateAgainstProgram();
  }

  /// A schedule with no breaks: the program alone.
  factory PlaybackSchedule.programOnly(ScheduleClip program) {
    return PlaybackSchedule(program: program);
  }

  /// The program being scheduled.
  final ScheduleClip program;

  /// Breaks, in any authoring order — [sortedBreaks] answers.
  final List<MediaBreak> breaks;

  /// The program's length on its own clock.
  Duration get programDuration => program.duration;

  /// Breaks ordered by where they cut into the program.
  ///
  /// Equal offsets keep intent: a pre-roll precedes an offset authored
  /// at zero, and a post-roll follows a mid-roll authored at the
  /// program end, because the tie-breaker is the position's own rank,
  /// not arrival order.
  List<MediaBreak> get sortedBreaks {
    final ordered = List<MediaBreak>.from(breaks)
      ..sort((a, b) {
        final byOffset = a.position.programOffset.compareTo(b.position.programOffset);
        if (byOffset != 0) {
          return byOffset;
        }
        return _positionRank(a.position).compareTo(_positionRank(b.position));
      });
    return List<MediaBreak>.unmodifiable(ordered);
  }

  /// The program view covering `from .. from+duration` of program time.
  ///
  /// Returns the same source and identity as [program], narrowed to
  /// one span so the composer can place slices of content between
  /// breaks. [from] is not baked into the clip: the entry point is
  /// carried by the placed [ScheduledSegment.programTime] and applied
  /// as a seek when the navigator opens the segment, so a slice and
  /// the whole program stay the same schedule-visible clip and a
  /// resume after an ad is one coordinate lookup, not an identity
  /// change. [from] is validated so a composer that drifted past the
  /// program end fails loudly here instead of placing a clip whose
  /// range does not exist.
  ScheduleClip clipCoveringProgram({required Duration from, required Duration duration}) {
    if (from < Duration.zero || duration <= Duration.zero) {
      throw ArgumentError.value(
        '$from + $duration',
        'duration',
        'A program slice must start inside the program and be non-empty.',
      );
    }
    if (from + duration > program.duration) {
      throw ArgumentError.value(
        '${from + duration}',
        'from + duration',
        'A program slice ending past $programDuration would replay media '
            'the program does not contain.',
      );
    }
    return program.copyWith(duration: duration);
  }

  void _validateAgainstProgram() {
    for (final mediaBreak in breaks) {
      final offset = mediaBreak.position.programOffset;
      if (offset > programDuration) {
        throw ArgumentError.value(
          mediaBreak.position,
          'break.position',
          'A break at $offset exceeds the program length $programDuration; '
              'a mid-roll past the end would replay the program tail.',
        );
      }
      final position = mediaBreak.position;
      if (position is PostRoll && position.programDuration != programDuration) {
        // A post-roll carrying its own idea of the program length that
        // disagrees with the scheduled program would be placed at the
        // stored duration and cut content the viewer never sees the
        // end of. One of the two numbers is wrong, and it is cheaper
        // to say so at construction than to debug a truncated program.
        throw ArgumentError.value(
          position,
          'break.position',
          'A post-roll declared for a ${position.programDuration} program '
              'cannot schedule a $programDuration program.',
        );
      }
    }
  }

  static int _positionRank(BreakPosition position) {
    // Pre before at-zero before post at the same offset.
    if (position is PreRoll) {
      return 0;
    }
    if (position is AtProgramOffset) {
      return 1;
    }
    return 2;
  }

  @override
  List<Object?> get props => <Object?>[program, breaks];
}
