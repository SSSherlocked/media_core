import 'package:equatable/equatable.dart';
import 'package:media_core/composition/playback_schedule.dart' show PlaybackSchedule;
import 'package:media_core/composition/schedule_clip.dart';
import 'package:meta/meta.dart';

/// Where a break attaches to the program.
///
/// [BreakPosition] answers one question — "when may this break start"
/// — in a form the composer can sort without parsing a manifest. The
/// three cases are exhaustive by design: the VAST/CSAI shape has no
/// fourth placement.
sealed class BreakPosition {
  /// Creates a break position.
  const BreakPosition();

  /// Where the break sits in program time, as an offset.
  ///
  /// Pre-roll is zero and post-roll is [PostRoll.programDuration], so
  /// sorting by this value is the whole placement order; the named
  /// subtypes stay for intent, readability and validation (a mid-roll
  /// at zero is almost certainly a bug, and an offset makes that
  /// visible).
  Duration get programOffset;

  /// Whether this position is the pre-roll.
  bool get isPreRoll => this is PreRoll;

  /// Whether this position is the post-roll.
  bool get isPostRoll => this is PostRoll;
}

/// Before the program: the entry point every viewer sees.
@immutable
final class PreRoll extends BreakPosition {
  /// Creates a pre-roll position.
  const PreRoll();

  @override
  Duration get programOffset => Duration.zero;

  @override
  bool operator ==(Object other) => other is PreRoll;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'PreRoll()';
}

/// At an explicit program offset.
///
/// A negative offset is rejected at construction, so a malformed
/// feed cannot silently reorder a break to before the program starts.
@immutable
final class AtProgramOffset extends BreakPosition {
  /// Creates a break starting [programTime] into the program.
  AtProgramOffset(this.programTime) : assert(!programTime.isNegative, 'A mid-roll offset cannot be negative.');

  /// Program time at which the break cuts in.
  final Duration programTime;

  @override
  Duration get programOffset => programTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AtProgramOffset && other.programTime == programTime;

  @override
  int get hashCode => Object.hash(AtProgramOffset, programTime);

  @override
  String toString() => 'AtProgramOffset($programTime)';
}

/// After the program: the tail break.
///
/// Carries the program duration because "the end of the timeline"
/// only exists once you know how long the content is; the composer
/// supplies it and an offset can be validated against it.
@immutable
final class PostRoll extends BreakPosition {
  /// Creates a post-roll after a program of [programDuration].
  PostRoll(this.programDuration)
    : assert(!programDuration.isNegative, 'A post-roll needs a non-negative program duration.');

  /// The program length the post-roll follows.
  final Duration programDuration;

  @override
  Duration get programOffset => programDuration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PostRoll && other.programDuration == programDuration;

  @override
  int get hashCode => Object.hash(PostRoll, programDuration);

  @override
  String toString() => 'PostRoll($programDuration)';
}

/// A group of clips that cuts into the program at one position.
///
/// [MediaBreak] models an ad pod (or any interruption block): one
/// position on the program, one ordered list of creatives. The
/// internal order matters (pod sequences pay per slot), the grouping
/// matters (a break completes when its last clip finishes), and the
/// two are independent of where the break sits.
///
/// Responsibilities:
///
/// - bind clips to one placement
///
/// It does not:
///
/// - know absolute timeline coordinates (that is ScheduledSegment,
///   assigned by TimelineComposer once it has all breaks and the
///   program length)
/// - fire tracking
///
/// Those belong to:
///
/// - ComposedSchedule
/// - the host
final class MediaBreak extends Equatable {
  /// Creates a break at [position] with [clips] in playback order.
  MediaBreak({required this.position, required this.clips})
    : assert(clips.isNotEmpty, 'A break with no clips cannot be scheduled.');

  /// Where this break attaches to the program.
  final BreakPosition position;

  /// The clips in this break, in the order they play.
  ///
  /// Breaks of kind content are rejected by [PlaybackSchedule] rather
  /// than silently honored: a "break" that contains the program is a
  /// playlist, not an interruption, and pretending otherwise would
  /// hide a real authoring mistake behind working code.
  final List<ScheduleClip> clips;

  /// Total time this break occupies once placed.
  Duration get totalDuration {
    var total = Duration.zero;
    for (final clip in clips) {
      total += clip.duration;
    }
    return total;
  }

  @override
  List<Object?> get props => <Object?>[position, clips];
}
