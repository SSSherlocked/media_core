import 'package:equatable/equatable.dart';
import 'package:media_core/recording/recording_format.dart';

/// Defines configuration for a recording session.
///
/// A [RecordingConfig] describes how a recording should be produced without
/// binding the configuration to a concrete recording backend.
///
/// Responsibilities:
///
/// - define the requested recording format
/// - define the output location
/// - configure recording duration limits
/// - configure whether audio and video are recorded
/// - provide immutable recording options
///
/// It does not:
///
/// - create output files
/// - encode media
/// - select a recording backend
/// - start or stop recording
///
/// Those responsibilities belong to:
///
/// - RecordingBackend
/// - RecordingSession
/// - RecordingManager
final class RecordingConfig extends Equatable {
  /// Creates recording configuration.
  const RecordingConfig({
    this.format = const RecordingFormat.mp4(),
    this.outputPath,
    this.recordVideo = true,
    this.recordAudio = true,
    this.maxDuration,
  }) : assert(
         maxDuration == null || maxDuration > Duration.zero,
         'maxDuration must be null or longer than Duration.zero.',
       );

  /// Requested output format.
  final RecordingFormat format;

  /// Optional output path.
  ///
  /// When `null`, the concrete backend may choose or request an output
  /// location according to its platform-specific behavior.
  final String? outputPath;

  /// Whether video should be included in the recording.
  final bool recordVideo;

  /// Whether audio should be included in the recording.
  final bool recordAudio;

  /// Optional maximum recording duration.
  ///
  /// A `null` value means that no duration limit is imposed by this
  /// configuration.
  final Duration? maxDuration;

  /// Whether the recording has an explicit output path.
  bool get hasOutputPath {
    return outputPath != null && outputPath!.isNotEmpty;
  }

  /// Whether the recording is configured to contain video.
  bool get hasVideo {
    return recordVideo && format.hasVideo;
  }

  /// Whether the recording is configured to contain audio.
  bool get hasAudio {
    return recordAudio && format.hasAudio;
  }

  /// Whether the recording has a maximum duration.
  bool get hasDurationLimit {
    return maxDuration != null;
  }

  /// Creates a copy with selected configuration values replaced.
  RecordingConfig copyWith({
    RecordingFormat? format,
    String? outputPath,
    bool? recordVideo,
    bool? recordAudio,
    Duration? maxDuration,
  }) {
    return RecordingConfig(
      format: format ?? this.format,
      outputPath: outputPath ?? this.outputPath,
      recordVideo: recordVideo ?? this.recordVideo,
      recordAudio: recordAudio ?? this.recordAudio,
      maxDuration: maxDuration ?? this.maxDuration,
    );
  }

  @override
  List<Object?> get props => [format, outputPath, recordVideo, recordAudio, maxDuration];

  @override
  String toString() {
    return 'RecordingConfig('
        'format: $format, '
        'outputPath: $outputPath, '
        'recordVideo: $recordVideo, '
        'recordAudio: $recordAudio, '
        'maxDuration: $maxDuration'
        ')';
  }
}
