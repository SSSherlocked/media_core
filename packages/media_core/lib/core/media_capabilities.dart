import 'package:equatable/equatable.dart';

/// Describes the media capabilities available for the current media.
///
/// [MediaCapabilities] describes what kind of content a media item contains
/// and which media-level features are available. It is independent from
/// backend/player implementation capabilities.
///
/// For example, a player backend may support video playback while the
/// current media itself is audio-only. Media capabilities describe the
/// latter.
final class MediaCapabilities extends Equatable {
  /// Creates an immutable media capabilities model.
  const MediaCapabilities({
    this.hasAudio = false,
    this.hasVideo = false,
    this.hasSubtitles = false,
    this.hasMultipleAudioTracks = false,
    this.hasMultipleVideoTracks = false,
    this.hasMultipleSubtitleTracks = false,
    this.supportsSeeking = false,
    this.supportsDuration = false,
    this.supportsLive = false,
  });

  /// Whether the media contains an audio track.
  final bool hasAudio;

  /// Whether the media contains a video track.
  final bool hasVideo;

  /// Whether the media contains subtitle information.
  final bool hasSubtitles;

  /// Whether the media contains multiple selectable audio tracks.
  final bool hasMultipleAudioTracks;

  /// Whether the media contains multiple selectable video tracks.
  final bool hasMultipleVideoTracks;

  /// Whether the media contains multiple selectable subtitle tracks.
  final bool hasMultipleSubtitleTracks;

  /// Whether the media supports seeking.
  final bool supportsSeeking;

  /// Whether the media exposes a meaningful duration.
  final bool supportsDuration;

  /// Whether the media represents a live stream.
  final bool supportsLive;

  /// Returns whether the media is audio-only.
  bool get isAudioOnly {
    return hasAudio && !hasVideo;
  }

  /// Returns whether the media is video-only.
  bool get isVideoOnly {
    return hasVideo && !hasAudio;
  }

  /// Returns whether the media contains both audio and video.
  bool get isAudioVideo {
    return hasAudio && hasVideo;
  }

  /// Returns whether the media type is unknown.
  bool get isUnknown {
    return !hasAudio && !hasVideo;
  }

  /// Returns whether the media contains any playable media component.
  bool get hasAnyMedia {
    return hasAudio || hasVideo;
  }

  /// Returns whether the media can be played through an audio output.
  bool get supportsAudioPlayback {
    return hasAudio;
  }

  /// Returns whether the media can be played through a video output.
  bool get supportsVideoPlayback {
    return hasVideo;
  }

  /// Returns whether the media requires a video renderer.
  bool get requiresVideoRenderer {
    return hasVideo;
  }

  /// Returns whether multiple audio tracks can be selected.
  bool get supportsMultipleAudioTracks {
    return hasMultipleAudioTracks;
  }

  /// Returns whether multiple video tracks can be selected.
  bool get supportsMultipleVideoTracks {
    return hasMultipleVideoTracks;
  }

  /// Returns whether multiple subtitle tracks can be selected.
  bool get supportsMultipleSubtitleTracks {
    return hasMultipleSubtitleTracks;
  }

  /// Returns whether the media provides any selectable tracks.
  bool get hasTrackSelection {
    return hasMultipleAudioTracks || hasMultipleVideoTracks || hasMultipleSubtitleTracks;
  }

  /// Returns whether the media is seekable.
  bool get isSeekable {
    return supportsSeeking;
  }

  /// Returns whether the media is live.
  bool get isLive {
    return supportsLive;
  }

  /// Returns whether the media has a finite duration.
  ///
  /// A media item is considered to have a finite duration only when it
  /// exposes duration information and is not a live stream.
  bool get hasFiniteDuration {
    return supportsDuration && !supportsLive;
  }

  /// Creates a copy with selectively replaced values.
  ///
  /// Null values retain the existing values.
  MediaCapabilities copyWith({
    bool? hasAudio,
    bool? hasVideo,
    bool? hasSubtitles,
    bool? hasMultipleAudioTracks,
    bool? hasMultipleVideoTracks,
    bool? hasMultipleSubtitleTracks,
    bool? supportsSeeking,
    bool? supportsDuration,
    bool? supportsLive,
  }) {
    return MediaCapabilities(
      hasAudio: hasAudio ?? this.hasAudio,
      hasVideo: hasVideo ?? this.hasVideo,
      hasSubtitles: hasSubtitles ?? this.hasSubtitles,
      hasMultipleAudioTracks: hasMultipleAudioTracks ?? this.hasMultipleAudioTracks,
      hasMultipleVideoTracks: hasMultipleVideoTracks ?? this.hasMultipleVideoTracks,
      hasMultipleSubtitleTracks: hasMultipleSubtitleTracks ?? this.hasMultipleSubtitleTracks,
      supportsSeeking: supportsSeeking ?? this.supportsSeeking,
      supportsDuration: supportsDuration ?? this.supportsDuration,
      supportsLive: supportsLive ?? this.supportsLive,
    );
  }

  /// Returns capabilities for audio-only media.
  MediaCapabilities asAudioOnly() {
    return copyWith(hasAudio: true, hasVideo: false);
  }

  /// Returns capabilities for video-only media.
  MediaCapabilities asVideoOnly() {
    return copyWith(hasAudio: false, hasVideo: true);
  }

  /// Returns capabilities for media containing audio and video.
  MediaCapabilities asAudioVideo() {
    return copyWith(hasAudio: true, hasVideo: true);
  }

  /// Returns capabilities without audio.
  MediaCapabilities withoutAudio() {
    return copyWith(hasAudio: false, hasMultipleAudioTracks: false);
  }

  /// Returns capabilities without video.
  MediaCapabilities withoutVideo() {
    return copyWith(hasVideo: false, hasMultipleVideoTracks: false);
  }

  /// Returns capabilities without subtitles.
  MediaCapabilities withoutSubtitles() {
    return copyWith(hasSubtitles: false, hasMultipleSubtitleTracks: false);
  }

  /// Returns capabilities with seeking disabled.
  MediaCapabilities withoutSeeking() {
    return copyWith(supportsSeeking: false);
  }

  /// Returns capabilities with duration support disabled.
  MediaCapabilities withoutDuration() {
    return copyWith(supportsDuration: false);
  }

  /// Returns capabilities marked as live media.
  MediaCapabilities asLive() {
    return copyWith(supportsLive: true);
  }

  /// Returns capabilities marked as non-live media.
  MediaCapabilities asNonLive() {
    return copyWith(supportsLive: false);
  }

  /// Returns whether this capability set equals [other].
  bool isSameAs(MediaCapabilities other) {
    return this == other;
  }

  /// Returns whether this capability set differs from [other].
  bool isDifferentFrom(MediaCapabilities other) {
    return this != other;
  }

  /// Returns the default unknown media capabilities.
  static const MediaCapabilities unknown = MediaCapabilities();

  /// Returns capabilities for audio-only media.
  static const MediaCapabilities audioOnly = MediaCapabilities(hasAudio: true);

  /// Returns capabilities for video-only media.
  static const MediaCapabilities videoOnly = MediaCapabilities(hasVideo: true);

  /// Returns capabilities for audio-video media.
  static const MediaCapabilities audioVideo = MediaCapabilities(hasAudio: true, hasVideo: true);

  /// Returns capabilities for a typical live stream.
  static const MediaCapabilities live = MediaCapabilities(hasAudio: true, hasVideo: true, supportsLive: true);

  /// Returns capabilities for typical on-demand media.
  static const MediaCapabilities onDemand = MediaCapabilities(
    hasAudio: true,
    hasVideo: true,
    supportsSeeking: true,
    supportsDuration: true,
  );

  @override
  List<Object?> get props => <Object?>[
    hasAudio,
    hasVideo,
    hasSubtitles,
    hasMultipleAudioTracks,
    hasMultipleVideoTracks,
    hasMultipleSubtitleTracks,
    supportsSeeking,
    supportsDuration,
    supportsLive,
  ];

  @override
  String toString() {
    return 'MediaCapabilities('
        'hasAudio: $hasAudio, '
        'hasVideo: $hasVideo, '
        'hasSubtitles: $hasSubtitles, '
        'hasMultipleAudioTracks: $hasMultipleAudioTracks, '
        'hasMultipleVideoTracks: $hasMultipleVideoTracks, '
        'hasMultipleSubtitleTracks: $hasMultipleSubtitleTracks, '
        'supportsSeeking: $supportsSeeking, '
        'supportsDuration: $supportsDuration, '
        'supportsLive: $supportsLive'
        ')';
  }
}
