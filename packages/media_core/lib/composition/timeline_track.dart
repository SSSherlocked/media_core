import 'package:equatable/equatable.dart';
import 'package:media_core/composition/media_timeline.dart' show MediaTimeline;
import 'package:media_core/source/media_track.dart';

/// One essence track placed on a shared presentation timeline.
///
/// A [MediaTrack]'s [MediaTrack.startOffset] says where its media
/// begins relative to its period; a [TimelineTrack]'s [offset] says
/// where that media sits on the timeline the player presents, after
/// the earliest track has been normalized to zero. The two differ by
/// the origin shift [MediaTimeline.from] applies, and reading only
/// the raw `startOffset` is how two DASH periods with a large common
/// base offset (a `periodStart` in the manifest) would appear to
/// start late.
///
/// Responsibilities:
///
/// - convert between this track's media time and presentation time
///
/// It does not:
///
/// - know the track's duration (inspection owns that)
/// - schedule demuxer seeks
///
/// Those belong to:
///
/// - SourceInspector
/// - PlayerAdapter
final class TimelineTrack extends Equatable {
  /// Places [track] on the presentation timeline at [offset].
  const TimelineTrack({required this.track, this.offset = Duration.zero});

  /// The essence this entry positions.
  final MediaTrack track;

  /// Where the track's media time zero sits on the presentation
  /// timeline.
  ///
  /// Always non-negative: [MediaTimeline.from] shifts every track so
  /// the earliest one lands exactly at zero.
  final Duration offset;

  /// Whether the track sits exactly at the presentation origin.
  bool get isAtOrigin => offset == Duration.zero;

  /// Converts a position in this track's media to presentation time.
  Duration presentationTimeFor(Duration mediaTime) => mediaTime + offset;

  /// Converts a presentation position to this track's media time.
  ///
  /// Can return a negative duration for a presentation time earlier
  /// than the track's own start; callers deciding whether to show
  /// this track must treat a negative result as "not started yet".
  Duration mediaTimeFor(Duration presentationTime) => presentationTime - offset;

  @override
  List<Object?> get props => <Object?>[track, offset];
}
