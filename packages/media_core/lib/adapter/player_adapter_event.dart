import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/playback/buffer_range.dart';
import 'package:media_core/playback/playback_buffer.dart' show PlaybackBuffer;

part 'player_adapter_event.freezed.dart';

/// Events emitted by a player adapter.
///
/// [PlayerAdapterEvent] represents changes and
/// notifications from a playback backend.
///
/// Responsibilities:
///
/// - describe adapter events
/// - transport backend notifications
///
/// It does not:
///
/// - store current state
/// - dispatch events
/// - manage lifecycle
///
/// Those belong to:
///
/// - PlayerAdapterState
/// - EventDispatcher
/// - PlayerSession
@freezed
abstract class PlayerAdapterEvent with _$PlayerAdapterEvent {
  /// Creates adapter event.
  const factory PlayerAdapterEvent.opened({
    /// Opened source identifier.
    String? source,
  }) = PlayerAdapterOpened;

  /// Playback started.
  const factory PlayerAdapterEvent.playing() = PlayerAdapterPlaying;

  /// Playback paused.
  const factory PlayerAdapterEvent.paused() = PlayerAdapterPaused;

  /// Playback stopped.
  const factory PlayerAdapterEvent.stopped() = PlayerAdapterStopped;

  /// Buffering state changed.
  const factory PlayerAdapterEvent.buffering({
    /// Whether buffering is active.
    required bool buffering,

    /// Optional buffering percentage.
    double? progress,
  }) = PlayerAdapterBuffering;

  /// Playback completed.
  const factory PlayerAdapterEvent.completed() = PlayerAdapterCompleted;

  /// Position changed.
  const factory PlayerAdapterEvent.positionChanged({required Duration position}) = PlayerAdapterPositionChanged;

  /// Duration changed.
  const factory PlayerAdapterEvent.durationChanged({required Duration duration}) = PlayerAdapterDurationChanged;

  /// Video size changed.
  const factory PlayerAdapterEvent.videoSizeChanged({required int width, required int height}) =
      PlayerAdapterVideoSizeChanged;

  /// Decoded video frame progressed.
  ///
  /// This event is a heartbeat indicating that the backend has
  /// decoded another video frame. It is separate from
  /// [PlayerAdapterEvent.videoSizeChanged], which only describes video
  /// geometry.
  const factory PlayerAdapterEvent.videoFrameProgress() = PlayerAdapterVideoFrameProgress;

  /// Video output configuration changed.
  ///
  /// This event indicates that the backend reconfigured its
  /// video output, such as resolution, pixel format, rotation,
  /// or video filter chain.
  const factory PlayerAdapterEvent.videoReconfigured() = PlayerAdapterVideoReconfigured;

  /// Hardware decoder changed.
  ///
  /// [decoder] identifies the currently active decoder when
  /// available, such as a hardware decoder name.
  const factory PlayerAdapterEvent.hwdecChanged({String? decoder}) = PlayerAdapterHwdecChanged;

  /// Audio output configuration changed.
  ///
  /// This event indicates that the backend reconfigured its
  /// audio output.
  const factory PlayerAdapterEvent.audioReconfigured() = PlayerAdapterAudioReconfigured;

  /// Audio output device changed.
  ///
  /// [device] identifies the currently selected audio output
  /// device when available.
  const factory PlayerAdapterEvent.audioDeviceChanged({String? device}) = PlayerAdapterAudioDeviceChanged;

  /// Subtitle track content changed.
  ///
  /// [text] contains the currently displayed subtitle text
  /// when available.
  const factory PlayerAdapterEvent.subtitleChanged({String? text}) = PlayerAdapterSubtitleChanged;

  /// Cache state changed.
  ///
  /// This event describes runtime cache or buffering information
  /// reported by the backend.
  const factory PlayerAdapterEvent.cacheChanged({
    /// Whether the backend is currently buffering.
    bool? buffering,

    /// Cached duration when available.
    Duration? duration,

    /// Cached or buffered progress when available.
    double? progress,
  }) = PlayerAdapterCacheChanged;

  /// Buffered byte ranges changed.
  ///
  /// This event reports the stretches of media the backend can play
  /// without waiting, in the same media clock as
  /// [PlayerAdapterEvent.positionChanged].
  ///
  /// It is distinct from [PlayerAdapterEvent.cacheChanged], which reports a
  /// single scalar progress figure: a progress bar needs the actual
  /// stretches to paint the ahead-fill and to answer whether a
  /// scrub target is already downloaded, and a scalar cannot express
  /// the discontiguous buffers a seek-ahead or a live edge produces.
  /// The two coexist because engines report one, the other, or both.
  const factory PlayerAdapterEvent.bufferedRangesChanged({
    /// Buffered stretches as the backend reported them; the consumer
    /// canonicalizes through [PlaybackBuffer.normalize].
    required List<BufferRange> ranges,
  }) = PlayerAdapterBufferedRangesChanged;

  /// Playback metadata changed.
  ///
  /// [metadata] contains metadata reported by the backend.
  const factory PlayerAdapterEvent.metadataChanged({required Map<String, dynamic> metadata}) =
      PlayerAdapterMetadataChanged;

  /// Playlist changed.
  ///
  /// [items] contains the current playlist items.
  ///
  /// [index] contains the currently selected item when available.
  const factory PlayerAdapterEvent.playlistChanged({required List<String> items, int? index}) =
      PlayerAdapterPlaylistChanged;

  /// Backend client message received.
  ///
  /// [message] contains the backend message.
  ///
  /// [args] contains optional message arguments.
  const factory PlayerAdapterEvent.clientMessage({
    /// Backend message.
    required String message,

    /// Optional message arguments.
    @Default(<String>[]) List<String> args,
  }) = PlayerAdapterClientMessage;

  /// Backend log message received.
  ///
  /// [level] contains the log level.
  ///
  /// [prefix] contains the backend log prefix.
  ///
  /// [text] contains the log message.
  const factory PlayerAdapterEvent.logMessage({required String level, required String prefix, required String text}) =
      PlayerAdapterLogMessage;

  /// Volume changed.
  const factory PlayerAdapterEvent.volumeChanged({required double volume}) = PlayerAdapterVolumeChanged;

  /// Playback rate changed.
  const factory PlayerAdapterEvent.rateChanged({required double rate}) = PlayerAdapterRateChanged;

  /// Adapter error occurred.
  const factory PlayerAdapterEvent.error({required String message, Object? error, StackTrace? stackTrace}) =
      PlayerAdapterErrorEvent;
}

/// Extensions for adapter events.
extension PlayerAdapterEventExtension on PlayerAdapterEvent {
  /// Whether this event represents an error.
  bool get isError {
    return this is PlayerAdapterErrorEvent;
  }

  /// Whether event affects playback state.
  bool get affectsPlayback {
    return switch (this) {
      PlayerAdapterPlaying() || PlayerAdapterPaused() || PlayerAdapterStopped() || PlayerAdapterCompleted() => true,
      _ => false,
    };
  }

  /// Whether event affects media geometry.
  bool get affectsGeometry {
    return this is PlayerAdapterVideoSizeChanged || this is PlayerAdapterVideoReconfigured;
  }

  /// Whether this event represents a decoded video frame heartbeat.
  bool get isVideoHeartbeat {
    return this is PlayerAdapterVideoFrameProgress;
  }

  /// Whether event affects buffering state.
  bool get affectsBuffering {
    return this is PlayerAdapterBuffering || this is PlayerAdapterCacheChanged;
  }

  /// Whether event affects audio output.
  bool get affectsAudioOutput {
    return this is PlayerAdapterAudioReconfigured ||
        this is PlayerAdapterAudioDeviceChanged ||
        this is PlayerAdapterVolumeChanged;
  }

  /// Whether this event is a backend diagnostic event.
  bool get isDiagnostic {
    return this is PlayerAdapterClientMessage || this is PlayerAdapterLogMessage;
  }
}
