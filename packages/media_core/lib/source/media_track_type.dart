import 'package:media_core/source/library.dart' show MediaTrack, PlayerSource, SourceMediaType;

/// Describes what kind of media a [MediaTrack] carries.
///
/// [MediaTrackType] is a track-level classification, distinct from the
/// source-level [SourceMediaType] used by [PlayerSource]: a source can
/// be `mixed` while each individual track inside it is still one of
/// [video], [audio] or [subtitle].
///
/// Responsibilities:
///
/// - classify a single [MediaTrack]
/// - drive composite-source grouping
///
/// It does not:
///
/// - describe a whole source
/// - express codec or container details
/// - select a backend
///
/// Those belong to:
///
/// - MediaSource
/// - MediaTrack
/// - PlayerAdapterSelector
enum MediaTrackType {
  /// Video content.
  video,

  /// Audio content.
  audio,

  /// Subtitle or caption content.
  subtitle,
}

/// Extensions for [MediaTrackType].
extension MediaTrackTypeX on MediaTrackType {
  /// Whether the track carries video.
  bool get isVideo => this == MediaTrackType.video;

  /// Whether the track carries audio.
  bool get isAudio => this == MediaTrackType.audio;

  /// Whether the track carries subtitles.
  bool get isSubtitle => this == MediaTrackType.subtitle;

  /// Whether the track is time-based.
  ///
  /// Subtitles are keyed to a timeline but do not drive the playhead
  /// themselves, so only video and audio are treated as time-based here.
  bool get isTimeBased => isVideo || isAudio;

  /// Returns the stable string representation of this track type.
  String get value => name;
}
