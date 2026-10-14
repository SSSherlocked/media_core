import 'dart:async';

import 'package:media_core/composition/composed_schedule.dart';
import 'package:media_core/composition/playback_schedule.dart';
import 'package:media_core/composition/schedule_clip.dart';
import 'package:media_core/composition/schedule_navigator.dart';
import 'package:media_core/composition/timeline_composer.dart';
import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/playback/player_transport_state.dart';

/// Drives one [PlayerHandle] through a composed [PlaybackSchedule].
///
/// The schedule engine answers "what plays at time t" as a pure
/// function; [ScheduledPlayback] is the side of that function that
/// touches the player. It subscribes to the handle's transport
/// stream, feeds every position to a [ScheduleNavigator], and carries
/// out the resulting actions: opening a clip's media when the
/// timeline crosses into it, seeking to the resume point a content
/// segment carries, and completing when the end passes.
///
/// What the host owns that this class deliberately does not:
///
/// - **ad UI and tracking** — [observationStream] reports every
///   navigator observation, which is where "skippable in 5s", the
///   combined progress bar and VAST beacons belong; a controller that
///   fired tracking would be a controller with network side effects
///   at a moment the host did not choose;
/// - **the pause between clips** — [start] opens the first clip and
///   the handle plays on; hosts that want a black frame between
///   program and ad wrap that themselves;
/// - **user intent** — a viewer drag on the combined bar arrives as
///   [seekCombined]; this class never seeks on its own.
///
/// The navigator keeps its own "which segment did I open" state, so
/// a crossing re-opens media even when the previous open has not
/// reported back yet; [start] awaits the first open, and crossings
/// are dispatched serially so a position burst cannot interleave two
/// openMedia calls.
///
/// Responsibilities:
///
/// - execute the navigator's actions against one handle
/// - expose combined-clock control and observation
///
/// It does not:
///
/// - decide placement (TimelineComposer)
/// - fire tracking or render ad UI
/// - survive a handle swap (create a new controller per handle)
///
/// Those belong to:
///
/// - TimelineComposer
/// - the host
/// - the host
final class ScheduledPlayback {
  /// Creates a controller driving [handle] through [schedule].
  ///
  /// The schedule is composed once at construction: the composed
  /// timeline is fixed for the controller's lifetime, matching the
  /// "immutable by construction" promise of [ComposedSchedule]. A
  /// host that needs a different schedule builds a new controller.
  factory ScheduledPlayback({required PlayerHandle handle, required PlaybackSchedule schedule}) {
    return ScheduledPlayback._(handle: handle, composed: const TimelineComposer().compose(schedule));
  }

  ScheduledPlayback._({required this.handle, required this.composed}) : navigator = ScheduleNavigator(composed);

  /// The handle whose position is observed and whose media is opened.
  final PlayerHandle handle;

  /// The composed timeline this controller plays through.
  final ComposedSchedule composed;

  /// The pure state machine the controller executes on behalf of.
  final ScheduleNavigator navigator;

  final _observations = StreamController<ScheduleObservation>.broadcast();

  StreamSubscription<PlayerTransportState>? _positionSub;
  Future<void> _dispatchTail = Future<void>.value();
  bool _started = false;
  bool _disposed = false;

  /// Every navigator observation, including the ones with no actions.
  ///
  /// Hosts render from this: [ScheduleObservation.skipAvailable] for
  /// a skip button, [ScheduleObservation.position] for a progress bar
  /// in combined time, and a non-empty [ScheduleObservation.actions]
  /// for "a clip just changed now".
  Stream<ScheduleObservation> get observationStream => _observations.stream;

  /// The total length of the combined timeline — the denominator of
  /// the progress bar, not the handle's own [PlayerHandle.duration].
  Duration get totalDuration => composed.totalDuration;

  /// The combined-clock position of the playhead.
  ///
  /// The handle reports media-local time (a resumed program segment
  /// restarts at its own coordinates); this maps it back onto the
  /// single clock the schedule defined.
  Duration get combinedPosition {
    return combinedTimeFor(handle.position);
  }

  /// Maps a media-local handle position to the combined timeline.
  ///
  /// During content the handle is inside the full program source, so
  /// a program position maps to the combined time whose segment's
  /// programTime contains it. Outside content the local time is the
  /// clip's own clock, which the segment's start already aligns.
  Duration combinedTimeFor(Duration mediaPosition) {
    final opened = navigator.openedSegment;
    if (opened == null) {
      return mediaPosition;
    }
    if (opened.clip.kind == ClipKind.content && opened.programTime != null) {
      // Program slice: handle position is program time; find the
      // segment whose program range contains it.
      for (final segment in composed.segments) {
        final programStart = segment.programTime;
        if (programStart == null) {
          continue;
        }
        if (mediaPosition >= programStart && mediaPosition < programStart + segment.duration) {
          return segment.start + (mediaPosition - programStart);
        }
      }
      return opened.start + (mediaPosition - opened.programTime!);
    }
    return opened.start + mediaPosition;
  }

  /// Opens the first clip and starts observing the handle.
  ///
  /// Idempotent: a second call is a no-op, because two subscriptions
  /// to one position stream would dispatch the same crossing twice.
  Future<void> start() async {
    _ensureActive();
    if (_started) {
      return;
    }
    _started = true;

    _positionSub = handle.playbackStream.listen((state) {
      _enqueueObserve(state.position);
    });

    await _dispatch(navigator.observe(Duration.zero));
  }

  /// Jumps the playhead to a combined-timeline position.
  ///
  /// The UI gesture behind a scrubber on a schedule: combined time
  /// across a pre-roll and into content is NOT a seek to that value
  /// in the current media — it is an instruction to the timeline.
  /// This method asks the navigator what lives at the combined time
  /// and performs the open+seek that lands the handle there, then
  /// keeps observing from that point.
  Future<void> seekCombined(Duration combinedTime) async {
    _ensureActive();
    final clamped = combinedTime < Duration.zero
        ? Duration.zero
        : (combinedTime > composed.totalDuration ? composed.totalDuration : combinedTime);
    final segment = composed.positionAt(clamped).segment;

    await _enqueue(() async {
      final needsOpen =
          navigator.openedSegment?.start != segment.start || navigator.openedSegment?.clip != segment.clip;
      if (needsOpen) {
        await handle.openMedia(segment.clip.source, autoPlay: false);
      }
      final target = segment.clip.kind == ClipKind.content && segment.programTime != null
          ? segment.programTimeAt(clamped) ?? segment.programTime!
          : clamped - segment.start;
      await handle.seek(target);
      // The seek moves the handle where the combined time lives; the
      // navigator must learn about it even when no new open was
      // needed, or it would believe the old clip is still fresh.
      await _dispatch(navigator.observe(target));
    });
  }

  /// Releases the position subscription. The handle is not disposed —
  /// its lifecycle belongs to the kernel, not to a schedule.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _positionSub?.cancel();
    _positionSub = null;
    await _observations.close();
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('ScheduledPlayback has been disposed.');
    }
  }

  void _enqueueObserve(Duration position) {
    // Position bursts (a fast seek, a buffering catch-up) must not
    // dispatch the same boundary twice concurrently: every tick is
    // appended to one tail, so crossings act in report order.
    _dispatchTail = _dispatchTail
        .then((_) async {
          if (_disposed) {
            return;
          }
          await _dispatch(navigator.observe(position));
        })
        .catchError((Object error, StackTrace stackTrace) {
          // A failed open must not silently stop the machine; the
          // host sees it on the observation stream it already trusts.
          _observations.addError(error, stackTrace);
        });
  }

  Future<void> _dispatch(ScheduleObservation observation) async {
    if (!_observations.isClosed) {
      _observations.add(observation);
    }
    for (final action in observation.actions) {
      if (action case OpenClip(:final clip, :final seekTo)) {
        await handle.openMedia(clip.source, autoPlay: true);
        if (seekTo != null && seekTo > Duration.zero) {
          await handle.seek(seekTo);
        }
      }
    }
  }

  Future<void> _enqueue(Future<void> Function() work) {
    _ensureActive();
    final next = _dispatchTail.then((_) => work());
    _dispatchTail = next.catchError((Object _, StackTrace _) {});
    return next;
  }
}
