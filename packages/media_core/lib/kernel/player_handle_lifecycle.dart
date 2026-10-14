part of 'player_handle.dart';

/// Screenshots and the session-shaped lifecycle transitions: close,
/// activate, deactivate and pool recycle.
extension PlayerHandleLifecycle on PlayerHandle {
  /// Captures the current video frame.
  ///
  /// Two routes exist and the handle picks the best available one: the
  /// attached engine's own frame capture when it declares
  /// [PlayerAdapterCapabilities.supportsScreenshot], and otherwise the
  /// rendered surface of a [MediaPlayerView] currently displaying this player.
  /// The engine route is preferred because it returns the decoded frame at its
  /// real resolution and does not need a widget on screen; the surface route is
  /// what makes screenshots work on engines that have no capture API at all.
  ///
  /// Returns null when no route produced an image: no source is open, nothing
  /// has been decoded yet, no widget renders this player and the engine cannot
  /// capture, or the capture timed out. Use [canCaptureScreenshot] to offer the
  /// action only when it can work.
  ///
  /// Errors are not thrown: a screenshot is a user initiated convenience, and
  /// every failure mode has the same answer — no image.
  Future<PlayerScreenshot?> captureScreenshot({ScreenshotOptions options = ScreenshotOptions.defaults}) {
    _ensureNotDisposed();

    if (_currentSource == null) {
      return Future<PlayerScreenshot?>.value();
    }

    return _record(OperationType.captureScreenshot, () async {
      final screenshot = await _runtime.screenshots.capture(options: options);

      if (_disposed) {
        return screenshot;
      }

      if (screenshot != null) {
        _publish(PlayerEventType.renderer, <String, Object?>{
          'action': 'screenshot',
          'source': screenshot.source.name,
          'format': screenshot.format.name,
          'bytes': screenshot.sizeInBytes,
        });
      }

      return screenshot;
    }());
  }

  /// Whether [captureScreenshot] has any route it could take.
  ///
  /// False means a capture would return null right now — the engine cannot
  /// capture and no [MediaPlayerView] is rendering this player.
  bool get canCaptureScreenshot {
    if (_disposed || _currentSource == null) {
      return false;
    }

    return _runtime.screenshots.canCapture;
  }

  /// Stream of successful captures.
  ///
  /// A host that shows a thumbnail strip subscribes here instead of keeping
  /// the returned values, so it also sees captures it did not trigger.
  Stream<PlayerScreenshot> get screenshots => _runtime.screenshots.captures;

  /// Captures kept by this player, newest first.
  List<PlayerScreenshot> get recentScreenshots => _runtime.screenshots.recent;

  /// The most recent capture, if any.
  PlayerScreenshot? get latestScreenshot => _runtime.screenshots.latest;

  /// Captures kept by this player, newest first, as a stream.
  ValueStream<List<PlayerScreenshot>> get screenshotHistory => _runtime.screenshots.history;

  /// Attaches the surface of a widget rendering this player.
  ///
  /// Called by [MediaPlayerView] when it binds to this handle. A widget must
  /// detach what it attached, otherwise a capture keeps trying to read a
  /// boundary that is no longer mounted.
  void attachScreenshotSurface(ScreenshotSurface surface) {
    _runtime.screenshots.attachSurface(surface);
  }

  /// Detaches a surface previously attached through [attachScreenshotSurface].
  void detachScreenshotSurface(ScreenshotSurface surface) {
    _runtime.screenshots.detachSurface(surface);
  }

  /// Drops the kept captures, releasing their bytes.
  void clearScreenshotHistory() {
    _runtime.screenshots.clearHistory();
  }

  // ---------------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------------

  /// Closes the current source without disposing the player.
  Future<void> close() {
    _ensureNotDisposed();

    _invalidateOperations();

    _currentSource = null;
    _backendReady = false;
    playIntent = false;
    _ladder.reset();

    // The session context names the source; a closed player must not keep
    // reporting a sourceId (and a source) that is no longer open, or every
    // snapshot contradicts its own `source: null` field.
    _runtime.session.updateContext(
      SessionContext(
        playerId: _player.id,
        sessionId: _runtime.session.context.sessionId,
        generationId: _runtime.sessionController.recreateGeneration(),
        sourceId: PlayerSource.unknown().id,
        source: PlayerSource.unknown(),
        policy: policy,
        platform: _runtime.session.context.platform,
      ),
    );

    _announceSource(null);

    _cancelActiveOperation(StateError('PlayerIdentity close requested.'));

    return _record(
      OperationType.close,
      _enqueue(() async {
        if (_disposed) return;

        try {
          await _runtime.adapter.close();
        } on Object catch (_) {
          // Closing an already released backend is harmless here.
        }

        _backendReady = false;

        if (_disposed) return;

        await _runtime.playback.stop();

        if (_disposed) return;

        await _runtime.sessionController.stop();

        if (_disposed) return;

        _lifecycle.pause();

        _publish(PlayerEventType.playback, const <String, Object?>{'action': 'stop'});
      }),
    );
  }

  /// Marks the player active. Paired with [deactivate].
  void activate() {
    _ensureNotDisposed();
    _lifecycle.activate();
  }

  /// Deactivates the player and pauses playback when active.
  Future<void> deactivate() {
    _ensureNotDisposed();

    if (!_runtime.playback.current.isPlaying) {
      _lifecycle.pause();

      _publish(PlayerEventType.lifecycle, const <String, Object?>{'action': 'deactivated'});

      return Future<void>.value();
    }

    final source = _currentSource;

    playIntent = false;

    _ladder.suspend();
    _cancelActiveOperation(StateError('PlayerIdentity deactivation requested.'));

    return _enqueue(() async {
      if (_disposed) return;
      if (source != null && !_isSourceCurrent(source)) return;

      if (!_backendReady) {
        _lifecycle.pause();

        _publish(PlayerEventType.lifecycle, const <String, Object?>{'action': 'deactivated'});

        return;
      }

      try {
        await _runtime.adapter.pause();

        if (_disposed) return;
        if (source != null && !_isSourceCurrent(source)) return;

        await _runtime.playback.pause();

        if (_disposed) return;
        if (source != null && !_isSourceCurrent(source)) return;

        await _runtime.sessionController.pause();
      } on Object catch (_) {
        // Backend may already be releasing; deactivation continues.
      }

      if (_disposed) return;
      if (source != null && !_isSourceCurrent(source)) return;

      _lifecycle.pause();

      _publish(PlayerEventType.lifecycle, const <String, Object?>{'action': 'deactivated'});
    });
  }

  /// Resets this handle for pool reuse.
  Future<void> recycle() {
    _ensureNotDisposed();

    _invalidateOperations();

    _currentSource = null;
    _backendReady = false;
    playIntent = false;
    _ladder.reset();
    _announceSource(null);

    return _enqueue(() async {
      if (_disposed) return;

      try {
        await _runtime.adapter.close();
      } on Object catch (_) {
        // Recycling must not fail on a broken backend.
      }

      _backendReady = false;

      if (_disposed) return;

      final generationId = _runtime.sessionController.recreateGeneration();

      _runtime.session.updateContext(
        SessionContext(
          playerId: _player.id,
          sessionId: _runtime.session.context.sessionId,
          generationId: generationId,
          sourceId: PlayerSource.unknown().id,
          source: PlayerSource.unknown(),
          policy: policy,
          platform: _runtime.session.context.platform,
        ),
      );

      _runtime.session.updateState(const SessionState.idle());

      await _runtime.playback.stop();

      if (_disposed) return;

      _lifecycle.pause();
    });
  }
}
