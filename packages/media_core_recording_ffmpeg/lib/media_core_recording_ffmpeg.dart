/// FFmpeg recording backend for media_core.
///
/// Captures a network stream to segmented MPEG-TS files plus a CSV journal, on
/// top of `ffmpeg_kit_extended_flutter`:
///
/// ```dart
/// final backend = FfmpegRecordingBackend(outputDirectory: recordingsDir);
/// await backend.initialize();
///
/// final manager = RecordingManager(backend: backend);
/// await manager.start(
///   source: RecordingSource.network(streamUrl, id: roomId),
///   config: const RecordingConfig(outputPath: recordingsDir),
/// );
/// // ... later
/// final result = await manager.stop();
/// ```
///
/// Segments rather than one file, intent rather than exit code, a result judged
/// by the files on disk, a dropped stream re-opened rather than reported, and a
/// room watched until it goes live rather than recorded on a guess are the five
/// decisions this package is built around; the first four are explained on
/// [FfmpegRecordingBackend], the last on [FfmpegLiveRecordingWatcher].
library;

import 'package:media_core_recording_ffmpeg/src/ffmpeg_recording_backend.dart' show FfmpegRecordingBackend;
import 'package:media_core_recording_ffmpeg/src/live_recording_watcher.dart' show FfmpegLiveRecordingWatcher;

export 'package:media_core_recording_ffmpeg/src/ffmpeg_executor.dart';
export 'package:media_core_recording_ffmpeg/src/ffmpeg_probe.dart';
export 'package:media_core_recording_ffmpeg/src/ffmpeg_record_arguments.dart';
export 'package:media_core_recording_ffmpeg/src/ffmpeg_record_config.dart';
export 'package:media_core_recording_ffmpeg/src/ffmpeg_record_container.dart';
export 'package:media_core_recording_ffmpeg/src/ffmpeg_recording_backend.dart';
export 'package:media_core_recording_ffmpeg/src/live_recording_watcher.dart';
export 'package:media_core_recording_ffmpeg/src/recording_manifest.dart';
export 'package:media_core_recording_ffmpeg/src/recording_recovery.dart';
export 'package:media_core_recording_ffmpeg/src/recording_remuxer.dart';
export 'package:media_core_recording_ffmpeg/src/recording_verification.dart';
