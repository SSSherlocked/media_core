import 'package:equatable/equatable.dart';
import 'package:media_core/fallback/quality_fallback.dart' show QualityFallback;
import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/kernel/player_kernel.dart' show PlayerKernel;
import 'package:media_core/quality/quality_candidate.dart';

/// Result of one quality switch.
enum QualitySwitchResult {
  /// The new source is open and the playhead landed back on it.
  applied,

  /// Nothing changed: the requested candidate is already the open
  /// one. Reported rather than silently returning success, because a
  /// host that logged "switched to 1080p" when no switch happened
  /// would be writing fiction into its own analytics.
  alreadyCurrent,

  /// The switch failed mid-flight.
  ///
  /// [QualitySwitchOutcome.restored] says whether the handle was
  /// rolled back to the previous source; when rollback itself
  /// failed, the handle is on whatever the last open left it on, and
  /// only the host's error surface can decide what to show.
  failed,
}

/// One quality switch's outcome, including where the playhead landed.
final class QualitySwitchOutcome extends Equatable {
  /// Creates an outcome.
  const QualitySwitchOutcome({
    required this.result,
    required this.from,
    required this.to,
    this.resumedAt,
    this.error,
    this.restored = false,
  });

  /// What happened.
  final QualitySwitchResult result;

  /// The candidate that was current when the switch began, null if
  /// none was.
  final QualityCandidate? from;

  /// The candidate that was requested.
  final QualityCandidate to;

  /// Media time the playhead landed at, when a resume happened.
  final Duration? resumedAt;

  /// The failure, when [result] is [QualitySwitchResult.failed].
  final Object? error;

  /// Whether the previous source was re-opened after a failure.
  final bool restored;

  /// Whether playback is now on [to].
  bool get applied => result == QualitySwitchResult.applied;

  @override
  List<Object?> get props => <Object?>[result, from, to, resumedAt, error, restored];
}

/// Switches a live [PlayerHandle] between quality candidates without
/// losing the viewer's position.
///
/// This is the piece the existing [QualityFallback] does not cover:
/// fallback walks candidates *because playback failed*, and needs no
/// continuity because the viewer was already stuck. A user tapping
/// "4K" mid-scene is the opposite case — everything is working, and
/// the whole value of the switch is that the scene does not restart.
///
/// The sequence a switch performs:
///
/// 1. capture [PlayerHandle.position] plus rate/volume and whether
///    playback was active — the facts that must survive the change;
/// 2. `PlayerHandle.openMedia` the new candidate's source;
/// 3. seek back to the captured position, which is only meaningful
///    because every candidate here is the *same program* encoded
///    differently — a switch between different programs would be a
///    playlist move, and this class does not pretend to know that
///    difference, so hosts must only ever offer alternate encodings
///    of one title as candidates;
/// 4. restore rate/volume and the playing-or-paused condition.
///
/// A failure at step 2 or 3 rolls the handle back to the previous
/// candidate (same position-capture, reopened, seeked) and reports
/// [QualitySwitchOutcome.restored]; a rollback that itself fails
/// reports [QualitySwitchResult.failed] with `restored: false` rather
/// than pretending nothing happened — the handle's actual state is
/// the only honest answer available.
///
/// Responsibilities:
///
/// - move a live handle between encodings of the same media
/// - report exactly where the playhead landed
///
/// It does not:
///
/// - choose candidates (ABR logic is a host decision; [QualityFallback]
///   is the failure-driven one)
/// - persist a preference
/// - survive the handle being disposed mid-switch
///
/// Those belong to:
///
/// - the host
/// - the host
/// - the host
final class QualitySwitchController {
  /// Creates a controller for [handle] with an initial candidate.
  QualitySwitchController({required this.handle, this.current});

  /// The handle being switched.
  final PlayerHandle handle;

  /// The candidate last known to be open.
  ///
  /// Assign this to record a candidate as open without playing it, for
  /// hosts that opened media through another path (first play via
  /// [PlayerKernel.createFromMedia]) and want subsequent switches to
  /// have a baseline to roll back to.
  QualityCandidate? current;

  /// Switches the handle to [candidate].
  ///
  /// No-op-as-[QualitySwitchResult.alreadyCurrent] when [candidate]
  /// is the current one; see the class doc for the full sequence.
  Future<QualitySwitchOutcome> switchTo(QualityCandidate candidate) async {
    final previous = current;

    if (previous != null && previous.source == candidate.source) {
      return QualitySwitchOutcome(
        result: QualitySwitchResult.alreadyCurrent,
        from: previous,
        to: candidate,
        resumedAt: handle.position,
      );
    }

    final resumeAt = handle.position;
    final wasPlaying = handle.playback.isPlaying;
    final volume = handle.playback.volume;
    final rate = handle.playback.rate;

    try {
      await _apply(candidate, resumeAt, wasPlaying, volume, rate);
      current = candidate;
      return QualitySwitchOutcome(
        result: QualitySwitchResult.applied,
        from: previous,
        to: candidate,
        resumedAt: resumeAt,
      );
    } on Object catch (error) {
      var restored = false;
      if (previous != null) {
        try {
          await _apply(previous, resumeAt, wasPlaying, volume, rate);
          restored = true;
        } on Object catch (_) {
          // The rollback failed too: the handle sits on whatever the
          // last open left it on, and `restored: false` is the whole
          // truth of that.
        }
      }
      return QualitySwitchOutcome(
        result: QualitySwitchResult.failed,
        from: previous,
        to: candidate,
        error: error,
        restored: restored,
      );
    }
  }

  Future<void> _apply(
    QualityCandidate candidate,
    Duration resumeAt,
    bool wasPlaying,
    double volume,
    double rate,
  ) async {
    await handle.openMedia(candidate.source, autoPlay: false);
    if (resumeAt > Duration.zero) {
      await handle.seek(resumeAt);
    }
    await handle.setVolume(volume);
    await handle.setRate(rate);
    if (wasPlaying) {
      await handle.play();
    }
  }
}
