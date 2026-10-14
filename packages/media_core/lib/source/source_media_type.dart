import 'package:media_core/media_core.dart' show PlayerInfo, SourceFormat, SourceProtocol, SourceType;

/// Describes the general media content type of a source.
///
/// [SourceMediaType] describes what kind of media content a source
/// represents. It is intentionally independent from:
///
/// - [SourceType], which describes the source category.
/// - [SourceProtocol], which describes how the source is accessed.
/// - [SourceFormat], which describes the container or file format.
///
/// Detailed stream information such as codecs, bitrate, resolution, and
/// track information belongs to media inspection and [PlayerInfo].
enum SourceMediaType {
  /// Unknown or not yet determined.
  unknown,

  /// Video content.
  video,

  /// Audio content.
  audio,

  /// Subtitle or caption content.
  subtitle,

  /// Still image content.
  image,

  /// A media playlist or collection.
  playlist,

  /// A source containing multiple media types.
  mixed,
}

/// Extensions for [SourceMediaType].
extension SourceMediaTypeX on SourceMediaType {
  /// Whether the media type is unknown.
  bool get isUnknown => this == SourceMediaType.unknown;

  /// Whether the media type is known.
  bool get isKnown => this != SourceMediaType.unknown;

  /// Whether this source contains video content.
  bool get isVideo => this == SourceMediaType.video;

  /// Whether this source contains audio content.
  bool get isAudio => this == SourceMediaType.audio;

  /// Whether this source contains subtitle content.
  bool get isSubtitle => this == SourceMediaType.subtitle;

  /// Whether this source contains image content.
  bool get isImage => this == SourceMediaType.image;

  /// Whether this source represents a playlist.
  bool get isPlaylist => this == SourceMediaType.playlist;

  /// Whether this source may contain multiple media types.
  bool get isMixed => this == SourceMediaType.mixed;

  /// Whether this is a playable media type.
  ///
  /// Playlists are source descriptions rather than directly playable media.
  bool get isPlayable {
    return this == SourceMediaType.video || this == SourceMediaType.audio || this == SourceMediaType.image;
  }

  /// Whether this type represents time-based media.
  ///
  /// Video and audio normally have a playback timeline.
  bool get isTimeBased {
    return this == SourceMediaType.video || this == SourceMediaType.audio;
  }

  /// Whether this type is auxiliary content.
  bool get isAuxiliary {
    return this == SourceMediaType.subtitle || this == SourceMediaType.image;
  }

  /// Returns the stable string representation of this media type.
  String get value => name;
}
