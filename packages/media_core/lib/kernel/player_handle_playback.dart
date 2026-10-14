part of 'player_handle.dart';

/// Playback commands: open, play, pause, stop, seek, volume and rate.
///
/// Every command here is serialized through `_enqueue` and recorded as
/// an operation; none of them touches an adapter that no longer owns
/// the current source.
extension PlayerHandlePlayback on PlayerHandle {
  /// Sets whether audio output is muted.
  ///
  /// Implemented as volume bookkeeping: muting remembers the current
  /// volume and drives the adapter to 0, unmuting restores it. Safe to
  /// call before a source is open — the value is applied by [open] and
  /// re-asserted after every backend swap.
  Future<void> setMute({required bool muted}) {
    _ensureNotDisposed();

    if (muted == _muted) {
      return Future<void>.value();
    }

    if (muted) {
      _unmutedVolume = _pendingVolume ?? (_currentSource != null && _backendReady ? volume : config.volume);
      _muted = true;

      return setVolume(0);
    }

    _muted = false;

    return setVolume(_unmutedVolume <= 0.0 ? 1.0 : _unmutedVolume);
  }

  /// Sets whether playback restarts after completion.
  ///
  /// Affects the next completion event; a stream that has already
  /// completed must be replayed with [play] or [seek].
  Future<void> setLoop({required bool loop}) {
    _ensureNotDisposed();

    _loop = loop;

    return Future<void>.value();
  }

  /// Applies mute on [adapter] after open, recovery and engine swap.
  ///
  /// Separate from [setVolume] because the mute preference must survive
  /// operations that do not go through the caller ([_restoreSession],
  /// [_prepareStagedAdapter]).
  Future<void> _applyMute(PlayerAdapter adapter) async {
    if (!_muted) {
      return;
    }

    try {
      await adapter.setVolume(0);
    } on Object catch (error, stackTrace) {
      // Best effort: re-applied on the next open/swap. Logged because a
      // player that comes back audible after a swap is otherwise
      // indistinguishable from one the user unmuted.
      MediaCoreLog.warning(
        LogCategory.player,
        're-applying mute failed on ${_registration.id}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle and transport commands
  // ---------------------------------------------------------------------------

  /// Initializes the adapter and lifecycle.
  ///
  /// Called by the kernel after construction.
  Future<void> initialize() {
    return _record(
      OperationType.initialize,
      _enqueue(() async {
        await _runtime.adapter.initialize(_adapterContext);

        if (_disposed) {
          return;
        }

        _lifecycle
          ..create()
          ..initialize();

        _publish(PlayerEventType.player, const <String, Object?>{'action': 'initialized'});
      }),
    );
  }

  /// Opens [source] on the adapter.
  Future<void> open(PlayerSource source, {bool? autoPlay}) {
    _ensureNotDisposed();

    final operationGeneration = _invalidateOperations();

    final sourceChanged = _currentSource?.id != source.id;

    _currentSource = source;
    _backendReady = false;

    if (sourceChanged) {
      _announceSource(source);
    }

    return _record(
      OperationType.load,
      _enqueue(() async {
        if (!_isOperationCurrent(operationGeneration) || _disposed) {
          return;
        }

        // A new source is a new recovery story: whatever the ladder was
        // doing for the previous one is stale. This is also what makes the
        // ladder safe to leave running — every lifecycle boundary resets it
        // instead of racing it.
        _ladder.reset();

        final generationId = _runtime.sessionController.recreateGeneration();

        _runtime.session.updateContext(
          SessionContext(
            playerId: _player.id,
            sessionId: _runtime.session.context.sessionId,
            generationId: generationId,
            sourceId: source.id,
            source: source,
            policy: policy,
            platform: _runtime.session.context.platform,
          ),
        );

        await _runtime.sessionController.open();

        if (!_isOperationCurrent(operationGeneration) || _disposed) {
          return;
        }

        // The ladder was already reset before the session generation was
        // recreated, so it cannot be mid-step here.
        _ladder.resume();

        try {
          await _runtime.adapter.open(source);
        } catch (_) {
          if (_isOperationCurrent(operationGeneration) && _isSourceCurrent(source)) {
            _backendReady = false;
          }

          rethrow;
        }

        if (!_isOperationCurrent(operationGeneration) || _disposed || !_isSourceCurrent(source)) {
          try {
            await _runtime.adapter.close();
          } on Object catch (_) {
            // Best-effort cleanup of the stale open.
          }

          _backendReady = false;
          return;
        }

        _backendReady = true;

        if (config.volume != 1.0) {
          await _runtime.adapter.setVolume(config.volume);

          if (!_isOperationCurrent(operationGeneration) || _disposed || !_isSourceCurrent(source)) {
            _backendReady = false;

            try {
              await _runtime.adapter.close();
            } on Object catch (_) {}

            return;
          }
        }

        if (config.playbackRate != 1.0) {
          await _runtime.adapter.setRate(config.playbackRate);

          if (!_isOperationCurrent(operationGeneration) || _disposed || !_isSourceCurrent(source)) {
            _backendReady = false;

            try {
              await _runtime.adapter.close();
            } on Object catch (_) {}

            return;
          }
        }

        // ---------------------------------------------------------------------
        // Apply any volume / rate the caller queued while this source was
        // still opening. The queued value is an explicit user choice and
        // therefore wins over the config defaults applied above.
        //
        // This is what lets `setVolume` be safely called right after
        // `play()` returned, before the adapter had actually accepted the
        // source. Previously that path threw a `StateError` and tore down
        // the whole engine switch.
        // ---------------------------------------------------------------------
        final queuedVolume = _pendingVolume;
        if (queuedVolume != null && queuedVolume != config.volume) {
          await _runtime.adapter.setVolume(queuedVolume);

          if (!_isOperationCurrent(operationGeneration) || _disposed || !_isSourceCurrent(source)) {
            _backendReady = false;

            try {
              await _runtime.adapter.close();
            } on Object catch (_) {}

            return;
          }
        }
        _pendingVolume = null;

        final queuedRate = _pendingRate;
        if (queuedRate != null && queuedRate != config.playbackRate) {
          await _runtime.adapter.setRate(queuedRate);

          if (!_isOperationCurrent(operationGeneration) || _disposed || !_isSourceCurrent(source)) {
            _backendReady = false;

            try {
              await _runtime.adapter.close();
            } on Object catch (_) {}

            return;
          }
        }
        _pendingRate = null;

        // A fresh adapter starts with video enabled; re-assert the track
        // preference so a recovering engine cannot turn video back on.
        await _applyAudioOnly(_runtime.adapter);

        if (!_isOperationCurrent(operationGeneration) || _disposed || !_isSourceCurrent(source)) {
          _backendReady = false;
          return;
        }

        MediaCoreLog.info(
          LogCategory.source,
          'opened ${source.uri} on ${_registration.id}',
          fields: <String, Object?>{
            'player': _player.id.value,
            'protocol': source.protocol.name,
            'format': source.format.name,
            'live': source.isLive,
            'volume': config.volume,
            'rate': config.playbackRate,
          },
        );

        _publish(PlayerEventType.source, <String, Object?>{
          'action': 'opened',
          'uri': source.uri.toString(),
          'backend': _registration.id,
        });

        if (autoPlay ?? config.autoPlay) {
          final token = _createOperationToken();

          try {
            await _playInternal(operationGeneration, token: token, source: source);
          } finally {
            _releaseOperationToken(token);
          }
        }
      }),
    );
  }

  /// Opens [source] by first planning it against this handle's
  /// current adapter.
  ///
  /// The [MediaSourcePlanner] consulted here is the same one the
  /// kernel runs at creation time, so a Bilibili DASH pair swapped
  /// onto an already-created media_kit handle goes through the same
  /// composite-support branch and reaches the same outcome — either
  /// the flat [PlayerSource] the adapter expects (with the original
  /// composite preserved under [MediaSourceBridge.metadataKey]) or an
  /// explicit throw.
  ///
  /// Throws [UnsupportedError] when the plan is an [UnsupportedPlan];
  /// every other outcome delegates to [open].
  Future<void> openMedia(MediaSource source, {bool? autoPlay}) async {
    _ensureNotDisposed();

    final plan = _planner.plan(source, _registration.capabilities);

    // The `async` boundary is load-bearing: it is what turns a synchronous
    // throw here — a disposed handle, an unsupported plan — into an error on
    // the returned Future, which is what every caller of this method awaits.
    switch (plan) {
      case DirectPlan():
      case CompositePlan():
        await open(source.toPlayerSource(), autoPlay: autoPlay);
        return;
      case UnsupportedPlan(:final reason):
        throw UnsupportedError(reason);
    }
  }

  /// Starts playback.
  Future<void> play() {
    _ensureNotDisposed();
    _ensureSource();

    playIntent = true;

    final operationGeneration = _captureOperationGeneration();
    final source = _currentSource!;

    final token = _createOperationToken();

    return _record(
      OperationType.play,
      _enqueue(() async {
        try {
          // An explicit play is a fresh recovery opportunity: it cancels a
          // previous suspend (see [pause]).
          _ladder.resume();

          await _playInternal(operationGeneration, token: token, source: source);
        } finally {
          _releaseOperationToken(token);
        }
      }),
    );
  }

  Future<void> _playInternal(
    int operationGeneration, {
    required OperationCancelToken token,
    PlayerSource? source,
  }) async {
    if (!_canUseBackend(operationGeneration: operationGeneration, source: source) || token.isCancelled) {
      return;
    }

    await token.runChecked(() => _runtime.adapter.play());

    if (!_canUseBackend(operationGeneration: operationGeneration, source: source) || token.isCancelled) {
      return;
    }

    await token.runChecked(() => _runtime.playback.play());

    if (!_canUseBackend(operationGeneration: operationGeneration, source: source) || token.isCancelled) {
      return;
    }

    await token.runChecked(() => _runtime.sessionController.play());

    if (!_canUseBackend(operationGeneration: operationGeneration, source: source) || token.isCancelled) {
      return;
    }

    _lifecycle.activate();

    _publish(PlayerEventType.playback, const <String, Object?>{'action': 'play'});
  }

  /// Pauses playback.
  Future<void> pause() {
    _ensureNotDisposed();
    _ensureSource();

    final source = _currentSource!;

    playIntent = false;

    // A user pause is a recovery boundary: recovery for playback the user
    // just stopped is stale by definition.
    _ladder.suspend();
    _cancelActiveOperation(StateError('Playback pause requested.'));

    return _record(
      OperationType.pause,
      _enqueue(() async {
        if (_disposed) return;
        if (!_isSourceCurrent(source)) return;
        if (!_backendReady) return;

        await _runtime.adapter.pause();

        if (_disposed || !_isSourceCurrent(source)) return;

        await _runtime.playback.pause();

        if (_disposed || !_isSourceCurrent(source)) return;

        await _runtime.sessionController.pause();

        if (_disposed || !_isSourceCurrent(source)) return;

        _lifecycle.pause();

        _publish(PlayerEventType.playback, const <String, Object?>{'action': 'pause'});
      }),
    );
  }

  /// Stops playback and clears the session state.
  Future<void> stop() {
    _ensureNotDisposed();

    if (_currentSource == null) {
      return Future<void>.value();
    }

    final source = _currentSource;

    playIntent = false;

    _ladder.suspend();
    _cancelActiveOperation(StateError('Playback stop requested.'));

    return _record(
      OperationType.stop,
      _enqueue(() async {
        if (_disposed) return;
        if (source != null && !_isSourceCurrent(source)) return;
        if (!_backendReady) return;

        await _runtime.adapter.stop();

        if (_disposed) return;
        if (source != null && !_isSourceCurrent(source)) return;

        await _runtime.playback.stop();

        if (_disposed) return;
        if (source != null && !_isSourceCurrent(source)) return;

        await _runtime.sessionController.stop();

        if (_disposed) return;
        if (source != null && !_isSourceCurrent(source)) return;

        // Nothing is playing any more, so the lifecycle must not keep claiming
        // the player is active: pause()/deactivate() already do this, and a
        // stopped player that still reports `isActive` contradicts the session
        // and playback facts the same handle exposes.
        _lifecycle.pause();

        _publish(PlayerEventType.playback, const <String, Object?>{'action': 'stop'});
      }),
    );
  }

  /// Seeks to [position].
  Future<void> seek(Duration position) {
    _ensureNotDisposed();
    _ensureSource();

    final operationGeneration = _captureOperationGeneration();
    final source = _currentSource!;

    final token = _createOperationToken();

    return _record(
      OperationType.seek,
      _enqueue(() async {
        try {
          if (!_canUseBackend(operationGeneration: operationGeneration, source: source) || token.isCancelled) {
            return;
          }

          await token.runChecked(() => _runtime.adapter.seek(position));

          if (!_canUseBackend(operationGeneration: operationGeneration, source: source) || token.isCancelled) {
            return;
          }

          await token.runChecked(() => _runtime.playback.seek(position));

          if (!_canUseBackend(operationGeneration: operationGeneration, source: source) || token.isCancelled) {
            return;
          }

          _publish(PlayerEventType.playback, <String, Object?>{
            'action': 'seek',
            'positionMs': position.inMilliseconds,
          });
        } finally {
          _releaseOperationToken(token);
        }
      }),
    );
  }

  /// Sets the volume in the 0.0–1.0 range.
  ///
  /// This method may be called before the source has finished opening
  /// (for example by an engine switch that calls it right after
  /// `play()` returned). In that case the value is queued and applied
  /// by [open] once the adapter has accepted the source. It never
  /// throws merely because the source is not yet ready.
  Future<void> setVolume(double volume) {
    _ensureNotDisposed();

    final clamped = volume.clamp(0.0, 1.0);

    // No source open yet: remember the value and let [open] apply it.
    // The playback controller is updated immediately so consumers that
    // read `playback.volume` (fallback re-attachment, snapshots) see the
    // correct value even before the adapter accepts it.
    if (_currentSource == null || !_backendReady) {
      _pendingVolume = clamped;
      _runtime.playback.apply(PlaybackCommand.volume(clamped));
      return Future<void>.value();
    }

    final operationGeneration = _captureOperationGeneration();
    final source = _currentSource!;

    // No cancellation token here on purpose: the slot is the one play/seek
    // continuations are checked against, so a volume request that took it used
    // to cancel the operation still running — the engine never saw that play at
    // all. Drag intermediates are dropped by the request number instead.
    final request = ++_volumeRequest;

    return _record(
      OperationType.setVolume,
      _enqueue(() async {
        if (request != _volumeRequest) {
          return;
        }

        if (!_canUseBackend(operationGeneration: operationGeneration, source: source)) {
          return;
        }

        await _runtime.adapter.setVolume(clamped);

        if (!_canUseBackend(operationGeneration: operationGeneration, source: source)) {
          return;
        }

        _runtime.playback.apply(PlaybackCommand.volume(clamped));
        _pendingVolume = null;

        if (!_canUseBackend(operationGeneration: operationGeneration, source: source)) {
          return;
        }

        _publish(PlayerEventType.audio, <String, Object?>{'action': 'volume', 'volume': clamped});
      }),
    );
  }

  /// Sets the playback rate.
  ///
  /// Mirrors [setVolume]: a rate set before the source is open is
  /// queued and applied by [open].
  Future<void> setRate(double rate) {
    _ensureNotDisposed();

    if (_currentSource == null || !_backendReady) {
      _pendingRate = rate;
      _runtime.playback.apply(PlaybackCommand.rate(rate));
      return Future<void>.value();
    }

    final operationGeneration = _captureOperationGeneration();
    final source = _currentSource!;

    // Mirrors [setVolume]: a rate slider drags one request per frame, and the
    // cancellation slot belongs to whatever play/seek is still running.
    final request = ++_rateRequest;

    return _record(
      OperationType.setPlaybackRate,
      _enqueue(() async {
        if (request != _rateRequest) {
          return;
        }

        if (!_canUseBackend(operationGeneration: operationGeneration, source: source)) {
          return;
        }

        await _runtime.adapter.setRate(rate);

        if (!_canUseBackend(operationGeneration: operationGeneration, source: source)) {
          return;
        }

        _runtime.playback.apply(PlaybackCommand.rate(rate));
        _pendingRate = null;

        if (!_canUseBackend(operationGeneration: operationGeneration, source: source)) {
          return;
        }

        _publish(PlayerEventType.playback, <String, Object?>{'action': 'rate', 'rate': rate});
      }),
    );
  }
}
