import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/screenshot/player_screenshot.dart';
import 'package:media_core/screenshot/screenshot_config.dart';
import 'package:media_core/screenshot/screenshot_format.dart';
import 'package:media_core/screenshot/screenshot_options.dart';
import 'package:media_core/screenshot/screenshot_request.dart';
import 'package:media_core/screenshot/screenshot_surface.dart';
import 'package:media_core/screenshot/screenshot_writer.dart' show ScreenshotWriter;
import 'package:media_core_logging/media_core_logging.dart';
import 'package:rxdart/rxdart.dart';

/// Per-player facts a capture needs but does not own.
///
/// The members are closures rather than values because everything they
/// describe changes underneath a screenshot: recovery swaps the adapter,
/// geometry arrives only after the first frame, and the position moves while
/// the user watches. The runtime hands these over once, and every capture
/// reads the current truth.
final class ScreenshotContext {
  /// Creates a capture context.
  const ScreenshotContext({
    required this.playerId,
    required this.captureFromEngine,
    required this.engineCaptureAvailable,
    required this.frameWidth,
    required this.frameHeight,
    required this.position,
  });

  /// PlayerIdentity the captures belong to.
  final PlayerId playerId;

  /// Asks the currently attached adapter for a frame.
  final Future<Uint8List?> Function(ScreenshotRequest request) captureFromEngine;

  /// Whether the currently attached adapter can capture a frame itself.
  final bool Function() engineCaptureAvailable;

  /// Frame width reported by the player, `0` when unknown.
  final int Function() frameWidth;

  /// Frame height reported by the player, `0` when unknown.
  final int Function() frameHeight;

  /// Current playback position.
  final Duration Function() position;
}

/// Captures video frames for one player.
///
/// Sits between the kernel handle and the two capture routes:
///
/// ```text
/// PlayerHandle.captureScreenshot
///        │
///        ▼
/// ScreenshotManager ──engine───▶ PlayerAdapter.captureFrame
///        │
///        └──surface──▶ ScreenshotSurface (the widget on screen)
/// ```
///
/// Responsibilities:
///
/// - choose the capture route
/// - bound a capture with a timeout
/// - attach the player's position and frame size to the result
/// - keep the most recent captures
/// - track which surfaces currently render this player
///
/// It does not:
///
/// - talk to engines (the adapter does)
/// - own widgets (it only borrows their surface)
/// - write files (see [ScreenshotWriter])
///
/// Those belong to:
///
/// - PlayerAdapter
/// - MediaPlayerView
/// - ScreenshotWriter
final class ScreenshotManager {
  /// Creates a manager for one player.
  ScreenshotManager({required ScreenshotContext context, this.config = const ScreenshotConfig()})
    : _context = context,
      _history = BehaviorSubject<List<PlayerScreenshot>>.seeded(const <PlayerScreenshot>[]);

  final ScreenshotContext _context;

  /// Screenshot behaviour.
  final ScreenshotConfig config;

  /// Captures kept in insertion order, newest first.
  final BehaviorSubject<List<PlayerScreenshot>> _history;

  /// One event per successful capture.
  final StreamController<PlayerScreenshot> _captures = StreamController<PlayerScreenshot>.broadcast();

  /// Surfaces currently rendering this player.
  ///
  /// Insertion-ordered so the newest surface — the one actually on screen
  /// after a host moved the video to another widget — is tried first.
  final LinkedHashSet<ScreenshotSurface> _surfaces = LinkedHashSet<ScreenshotSurface>();

  bool _disposed = false;

  /// Captures kept, newest first.
  ValueStream<List<PlayerScreenshot>> get history => _history.stream;

  /// The kept captures, newest first.
  List<PlayerScreenshot> get recent => List<PlayerScreenshot>.unmodifiable(_history.value);

  /// The most recent capture, if any.
  PlayerScreenshot? get latest {
    final entries = _history.value;

    return entries.isEmpty ? null : entries.first;
  }

  /// One event per successful capture.
  Stream<PlayerScreenshot> get captures => _captures.stream;

  /// Whether this manager has been disposed.
  bool get isDisposed => _disposed;

  /// Whether any widget currently offers a surface for this player.
  bool get hasSurface => _surfaces.isNotEmpty;

  /// Whether a capture has any route it can take.
  ///
  /// False means [capture] would return null: the engine cannot capture and no
  /// widget is rendering this player. A host uses this to disable the "save
  /// frame" action instead of offering one that does nothing.
  bool get canCapture => _context.engineCaptureAvailable() || (config.surfaceFallback && hasSurface);

  /// Registers a widget surface that can render this player.
  void attachSurface(ScreenshotSurface surface) {
    if (_disposed) {
      return;
    }

    _surfaces.add(surface);
  }

  /// Removes a widget surface.
  void detachSurface(ScreenshotSurface surface) {
    _surfaces.remove(surface);
  }

  /// Removes every surface.
  ///
  /// Used when the player is disposed while a widget is still tearing down.
  void detachAllSurfaces() {
    _surfaces.clear();
  }

  /// Captures the current video frame.
  ///
  /// Returns null when no route produced a frame — no video decoded yet, the
  /// engine cannot capture and no widget is rendering this player, or the
  /// attempt timed out. Nothing throws: a screenshot is a user-initiated
  /// convenience, and a failure is reported as "no image".
  Future<PlayerScreenshot?> capture({ScreenshotOptions options = ScreenshotOptions.defaults}) async {
    if (_disposed) {
      return null;
    }

    for (final source in _routesFor(options)) {
      final frame = await _captureVia(source, options);

      if (frame == null || frame.bytes.isEmpty) {
        continue;
      }

      // A surface capture can only encode PNG; an engine capture produced
      // exactly what was asked for. The result says which one happened so a
      // caller that needs a specific encoding can tell.
      final produced = source.isSurface ? ScreenshotFormat.png : options.format;

      final screenshot = PlayerScreenshot(
        bytes: frame.bytes,
        format: produced,
        width: frame.width,
        height: frame.height,
        position: _context.position(),
        capturedAt: clock.now(),
        source: source,
        playerId: _context.playerId,
        requestedFormat: produced == options.format ? null : options.format,
      );

      _remember(screenshot);

      MediaCoreLog.info(LogCategory.renderer, 'screenshot captured', fields: screenshot.toLogFields());

      return screenshot;
    }

    MediaCoreLog.warning(
      LogCategory.renderer,
      'screenshot unavailable',
      fields: <String, Object?>{
        'playerId': _context.playerId.value,
        'route': options.route.name,
        'engineCapture': _context.engineCaptureAvailable(),
        'surfaces': _surfaces.length,
      },
    );

    return null;
  }

  /// Forgets the kept captures, releasing their bytes.
  void clearHistory() {
    if (_disposed) {
      return;
    }

    _history.add(const <PlayerScreenshot>[]);
  }

  /// Releases everything this manager holds.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _surfaces.clear();
    clearHistory();

    await _captures.close();
    await _history.close();
  }

  /// Routes a capture may try, in order.
  Iterable<ScreenshotSource> _routesFor(ScreenshotOptions options) {
    switch (options.route) {
      case ScreenshotRoute.engine:
        return const <ScreenshotSource>[ScreenshotSource.engine];

      case ScreenshotRoute.surface:
        return const <ScreenshotSource>[ScreenshotSource.surface];

      case ScreenshotRoute.auto:
        final engineFirst = _context.engineCaptureAvailable();

        if (!config.surfaceFallback) {
          return engineFirst ? const <ScreenshotSource>[ScreenshotSource.engine] : const <ScreenshotSource>[];
        }

        return engineFirst
            ? const <ScreenshotSource>[ScreenshotSource.engine, ScreenshotSource.surface]
            : const <ScreenshotSource>[ScreenshotSource.surface];
    }
  }

  Future<_CapturedFrame?> _captureVia(ScreenshotSource source, ScreenshotOptions options) {
    final attempt = switch (source) {
      ScreenshotSource.engine => _captureFromEngine(options),
      ScreenshotSource.surface => _captureFromSurface(options),
    };

    // A decoder that never answers must not leave a user action pending: a
    // timed-out capture is reported as an unavailable one.
    return attempt.timeout(options.timeout, onTimeout: () => null);
  }

  Future<_CapturedFrame?> _captureFromEngine(ScreenshotOptions options) async {
    try {
      final bytes = await _context.captureFromEngine(
        ScreenshotRequest(
          format: options.format,
          quality: options.effectiveQuality,
          includeSubtitles: options.includeSubtitles,
        ),
      );

      if (bytes == null || bytes.isEmpty) {
        return null;
      }

      // The engine returned the decoded frame, so the frame's own size is the
      // geometry the player reported for the stream.
      return _CapturedFrame(bytes: bytes, width: _context.frameWidth(), height: _context.frameHeight());
    } on Object catch (error) {
      // An engine that cannot capture on this platform throws instead of
      // declaring no capability; the surface route is the answer either way.
      MediaCoreLog.debug(
        LogCategory.renderer,
        'engine screenshot failed',
        fields: <String, Object?>{'playerId': _context.playerId.value, 'error': '$error'},
      );

      return null;
    }
  }

  Future<_CapturedFrame?> _captureFromSurface(ScreenshotOptions options) async {
    for (final surface in List<ScreenshotSurface>.of(_surfaces)) {
      try {
        final size = surface.captureSize(pixelRatio: options.pixelRatio);

        final bytes = await surface.capturePng(pixelRatio: options.pixelRatio);

        if (bytes == null || bytes.isEmpty) {
          continue;
        }

        // A surface capture is the size of the widget, not of the stream, so
        // the reported frame size comes from the surface — unless it is gone,
        // in which case the stream geometry is the closest true answer.
        return _CapturedFrame(
          bytes: bytes,
          width: size?.width.round() ?? _context.frameWidth(),
          height: size?.height.round() ?? _context.frameHeight(),
        );
      } on Object catch (error) {
        MediaCoreLog.debug(
          LogCategory.renderer,
          'surface screenshot failed',
          fields: <String, Object?>{'playerId': _context.playerId.value, 'error': '$error'},
        );
      }
    }

    return null;
  }

  void _remember(PlayerScreenshot screenshot) {
    _captures.add(screenshot);

    final limit = config.historyLimit;

    if (limit <= 0) {
      return;
    }

    final next = <PlayerScreenshot>[screenshot, ..._history.value];

    _history.add(next.length > limit ? next.sublist(0, limit) : next);
  }
}

/// Bytes produced by one route, with the size they describe.
///
/// The size cannot be read from the player: a surface capture is the size of
/// the widget, an engine capture is the size of the decoded frame, and the two
/// differ whenever the surface scales the video.
final class _CapturedFrame {
  const _CapturedFrame({required this.bytes, required this.width, required this.height});

  final Uint8List bytes;

  final int width;

  final int height;
}
