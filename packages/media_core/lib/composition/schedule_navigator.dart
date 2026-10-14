import 'package:media_core/composition/composed_schedule.dart';
import 'package:media_core/composition/schedule_clip.dart';
import 'package:meta/meta.dart';

/// Something the host must do to keep a composed schedule honest.
///
/// The navigator never touches a player — it observes the playhead
/// and says when the clip under the playhead changes. [OpenClip]
/// means "call `handle.openMedia` with this clip's source (and seek
/// to its `seekTo` if non-null)"; [ScheduleComplete] means the
/// timeline ended.
sealed class ScheduleAction {
  /// Creates an action.
  const ScheduleAction();
}

/// Enter or resume a clip whose media is not yet the open one.
@immutable
final class OpenClip extends ScheduleAction {
  /// Creates an open instruction.
  const OpenClip(this.clip, {this.seekTo});

  /// The clip to present.
  final ScheduleClip clip;

  /// Program-local media time to start at, when not the clip's head.
  ///
  /// Content segments carry their `programTime` here so resuming after
  /// an ad starts the program exactly where it was cut, and a user
  /// seek across a break lands on the right side of the next cut.
  final Duration? seekTo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OpenClip && other.clip == clip && other.seekTo == seekTo;

  @override
  int get hashCode => Object.hash(OpenClip, clip, seekTo);

  @override
  String toString() => 'OpenClip(${clip.kind}${seekTo == null ? '' : ' @ $seekTo'})';
}

/// The combined timeline has been played through.
@immutable
final class ScheduleComplete extends ScheduleAction {
  /// Creates a completion.
  const ScheduleComplete();

  @override
  bool operator ==(Object other) => other is ScheduleComplete;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ScheduleComplete()';
}

/// The decision the navigator makes for one playhead observation.
///
/// [actions] is what must happen between the last observation and
/// now; [position] carries the ad-clock facts a host needs to render
/// "this ad will be skippable in 5s" (its `localTime` against the
/// clip's `skipAfter` and `duration`) without reaching into segment
/// internals, and [skipAvailable] answers the one question
/// the schedule forbids the host to guess.
final class ScheduleObservation {
  /// Creates an observation.
  const ScheduleObservation({required this.position, required this.actions, this.skipAvailable = false});

  /// Where the playhead landed, or null when the schedule is empty.
  final SchedulePosition? position;

  /// Ordered host actions for this tick; may be empty.
  final List<ScheduleAction> actions;

  /// Whether an advertisement under the playhead may be dismissed now.
  final bool skipAvailable;

  @override
  String toString() =>
      'ScheduleObservation(${position?.kind}, actions: ${actions.length}, '
      'skip: $skipAvailable)';
}

/// The pure playhead state machine over a [ComposedSchedule].
///
/// Feed it positions as the player reports them ([observe]) and it
/// says what the host must do: open the next clip when the timeline
/// crosses into an ad or back into content, seek when a segment starts
/// inside its media (a resume after a break, or a user seek), and
/// complete when the end is reached. It keeps exactly one piece of
/// state — which clip it last opened — because everything else is a
/// question the composed schedule already answers deterministically.
///
/// Why it stays pure:
///
/// - crossing into an ad means calling `handle.openMedia(ad.source)`;
///   the navigator could do that itself, but then the machine that
///   defines *when* would also own *how*, and no test of the when
///   would run without a player;
/// - seeks are user actions arriving out of order (position A → C → B):
///   the state machine tolerates that because it compares against the
///   schedule, not against the previous tick.
///
/// Responsibilities:
///
/// - translate a playhead time into host actions
/// - own skip-eligibility for the clip under the playhead
///
/// It does not:
///
/// - drive the player or read its position
/// - fire tracking beacons
///
/// Those belong to:
///
/// - the host (PlayerHandle)
/// - the host's ad-analytics layer
final class ScheduleNavigator {
  /// Creates a navigator over [schedule], starting before any clip
  /// has been opened.
  ScheduleNavigator(this.schedule);

  /// The composed schedule being followed.
  final ComposedSchedule schedule;

  ScheduledSegment? _opened;

  /// The clip currently believed to be the open one, if any.
  ScheduledSegment? get openedSegment => _opened;

  /// Observes the playhead at [time].
  ///
  /// Call it on every position tick and after every seek. Returns the
  /// actions the host must perform, in order — typically empty in the
  /// middle of a clip, one [OpenClip] at a boundary, and
  /// [ScheduleComplete] once past the end.
  ScheduleObservation observe(Duration time) {
    if (schedule.segments.isEmpty) {
      return const ScheduleObservation(position: null, actions: <ScheduleAction>[ScheduleComplete()]);
    }

    final position = schedule.positionAt(time);
    final atEnd = time >= schedule.totalDuration;

    final actions = <ScheduleAction>[];
    final segment = position.segment;

    if (!atEnd && !_sameSegment(_opened, segment)) {
      final seekTo = segment.clip.kind == ClipKind.content && segment.programTime != null
          ? segment.programTimeAt(time) ?? segment.programTime
          : null;
      actions.add(OpenClip(segment.clip, seekTo: seekTo));
      _opened = segment;
    }

    final skip =
        position.kind == ClipKind.advertisement &&
        segment.clip.skipAfter != null &&
        position.localTime >= segment.clip.skipAfter!;

    if (atEnd) {
      actions.add(const ScheduleComplete());
      _opened = null;
    }

    return ScheduleObservation(position: position, actions: actions, skipAvailable: skip);
  }

  /// The next boundary time at or after [time], for hosts that want
  /// to act on a timer rather than on every tick.
  Duration? nextBoundary(Duration time) => schedule.nextBoundary(time);

  static bool _sameSegment(ScheduledSegment? a, ScheduledSegment? b) {
    if (a == null || b == null) {
      return false;
    }
    return identical(a, b) || (a.clip == b.clip && a.start == b.start);
  }
}
