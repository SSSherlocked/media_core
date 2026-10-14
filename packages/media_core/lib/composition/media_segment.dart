import 'package:equatable/equatable.dart';

/// A named range on a presentation timeline.
///
/// The composition layer's generic unit of "a piece of the timeline":
/// an HLS/DASH segment boundary, a chapter marker, an ad break, or a
/// gap left by a removed section all share this shape — a position, a
/// length, and opaque attributes the producing layer interprets.
///
/// Responsibilities:
///
/// - express a presentation-time range with a label and attributes
/// - answer containment questions ([covers], [intersects])
///
/// It does not:
///
/// - reference the bytes or URL of an actual media segment
/// - schedule anything
///
/// Those belong to:
///
/// - the producing manifest layer
/// - PlayerAdapter
final class MediaSegment extends Equatable {
  /// Creates a segment starting at [start] on the presentation
  /// timeline.
  MediaSegment({required this.start, required this.duration, this.label, this.attributes = const <String, Object?>{}})
    : assert(!duration.isNegative, 'Segment duration must not be negative.');

  /// Where the segment begins on the presentation timeline.
  final Duration start;

  /// How long the segment lasts.
  final Duration duration;

  /// Optional human-readable name (chapter title, ad slot id, ...).
  final String? label;

  /// Producer-specific attributes; opaque to media_core.
  final Map<String, Object?> attributes;

  /// Where the segment ends on the presentation timeline.
  Duration get end => start + duration;

  /// Whether [time] falls inside this segment, end-exclusive.
  bool covers(Duration time) => time >= start && time < end;

  /// Whether this segment overlaps [other].
  bool intersects(MediaSegment other) => start < other.end && other.start < end;

  /// The segment shifted by [delta] on the timeline.
  MediaSegment shiftedBy(Duration delta) =>
      MediaSegment(start: start + delta, duration: duration, label: label, attributes: attributes);

  @override
  List<Object?> get props => <Object?>[start, duration, label, attributes];
}
