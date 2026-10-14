import 'package:equatable/equatable.dart';
import 'package:media_core/recording/recording_backend.dart' show RecordingBackend;

/// Defines the container and encoding format used for a recording.
///
/// A [RecordingFormat] describes the intended output format at the media-core
/// abstraction level. It does not bind the recording to a specific platform
/// encoder or backend implementation.
///
/// Responsibilities:
///
/// - identify the recording container format
/// - identify the common recording format options
/// - provide stable format names
/// - provide basic format characteristics
///
/// It does not:
///
/// - encode audio or video
/// - create output files
/// - select platform codecs
/// - validate backend-specific encoder availability
///
/// Those responsibilities belong to:
///
/// - RecordingBackend
/// - platform-specific recording implementations
final class RecordingFormat extends Equatable {
  /// Creates a recording format.
  const RecordingFormat({required this.container, this.videoCodec, this.audioCodec});

  /// Creates an MP4 recording format.
  const RecordingFormat.mp4({this.videoCodec = RecordingVideoCodec.h264, this.audioCodec = RecordingAudioCodec.aac})
    : container = RecordingContainer.mp4;

  /// Creates a WebM recording format.
  const RecordingFormat.webm({this.videoCodec = RecordingVideoCodec.vp9, this.audioCodec = RecordingAudioCodec.opus})
    : container = RecordingContainer.webm;

  /// Creates an MPEG-TS recording format.
  const RecordingFormat.mpegTs({this.videoCodec = RecordingVideoCodec.h264, this.audioCodec = RecordingAudioCodec.aac})
    : container = RecordingContainer.mpegTs;

  /// Output container format.
  final RecordingContainer container;

  /// Requested video codec.
  final RecordingVideoCodec? videoCodec;

  /// Requested audio codec.
  final RecordingAudioCodec? audioCodec;

  /// Stable format name.
  String get name {
    return container.name;
  }

  /// Whether this format contains a video codec.
  bool get hasVideo {
    return videoCodec != null;
  }

  /// Whether this format contains an audio codec.
  bool get hasAudio {
    return audioCodec != null;
  }

  @override
  List<Object?> get props => [container, videoCodec, audioCodec];

  @override
  String toString() {
    return 'RecordingFormat('
        'container: $container, '
        'videoCodec: $videoCodec, '
        'audioCodec: $audioCodec'
        ')';
  }
}

/// Defines the supported recording container formats.
///
/// A container describes how encoded audio and video streams are packaged
/// together in the output.
enum RecordingContainer {
  /// MPEG-4 container.
  mp4,

  /// WebM container.
  webm,

  /// MPEG transport stream container.
  mpegTs,
}

/// Provides common operations for [RecordingContainer].
extension RecordingContainerX on RecordingContainer {
  /// Stable string representation of this container.
  String get name {
    return switch (this) {
      RecordingContainer.mp4 => 'mp4',
      RecordingContainer.webm => 'webm',
      RecordingContainer.mpegTs => 'mpeg-ts',
    };
  }

  /// Common file extension associated with this container.
  String get extension {
    return switch (this) {
      RecordingContainer.mp4 => 'mp4',
      RecordingContainer.webm => 'webm',
      RecordingContainer.mpegTs => 'ts',
    };
  }

  /// MIME type commonly associated with this container.
  String get mimeType {
    return switch (this) {
      RecordingContainer.mp4 => 'video/mp4',
      RecordingContainer.webm => 'video/webm',
      RecordingContainer.mpegTs => 'video/mp2t',
    };
  }
}

/// Defines commonly supported video codecs for recording.
///
/// These values express a backend-independent preference. A concrete
/// [RecordingBackend] is responsible for determining whether a codec is
/// actually available on the current platform.
enum RecordingVideoCodec {
  /// H.264 / AVC video encoding.
  h264,

  /// H.265 / HEVC video encoding.
  h265,

  /// VP8 video encoding.
  vp8,

  /// VP9 video encoding.
  vp9,

  /// AV1 video encoding.
  av1,
}

/// Provides common operations for [RecordingVideoCodec].
extension RecordingVideoCodecX on RecordingVideoCodec {
  /// Stable string representation of this codec.
  String get name {
    return switch (this) {
      RecordingVideoCodec.h264 => 'h264',
      RecordingVideoCodec.h265 => 'h265',
      RecordingVideoCodec.vp8 => 'vp8',
      RecordingVideoCodec.vp9 => 'vp9',
      RecordingVideoCodec.av1 => 'av1',
    };
  }
}

/// Defines commonly supported audio codecs for recording.
///
/// These values express a backend-independent preference. A concrete
/// [RecordingBackend] is responsible for determining whether a codec is
/// actually available on the current platform.
enum RecordingAudioCodec {
  /// AAC audio encoding.
  aac,

  /// Opus audio encoding.
  opus,

  /// MP3 audio encoding.
  mp3,

  /// Vorbis audio encoding.
  vorbis,
}

/// Provides common operations for [RecordingAudioCodec].
extension RecordingAudioCodecX on RecordingAudioCodec {
  /// Stable string representation of this codec.
  String get name {
    return switch (this) {
      RecordingAudioCodec.aac => 'aac',
      RecordingAudioCodec.opus => 'opus',
      RecordingAudioCodec.mp3 => 'mp3',
      RecordingAudioCodec.vorbis => 'vorbis',
    };
  }
}
