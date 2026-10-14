import 'dart:typed_data';

import 'package:media_core/adapter/engine_option.dart';
import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/adapter/player_adapter_context.dart';
import 'package:media_core/adapter/player_adapter_event.dart';
import 'package:media_core/adapter/player_adapter_metrics.dart';
import 'package:media_core/core/player_core_state.dart';
import 'package:media_core/screenshot/screenshot_request.dart';
import 'package:media_core/source/player_source.dart';

/// Abstract media player backend adapter.
///
/// [PlayerAdapter] is the common interface between
/// media_core and concrete playback engines.
///
/// Implementations may use:
///
/// - media_kit
/// - native player
/// - ffmpeg based backend
/// - platform player
///
/// Responsibilities:
///
/// - control playback backend
/// - expose backend events
/// - provide backend state
///
/// It does not:
///
/// - select backend
/// - create backend instance
/// - handle fallback
///
/// Those belong to:
///
/// - PlayerAdapterFactory
/// - BackendSelector
/// - FallbackManager
abstract interface class PlayerAdapter {
  /// Adapter identifier.
  String get id;

  /// Adapter capabilities.
  PlayerAdapterCapabilities get capabilities;

  /// Current adapter state.
  PlayerCoreState get state;

  /// Current playback position.
  Duration get position;

  /// Current media duration.
  ///
  /// Returns null when the duration is unknown or not available.
  Duration? get duration;

  /// Current metrics.
  PlayerAdapterMetrics get metrics;

  /// Adapter events.
  Stream<PlayerAdapterEvent> get events;

  /// Whether adapter is initialized.
  bool get initialized;

  /// Initializes adapter.
  Future<void> initialize(PlayerAdapterContext context);

  /// Opens a media source.
  Future<void> open(PlayerSource source);

  /// Starts playback.
  Future<void> play();

  /// Pauses playback.
  Future<void> pause();

  /// Stops playback.
  Future<void> stop();

  /// Seeks to position.
  Future<void> seek(Duration position);

  /// Sets volume.
  Future<void> setVolume(double volume);

  /// Sets playback speed.
  Future<void> setRate(double rate);

  /// Restricts playback to the audio track.
  ///
  /// Only meaningful when
  /// [PlayerAdapterCapabilities.supportsAudioOnly] is declared; an
  /// adapter without that capability may ignore the command.
  ///
  /// Implementations that own a video track must keep the setting
  /// across later [open] calls, because recovery replays a source
  /// without going back through the application.
  Future<void> setAudioOnly({required bool audioOnly});

  /// Applies raw engine options, spelled in the engine's own vocabulary.
  ///
  /// See [EngineOption]: the adapter transports the caller's values to the
  /// live engine where the engine supports it, and reports per option what
  /// happened. Options received before the engine exists are consumed at
  /// engine creation.
  Future<List<EngineOptionOutcome>> applyEngineOptions(List<EngineOption> options);

  /// Captures the current video frame with the backend's own API.
  ///
  /// Returns the encoded image bytes, or null when this backend cannot
  /// capture — see [PlayerAdapterCapabilities.supportsScreenshot] — or cannot
  /// encode [request]'s format.
  ///
  /// An implementation must not silently substitute another format: the caller
  /// treats null as "this route produced nothing" and falls back to capturing
  /// the rendered surface, which *does* produce a different format and says so
  /// on the result. Returning PNG bytes for a JPEG request would be
  /// indistinguishable from a backend that lied about the format.
  ///
  /// The engine's own capture is preferred where it exists: it returns the
  /// decoded frame at its real resolution, without the widget layer's fit,
  /// scaling or absence from the tree.
  Future<Uint8List?> captureFrame(ScreenshotRequest request);

  /// Closes current source.
  Future<void> close();

  /// Releases adapter resources.
  Future<void> dispose();
}
