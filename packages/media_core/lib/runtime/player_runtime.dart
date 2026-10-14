import 'dart:async';

import 'package:media_core/adapter/player_adapter.dart';
import 'package:media_core/geometry/geometry_controller.dart';
import 'package:media_core/playback/playback_command.dart';
import 'package:media_core/playback/playback_controller.dart';
import 'package:media_core/playback/player_transport_state.dart';
import 'package:media_core/runtime/player_geometry_binding.dart';
import 'package:media_core/runtime/player_playback_binding.dart';
import 'package:media_core/screenshot/screenshot_config.dart';
import 'package:media_core/screenshot/screenshot_manager.dart';
import 'package:media_core/session/player_session.dart';
import 'package:media_core/session/session_controller.dart';
import 'package:media_core_logging/media_core_logging.dart';

/// Runtime container for one logical player.
///
/// Owns the backend adapter and the per-player state modules that
/// directly describe the current playback runtime.
///
/// Responsibilities:
///
/// - own the active [PlayerAdapter]
/// - own the [PlayerSession] and its [SessionController]
/// - own the [PlaybackController] and [GeometryController]
/// - bridge adapter events into playback and geometry state
/// - swap the adapter when the handle performs a backend fallback
///
/// It does not:
///
/// - select adapters
/// - perform backend fallback
/// - perform recovery
/// - serialize public player operations
/// - publish kernel-level events
///
/// Those belong to `PlayerHandle`.
final class PlayerRuntime {
  /// Creates a runtime around an already-constructed [adapter] and
  /// [session].
  ///
  /// The bindings are attached immediately and stay alive for the
  /// runtime's whole lifetime — except across [replaceAdapter], which
  /// rebinds them to the new backend.
  PlayerRuntime({
    required PlayerAdapter adapter,
    required PlayerSession session,
    ScreenshotConfig screenshotConfig = const ScreenshotConfig(),
  }) : _adapter = adapter,
       _session = session,
       _sessionController = SessionController(session),
       _playback = PlaybackController(),
       _geometry = GeometryController() {
    _geometryBinding = PlayerGeometryBinding(adapter: adapter, geometry: _geometry);

    _playbackBinding = PlayerPlaybackBinding(adapter: adapter, playback: _playback);

    // Screenshots are assembled here because this is the only place where the
    // adapter, the geometry and the playback mirror are all in scope. The
    // closures read them at capture time, so a backend swap during recovery is
    // transparent to whoever presses "save frame".
    _screenshots = ScreenshotManager(
      config: screenshotConfig,
      context: ScreenshotContext(
        playerId: session.context.playerId,
        captureFromEngine: (request) => _adapter.captureFrame(request),
        engineCaptureAvailable: () => _adapter.capabilities.supportsScreenshot,
        frameWidth: () => _geometry.current.geometry.videoSize.width,
        frameHeight: () => _geometry.current.geometry.videoSize.height,
        position: () => _playback.current.position,
      ),
    );

    // The session publishes position/duration/buffering in its snapshots but
    // does not own them; the playback mirror is the owner, and this is the one
    // place both are in scope.
    _sessionSubscription = _playback.state.listen((state) {
      _sessionController.updateTimeline(position: state.position, duration: state.duration, buffering: state.buffering);
    }, onError: (Object _) {});
  }

  StreamSubscription<PlayerTransportState>? _sessionSubscription;

  /// Mutable: [replaceAdapter] swaps it during backend fallback.
  PlayerAdapter _adapter;

  final PlayerSession _session;
  final SessionController _sessionController;

  final PlaybackController _playback;
  final GeometryController _geometry;

  // Mutable: replaceAdapter disposes the old pair and rebuilds them
  // against the new adapter.
  late PlayerGeometryBinding _geometryBinding;
  late PlayerPlaybackBinding _playbackBinding;

  /// Frame capture for this player.
  ///
  /// Owned here, not by the handle: it needs the adapter, the geometry and the
  /// playback mirror, and it must survive a backend swap unchanged.
  late final ScreenshotManager _screenshots;

  bool _disposed = false;

  /// The backend adapter.
  PlayerAdapter get adapter => _adapter;

  /// The player session.
  PlayerSession get session => _session;

  /// The session controller.
  SessionController get sessionController => _sessionController;

  /// Playback state controller.
  PlaybackController get playback => _playback;

  /// Geometry state controller.
  GeometryController get geometry => _geometry;

  /// Frame capture for this player.
  ScreenshotManager get screenshots => _screenshots;

  /// Whether this runtime has been disposed.
  bool get disposed => _disposed;

  /// Swaps the backend adapter.
  ///
  /// Called by `PlayerHandle.attachAdapter` *after* the new adapter
  /// has been initialized and, when a source is present, opened. This
  /// method only handles the switch: it detaches both bindings from the
  /// old adapter, replaces the reference, and rebuilds both bindings
  /// against the new adapter.
  ///
  /// It does not initialize, open, seek, or play the new adapter —
  /// those are the caller's responsibility, because they involve
  /// lifecycle state the runtime does not own.
  ///
  /// The old adapter is *not* disposed here. The caller disposes it,
  /// because it may still be observing the runtime's own events until
  /// the swap settles.
  Future<void> replaceAdapter(PlayerAdapter nextAdapter) async {
    if (_disposed) {
      throw StateError('PlayerRuntime has been disposed.');
    }

    if (identical(_adapter, nextAdapter)) {
      return;
    }

    MediaCoreLog.info(LogCategory.fallback, 'runtime adapter swap: ${_adapter.id} -> ${nextAdapter.id}');

    // Detach old bindings first so no further events from the old
    // adapter reach the controllers.
    await _geometryBinding.dispose();
    await _playbackBinding.dispose();

    // The previous engine's geometry must not survive the swap: a
    // video-size event is emitted once per open, so keeping the old size would
    // letterbox the new engine's picture until it happens to report its own.
    _geometry.clear();

    _playback.apply(const PlaybackCommand.stop());

    _adapter = nextAdapter;

    // Rebuild bindings against the new adapter. The controllers
    // themselves are preserved — they describe *this* player, not the
    // backend behind it.
    _geometryBinding = PlayerGeometryBinding(adapter: nextAdapter, geometry: _geometry);

    _playbackBinding = PlayerPlaybackBinding(adapter: nextAdapter, playback: _playback);
  }

  /// Releases all runtime-owned resources.
  ///
  /// Bindings are detached first so no further adapter events can
  /// reach the controllers, then the controllers are disposed, then
  /// the session controller, then the adapter itself.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _geometryBinding.dispose();
    await _playbackBinding.dispose();

    await _sessionSubscription?.cancel();
    _sessionSubscription = null;

    // Before the adapter goes: a capture in flight must not touch a disposed
    // engine, and the surfaces belong to widgets that may outlive this call.
    await _screenshots.dispose();

    await _playback.dispose();
    await _geometry.dispose();

    await _sessionController.dispose();
    await _adapter.dispose();
  }
}
