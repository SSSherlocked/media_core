import 'package:equatable/equatable.dart';
import 'package:media_core/composition/schedule_navigator.dart' show ScheduleNavigator;
import 'package:media_core/source/media_source.dart';

/// What role a scheduled clip plays on the combined timeline.
///
/// `kind` is the only thing the schedule machine itself branches on:
/// entering and leaving [advertisement] segments is what interrupts
/// playback and fires tracking, while every other kind flows straight
/// through. What the kinds mean to the user — an ad break versus a
/// filler versus the next episode — is the host's vocabulary, not the
/// composer's.
enum ClipKind {
  /// The program itself: the one clip kind whose internal clock the
  /// schedule tracks so a break can resume exactly where it cut in.
  content,

  /// A paid advertisement. The schedule refuses to cross an
  /// advertisement boundary while the playhead moves, and
  /// [ScheduleNavigator] surfaces skip decisions only for this kind.
  advertisement,

  /// Channel furniture between programs: promos, bumpers, filler.
  /// Passes through like [content] but is not itself resumable.
  filler,
}

/// Extension helpers for [ClipKind].
extension ClipKindX on ClipKind {
  /// Whether playback must be interrupted when entering or leaving
  /// this kind of clip.
  ///
  /// Only [ClipKind.advertisement] interrupts: a filler or a program
  /// continuation is just more timeline. This predicate is the single
  /// definition the navigator branches on, so a new pass-through kind
  /// never has to touch its code.
  bool get isInterruptive => this == ClipKind.advertisement;
}

/// One media item placed on a schedule.
///
/// A [ScheduleClip] is a duration-typed [MediaSource] with a role: the
/// schedule cannot plan against a source whose length it does not
/// know, so [duration] is required and is the host's answer to
/// "exactly how long does this occupy the timeline" (an ad's VAST
/// duration, a program's manifest duration, a bumper's fixed length).
///
/// Responsibilities:
///
/// - bind a media source to a role and a duration
///
/// It does not:
///
/// - carry placement rules (that is MediaBreak)
/// - track its own playback state
///
/// Those belong to:
///
/// - MediaBreak
/// - ScheduleNavigator
final class ScheduleClip extends Equatable {
  /// Creates a scheduled clip.
  ScheduleClip({
    required this.source,
    required this.duration,
    this.kind = ClipKind.content,
    this.id,
    this.skipAfter,
    this.clickThroughUrl,
    this.trackingUris = const <Uri>[],
    this.attributes = const <String, Object?>{},
  }) : assert(!duration.isNegative, 'A scheduled clip must occupy a non-negative span.'),
       assert(skipAfter == null || !skipAfter.isNegative, 'A skip point cannot precede the start of its clip.');

  /// The media to present for this clip.
  final MediaSource source;

  /// How long the clip occupies the combined timeline.
  ///
  /// Required, not inferred: an ad server that reports a 15-second
  /// creative and a manifest that disagrees about the program's
  /// length are different failure modes, and the schedule wants to be
  /// able to name which one it hit.
  final Duration duration;

  /// The role this clip plays. See [ClipKind].
  final ClipKind kind;

  /// Optional stable id (an ad slot id, a VAST AdId, an episode id).
  final String? id;

  /// When inside an advertisement the viewer may dismiss it.
  ///
  /// Null means "no skip is offered". Meaningful only for
  /// [ClipKind.advertisement]; the navigator reports a non-null value
  /// on any other kind as an unskippable pass-through, because the
  /// decision rule lives in one place, not in kind-shaped branches.
  final Duration? skipAfter;

  /// Optional click-through destination for a tappable advertisement.
  final Uri? clickThroughUrl;

  /// Tracking beacons to ping at creative lifecycle points.
  ///
  /// URIs only; firing them (and when) is host behavior — a schedule
  /// machine with network side effects could not be a pure function.
  final List<Uri> trackingUris;

  /// Producer-specific attributes; opaque to media_core.
  final Map<String, Object?> attributes;

  /// The end of the clip relative to whatever it is placed after.
  Duration get relativeEnd => duration;

  /// Creates a copy with modifications.
  ///
  /// TimelineComposer uses [duration] to narrow the program into the
  /// slice between two breaks; identity fields (source, kind, id)
  /// carry through so a content slice and the program are recognizably
  /// the same clip.
  ScheduleClip copyWith({
    MediaSource? source,
    Duration? duration,
    ClipKind? kind,
    String? id,
    Duration? skipAfter,
    Uri? clickThroughUrl,
    List<Uri>? trackingUris,
    Map<String, Object?>? attributes,
  }) {
    return ScheduleClip(
      source: source ?? this.source,
      duration: duration ?? this.duration,
      kind: kind ?? this.kind,
      id: id ?? this.id,
      skipAfter: skipAfter ?? this.skipAfter,
      clickThroughUrl: clickThroughUrl ?? this.clickThroughUrl,
      trackingUris: trackingUris ?? this.trackingUris,
      attributes: attributes ?? this.attributes,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    source,
    duration,
    kind,
    id,
    skipAfter,
    clickThroughUrl,
    trackingUris,
    attributes,
  ];
}
