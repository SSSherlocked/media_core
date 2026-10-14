import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/core/library.dart' show PlayerCoreState, PlayerSnapshot;

part 'player_info.freezed.dart';
part 'player_info.g.dart';

/// Descriptive information about the current player and media.
///
/// [PlayerInfo] contains relatively stable descriptive data. Runtime state
/// belongs to [PlayerCoreState], while the complete observable state belongs to
/// [PlayerSnapshot].
@freezed
abstract class PlayerInfo with _$PlayerInfo {
  /// Creates player information.
  const factory PlayerInfo({
    /// Optional title of the current media.
    String? title,

    /// Optional description of the current media.
    String? description,

    /// Optional author, creator, or channel name.
    String? author,

    /// Optional album name.
    String? album,

    /// Optional artist name.
    String? artist,

    /// Optional artwork URL.
    String? artworkUrl,

    /// Optional thumbnail URL.
    String? thumbnailUrl,

    /// Optional media duration in milliseconds.
    int? durationMs,

    /// Optional width of the video.
    int? width,

    /// Optional height of the video.
    int? height,

    /// Optional video frame rate.
    double? frameRate,

    /// Optional video bitrate in bits per second.
    int? videoBitrate,

    /// Optional audio bitrate in bits per second.
    int? audioBitrate,

    /// Optional container or stream format.
    String? format,

    /// Optional video codec.
    String? videoCodec,

    /// Optional audio codec.
    String? audioCodec,

    /// Optional subtitle codec.
    String? subtitleCodec,

    /// Optional language of the primary audio stream.
    String? audioLanguage,

    /// Optional language of the primary subtitle stream.
    String? subtitleLanguage,

    /// Optional container metadata.
    @Default(<String, String>{}) Map<String, String> metadata,
  }) = _PlayerInfo;

  /// Creates player information from JSON.
  factory PlayerInfo.fromJson(Map<String, Object?> json) => _$PlayerInfoFromJson(json);

  const PlayerInfo._();

  /// Empty player information.
  static const PlayerInfo empty = PlayerInfo();

  /// Whether a title is available.
  bool get hasTitle => _hasText(title);

  /// Whether a description is available.
  bool get hasDescription => _hasText(description);

  /// Whether an author is available.
  bool get hasAuthor => _hasText(author);

  /// Whether artwork is available.
  bool get hasArtwork => _hasText(artworkUrl);

  /// Whether a thumbnail is available.
  bool get hasThumbnail => _hasText(thumbnailUrl);

  /// Whether duration information is available.
  bool get hasDuration => durationMs != null && durationMs! >= 0;

  /// Whether video dimensions are available.
  bool get hasVideoSize {
    return width != null && height != null && width! > 0 && height! > 0;
  }

  /// Whether video frame-rate information is available.
  bool get hasFrameRate {
    return frameRate != null && frameRate! > 0;
  }

  /// Whether bitrate information is available.
  bool get hasBitrate {
    return videoBitrate != null || audioBitrate != null;
  }

  /// Whether video codec information is available.
  bool get hasVideoCodec => _hasText(videoCodec);

  /// Whether audio codec information is available.
  bool get hasAudioCodec => _hasText(audioCodec);

  /// Whether subtitle codec information is available.
  bool get hasSubtitleCodec => _hasText(subtitleCodec);

  /// Whether any metadata is available.
  bool get hasMetadata => metadata.isNotEmpty;

  /// Returns the media duration as a [Duration].
  Duration? get duration {
    final value = durationMs;
    if (value == null || value < 0) {
      return null;
    }

    return Duration(milliseconds: value);
  }

  /// Returns the video aspect ratio.
  double? get aspectRatio {
    final videoWidth = width;
    final videoHeight = height;

    if (videoWidth == null || videoHeight == null || videoWidth <= 0 || videoHeight <= 0) {
      return null;
    }

    return videoWidth / videoHeight;
  }

  /// Whether the video is portrait-oriented.
  bool get isPortrait {
    final ratio = aspectRatio;
    return ratio != null && ratio < 1;
  }

  /// Whether the video is landscape-oriented.
  bool get isLandscape {
    final ratio = aspectRatio;
    return ratio != null && ratio > 1;
  }

  /// Whether the video is square.
  bool get isSquare {
    final ratio = aspectRatio;
    return ratio != null && ratio == 1;
  }

  /// Returns the effective display name.
  ///
  /// The title has priority, followed by author and album.
  String? get displayName {
    final candidates = <String?>[title, author, album];

    for (final candidate in candidates) {
      if (_hasText(candidate)) {
        return candidate!.trim();
      }
    }

    return null;
  }

  /// Returns a metadata value.
  String? metadataValue(String key) {
    return metadata[key];
  }

  /// Whether the metadata contains [key].
  bool hasMetadataKey(String key) {
    return metadata.containsKey(key);
  }

  /// Returns a copy with [key] added or replaced in metadata.
  PlayerInfo withMetadata(String key, String value) {
    return copyWith(metadata: <String, String>{...metadata, key: value});
  }

  /// Returns a copy without [key] from metadata.
  PlayerInfo withoutMetadata(String key) {
    if (!metadata.containsKey(key)) {
      return this;
    }

    final nextMetadata = <String, String>{...metadata}..remove(key);

    return copyWith(metadata: nextMetadata);
  }

  /// Returns a copy without all metadata.
  PlayerInfo clearMetadata() {
    return copyWith(metadata: <String, String>{});
  }

  /// Returns whether this info contains useful descriptive data.
  bool get isEmpty {
    return !hasTitle &&
        !hasDescription &&
        !hasAuthor &&
        !hasArtwork &&
        !hasThumbnail &&
        !hasDuration &&
        !hasVideoSize &&
        !hasFrameRate &&
        !hasBitrate &&
        !hasVideoCodec &&
        !hasAudioCodec &&
        !hasSubtitleCodec &&
        !hasMetadata;
  }

  /// Returns whether this info contains at least one field.
  bool get isNotEmpty => !isEmpty;

  static bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}
