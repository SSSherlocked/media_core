import 'package:equatable/equatable.dart';

/// Describes the media type currently represented by a player.
///
/// [PlayerMediaType] is a small immutable value object used by the core player
/// model. It describes the capabilities of the current media itself,
/// rather than the transport protocol or source declaration.
///
/// Source-level media information belongs to `SourceMediaType`.
final class PlayerMediaType extends Equatable implements Comparable<PlayerMediaType> {
  /// Creates a media type from a raw value.
  ///
  /// Empty values are not allowed.
  factory PlayerMediaType(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Media type must not be empty.');
    }

    return PlayerMediaType._(normalized);
  }

  const PlayerMediaType._(this.value);

  /// Creates a custom media type.
  factory PlayerMediaType.custom(String value) {
    return PlayerMediaType(value);
  }

  /// Creates a media type from a JSON value.
  factory PlayerMediaType.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('PlayerMediaType JSON value must be a String.');
    }

    return PlayerMediaType(json);
  }

  /// Creates a media type by parsing a raw string.
  factory PlayerMediaType.parse(String value) {
    return PlayerMediaType(value);
  }

  /// Attempts to parse a media type.
  ///
  /// Returns `null` when [value] is empty or invalid.
  static PlayerMediaType? tryParse(String? value) {
    if (value == null || !isValid(value)) {
      return null;
    }

    return PlayerMediaType(value);
  }

  /// Represents an unknown media type.
  static const PlayerMediaType unknown = PlayerMediaType._('unknown');

  /// Represents audio-only media.
  static const PlayerMediaType audio = PlayerMediaType._('audio');

  /// Represents video-only media.
  static const PlayerMediaType video = PlayerMediaType._('video');

  /// Represents media containing both audio and video.
  static const PlayerMediaType audioVideo = PlayerMediaType._('audio_video');

  /// Returns the raw media type value.
  final String value;

  /// Returns the raw string representation.
  String get rawValue => value;

  /// Returns the serialized value.
  String get toValue => value;

  /// Returns the JSON representation.
  String toJson() => value;

  /// Returns whether this is a built-in media type.
  bool get isBuiltIn {
    return this == unknown || this == audio || this == video || this == audioVideo;
  }

  /// Returns whether this is a custom media type.
  bool get isCustom => !isBuiltIn;

  /// Returns whether this represents an unknown media type.
  bool get isUnknown => value == unknown.value;

  /// Returns whether this represents audio-only media.
  bool get isAudio => value == audio.value;

  /// Returns whether this represents video media.
  bool get isVideo => value == video.value;

  /// Returns whether this contains both audio and video.
  bool get isAudioVideo => value == audioVideo.value;

  /// Returns whether the media contains an audio component.
  bool get hasAudio {
    return isAudio || isAudioVideo;
  }

  /// Returns whether the media contains a video component.
  bool get hasVideo {
    return isVideo || isAudioVideo;
  }

  /// Returns whether the media can be played through an audio output.
  bool get supportsAudioPlayback => hasAudio;

  /// Returns whether the media requires video playback support.
  bool get supportsVideoPlayback => hasVideo;

  /// Returns whether the media requires a video renderer.
  bool get requiresVideoRenderer => hasVideo;

  /// Returns whether the media is audio-only.
  bool get isAudioOnly => isAudio;

  /// Returns whether the media is video-only.
  bool get isVideoOnly => isVideo;

  /// Returns whether the media combines audio and video.
  bool get isCombined => isAudioVideo;

  /// Returns whether the media type is known and playable.
  bool get isPlayable {
    return isAudio || isVideo || isAudioVideo;
  }

  /// Returns whether the media type is one of the known built-in types.
  bool get isKnown => isBuiltIn && !isUnknown;

  /// Returns whether the value is a valid media type.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Returns all built-in media types.
  static const List<PlayerMediaType> builtIns = <PlayerMediaType>[unknown, audio, video, audioVideo];

  /// Returns all playable built-in media types.
  static const List<PlayerMediaType> builtIn = <PlayerMediaType>[audio, video, audioVideo];

  /// Returns whether [value] is a built-in media type.
  static bool isBuiltInValue(String value) {
    final normalized = value.trim();

    return builtIns.any((type) => type.value == normalized);
  }

  /// Returns the corresponding built-in type for [value].
  ///
  /// Unknown values are represented by [unknown].
  static PlayerMediaType builtInFor(String value) {
    final normalized = value.trim();

    for (final type in builtIns) {
      if (type.value == normalized) {
        return type;
      }
    }

    return unknown;
  }

  /// Creates a copy with a different raw value.
  PlayerMediaType copyWith({String? value}) {
    return PlayerMediaType(value ?? this.value);
  }

  /// Returns whether this type is equal to [other].
  bool isSameAs(PlayerMediaType other) {
    return this == other;
  }

  /// Returns whether this type differs from [other].
  bool isDifferentFrom(PlayerMediaType other) {
    return this != other;
  }

  /// Returns whether this type has the same audio/video capabilities
  /// as [other].
  bool hasSameCapabilitiesAs(PlayerMediaType other) {
    return hasAudio == other.hasAudio && hasVideo == other.hasVideo;
  }

  @override
  int compareTo(PlayerMediaType other) {
    return value.compareTo(other.value);
  }

  @override
  List<Object?> get props => <Object?>[value];

  @override
  String toString() {
    return value;
  }
}
