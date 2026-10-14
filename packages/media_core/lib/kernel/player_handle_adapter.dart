part of 'player_handle.dart';

/// Adapter subscription and the adapter event bridge.
///
/// Only handles what the runtime does not:
///
/// - session transitions
/// - recovery / fallback triggers
/// - lifecycle transitions
/// - event bus publication
/// - completion restarts (config.loop)
///
/// Playback state is updated by PlayerPlaybackBinding.
/// Geometry state is updated by PlayerGeometryBinding.
extension _HandleAdapterBridge on PlayerHandle {
  /// Subscribes to one adapter and rejects events from an adapter that
  /// is no longer active.
  ///
  /// This subscription coexists with the two bindings inside
  /// [PlayerRuntime]: the adapter's event stream is broadcast, so all
  /// three consumers receive events independently. This subscription
  /// handles only handle-level concerns — session transitions,
  /// recovery, event bus publication and completion. The bindings
  /// handle playback and geometry state.
  ///
  /// It also feeds [adapterEvents], which is how consumers survive a
  /// backend swap: they listen to the handle once, and the handle is the
  /// only place that re-subscribes when the adapter instance is
  /// replaced.
  void _subscribeAdapter(PlayerAdapter adapter) {
    _adapterSubscription = adapter.events.listen(
      (event) {
        if (_disposed || !identical(adapter, _runtime.adapter)) {
          return;
        }

        if (!_adapterEvents.isClosed) {
          _adapterEvents.add(event);
        }

        _onAdapterEvent(event);
      },
      // An error delivered through the stream itself — not wrapped in a
      // PlayerAdapterErrorEvent — still has to reach the session, or the
      // backend fails and the handle keeps reporting the last good state.
      onError: (Object error, StackTrace stackTrace) {
        _handleAdapterError('adapter stream error', error, stackTrace);
      },
    );
  }

  /// Replaces the active adapter and moves the handle's own subscription
  /// to it.
  ///
  /// The runtime swaps its bindings; this covers the handle's
  /// subscription, the registration record and the consumers of
  /// [adapterEvents] and [backendChanges].
  Future<void> _installAdapter(PlayerAdapter next, PlayerAdapterRegistration registration) async {
    final previous = _runtime.adapter;
    final previousSubscription = _adapterSubscription;

    _adapterSubscription = null;
    _registration = registration;

    // Detach the handle's listener before the runtime drops its
    // bindings, so no event from the outgoing adapter reaches a
    // half-swapped runtime.
    await previousSubscription?.cancel();

    await _runtime.replaceAdapter(next);

    _subscribeAdapter(next);

    if (!_backendChanges.isClosed) {
      _backendChanges.add(PlayerBackendChange(from: previous.id, to: registration.id, adapter: next));
    }

    // [PlayerRuntime.replaceAdapter] swaps its bindings but deliberately does
    // not dispose the outgoing adapter - it documents that the caller owns
    // that. Without this the retired engine keeps its native player, threads
    // and surface alive for the rest of the process, once per swap.
    if (!identical(previous, next)) {
      try {
        await previous.dispose();
      } on Object catch (_) {
        // A backend that refuses to release must not fail the swap that
        // already succeeded.
      }
    }
  }

  /// Applies the audio-only preference to [adapter] when it declares
  /// the capability.
  ///
  /// Best effort: a track switch that fails does not invalidate the
  /// playback that is already running, and the next open or swap applies
  /// the preference again.
  Future<void> _applyAudioOnly(PlayerAdapter adapter) async {
    await _applyMute(adapter);

    if (!adapter.capabilities.supportsAudioOnly) {
      return;
    }

    try {
      await adapter.setAudioOnly(audioOnly: _audioOnly);
    } on Object catch (error, stackTrace) {
      // See above: the preference is re-applied on the next open/swap.
      // It is still logged, because a swap that comes back with the
      // picture on and the audio-only request dropped is invisible
      // everywhere else.
      MediaCoreLog.warning(
        LogCategory.player,
        'setAudioOnly($_audioOnly) failed on ${_registration.id}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Publishes the source the handle is now playing.
  void _announceSource(PlayerSource? source) {
    if (_sourceChanges.isClosed) {
      return;
    }

    _sourceChanges.add(source);
  }

  // ---------------------------------------------------------------------------
  // Adapter event bridge
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Adapter event bridge
  //
  // Only handles what the runtime does not:
  //
  // - session transitions
  // - recovery / fallback triggers
  // - lifecycle transitions
  // - event bus publication
  // - completion restarts (config.loop)
  //
  // Playback state is updated by PlayerPlaybackBinding.
  // Geometry state is updated by PlayerGeometryBinding.
  // ---------------------------------------------------------------------------

  void _onAdapterEvent(PlayerAdapterEvent event) {
    if (_disposed) {
      return;
    }

    switch (event) {
      case PlayerAdapterOpened():
        _publish(PlayerEventType.source, const <String, Object?>{'action': 'adapterOpened'});

      case PlayerAdapterPlaying():
        // PlaybackController updated by PlayerPlaybackBinding.
        //
        // The session transition is fire-and-forget: the controller updates
        // its state synchronously and its Future cannot fail, while this
        // bridge is the synchronous event fan-out — awaiting here would
        // reorder the handle's own events and let a later adapter event
        // overtake an earlier session transition.
        unawaited(_runtime.sessionController.play());

      case PlayerAdapterPaused():
        unawaited(_runtime.sessionController.pause());

      case PlayerAdapterStopped():
        unawaited(_runtime.sessionController.stop());

      case PlayerAdapterBuffering(:final buffering, :final progress):
        // PlaybackController updated by PlayerPlaybackBinding.
        //
        // The flag is forwarded, not implied: `buffering: false` ends the
        // condition, and treating it as "enter buffering" left the session in
        // that status (loading == true) after the stream had recovered.
        _runtime.sessionController.setBuffering(buffering: buffering);

        _publish(PlayerEventType.buffering, <String, Object?>{'buffering': buffering, 'progress': progress});

      case PlayerAdapterCompleted():
        _runtime.sessionController.complete();

        _publish(PlayerEventType.playback, const <String, Object?>{'action': 'completed'});

        unawaited(_restartForLoop());

      case PlayerAdapterPositionChanged():
      case PlayerAdapterDurationChanged():
      case PlayerAdapterVolumeChanged():
      case PlayerAdapterRateChanged():
        // Handled by PlayerPlaybackBinding.
        break;

      case PlayerAdapterVideoSizeChanged(:final width, :final height):
        // GeometryController updated by PlayerGeometryBinding.
        _publish(PlayerEventType.renderer, <String, Object?>{'width': width, 'height': height});

      case PlayerAdapterVideoFrameProgress():
        // Frame heartbeat is consumed by adapter-level watchdogs.
        break;

      case PlayerAdapterVideoReconfigured():
        _publish(PlayerEventType.renderer, const <String, Object?>{'action': 'videoReconfigured'});

      case PlayerAdapterHwdecChanged(:final decoder):
        _publish(PlayerEventType.renderer, <String, Object?>{'action': 'hwdecChanged', 'decoder': decoder});

      case PlayerAdapterAudioReconfigured():
        _publish(PlayerEventType.audio, const <String, Object?>{'action': 'audioReconfigured'});

      case PlayerAdapterAudioDeviceChanged(:final device):
        _publish(PlayerEventType.audio, <String, Object?>{'action': 'audioDeviceChanged', 'device': device});

      case PlayerAdapterSubtitleChanged(:final text):
        _publish(PlayerEventType.renderer, <String, Object?>{'action': 'subtitleChanged', 'text': text});

      case PlayerAdapterCacheChanged(:final buffering, :final duration, :final progress):
        _publish(PlayerEventType.buffering, <String, Object?>{
          'action': 'cacheChanged',
          'buffering': buffering,
          'durationMs': duration?.inMilliseconds,
          'progress': progress,
        });

      case PlayerAdapterBufferedRangesChanged(:final ranges):
        // The transport state carries the canonical view (the binding
        // normalizes it); this event is the moment the bar repaints,
        // so it publishes the raw reach figure the UI can draw
        // without recomputing.
        _publish(PlayerEventType.buffering, <String, Object?>{
          'action': 'bufferedRanges',
          'ranges': ranges
              .map((range) => <String, int>{'startMs': range.start.inMilliseconds, 'endMs': range.end.inMilliseconds})
              .toList(),
        });

      case PlayerAdapterMetadataChanged(:final metadata):
        _publish(PlayerEventType.player, <String, Object?>{'action': 'metadataChanged', 'metadata': metadata});

      case PlayerAdapterPlaylistChanged(:final items, :final index):
        _publish(PlayerEventType.player, <String, Object?>{
          'action': 'playlistChanged',
          'items': items,
          'index': index,
        });

      case PlayerAdapterClientMessage(:final message, :final args):
        _publish(PlayerEventType.player, <String, Object?>{
          'action': 'clientMessage',
          'message': message,
          'args': args,
        });

      case PlayerAdapterLogMessage(:final level, :final prefix, :final text):
        _publish(PlayerEventType.player, <String, Object?>{
          'action': 'logMessage',
          'level': level,
          'prefix': prefix,
          'text': text,
        });

      case PlayerAdapterErrorEvent(:final message, :final error, :final stackTrace):
        _handleAdapterError(message, error, stackTrace);
    }
  }

  /// Restarts a looping source after completion, reporting a failure instead
  /// of dropping it.
  ///
  /// The adapter-event bridge cannot await this, so the error has to go
  /// somewhere: a failed replay is a playback failure, and it is reported as
  /// one rather than becoming an unhandled async error.
  Future<void> _restartForLoop() async {
    try {
      await _handleCompletion();
    } on Object catch (error, stackTrace) {
      if (_disposed) {
        return;
      }

      reportFailure(
        RecoveryFailure.fromMessage(
          'loop restart failed on ${_registration.id}: $error',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Restarts a looping source after completion.
  Future<void> _handleCompletion() async {
    if (!_isCurrentPlaybackContext()) {
      return;
    }

    final source = _currentSource;

    if (!_loop || source == null || _disposed || !_backendReady) {
      return;
    }

    final operationGeneration = _operationGeneration;
    final sourceId = source.id;

    // Deliberately no cancellation token: `_createOperationToken` cancels the
    // *previous* active continuation, so a completion arriving while a user's
    // play()/seek() is still in flight would cancel that unrelated operation.
    // The generation and source checks already make this body stale-safe.
    await _enqueue(() async {
      if (!_isOperationCurrent(operationGeneration) || !_isSourceIdCurrent(sourceId) || !_backendReady) {
        return;
      }

      await _runtime.adapter.seek(Duration.zero);

      if (!_isOperationCurrent(operationGeneration) || !_isSourceIdCurrent(sourceId) || !_backendReady) {
        return;
      }

      await _runtime.adapter.play();

      if (!_isOperationCurrent(operationGeneration) || !_isSourceIdCurrent(sourceId) || !_backendReady) {
        return;
      }

      await _runtime.playback.play();

      if (!_isOperationCurrent(operationGeneration) || !_isSourceIdCurrent(sourceId) || !_backendReady) {
        return;
      }

      await _runtime.sessionController.play();
    });
  }

  bool _isCurrentPlaybackContext() {
    return !_disposed && _currentSource != null && _backendReady;
  }

  /// Normalizes an adapter error into a recovery report.
  ///
  /// The handle does not decide anything here. It classifies the message
  /// (recovery owns that normalization), publishes the error for the
  /// event bus, and hands the failure to the ladder. Whether the player
  /// reopens, switches line, switches backend or gives up is the ladder's
  /// decision and nobody else's.
  void _handleAdapterError(String message, Object? error, StackTrace? stackTrace) {
    if (_disposed) {
      return;
    }

    _runtime.sessionController.error(message);

    _eventBus.publish(PlayerErrorEvent(error: error ?? message, stackTrace: stackTrace, context: _buildContext()));

    MediaCoreLog.warning(
      LogCategory.error,
      'adapter error on ${_registration.id}: $message',
      error: error,
      stackTrace: stackTrace,
      // The effective gate below, not the configured defaults: reporting only
      // `_options.enableRecovery && config.enableRecovery` printed
      // `recoveryEnabled=true` for a handle whose recovery the playback owner
      // had explicitly disabled, which reads as "the ladder is running" during
      // a triage where it is not.
      fields: <String, Object?>{'recoveryEnabled': recoveryEnabled && _options.enableRecovery && config.enableRecovery},
    );

    if (!recoveryEnabled || !_options.enableRecovery || !config.enableRecovery) {
      return;
    }

    reportFailure(
      RecoveryFailure.fromMessage(message, error: error, stackTrace: stackTrace, source: RecoveryFailureSource.adapter),
    );
  }

  EventContext _buildContext() {
    return EventContext(
      playerId: _player.id,
      sessionId: _runtime.session.context.sessionId,
      sourceId: _currentSource?.id,
      generationId: _runtime.session.generation.id,
    );
  }

  void _publish(PlayerEventType type, Map<String, Object?> data, {EventPriority priority = EventPriority.normal}) {
    if (!_options.enableEventBus || _disposed) {
      return;
    }

    _eventBus.publish(GenericPlayerEvent(type: type, data: data, priority: priority, context: _buildContext()));
  }
}
