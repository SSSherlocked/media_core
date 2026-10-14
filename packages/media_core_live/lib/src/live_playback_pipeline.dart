part of 'live_playback_controller.dart';

/// The machinery around the sweep: which engines to try and in what
/// order, how a handle is attached and released, how watchdog and
/// adapter events become recover tasks, and the single-slot task queue
/// every public action waits on.
extension _LivePlaybackPipeline on LivePlaybackController {
  // ---------------------------------------------------------------------------
  // Engine order and handle lifecycle
  // ---------------------------------------------------------------------------

  /// Backend ids to try, best first: the pinned engine (if any), then the
  /// selector's scored order for the primary source.
  List<String> _engineOrder() {
    final primary = _sources.isNotEmpty ? _sources.first : _request?.primary;
    final source = primary ?? _request!.primary;
    final scored = kernel.selector
        .candidatesFor(source)
        .where((registration) => registration.enabled)
        .map((registration) => registration.id)
        .toList(growable: false);

    // A pinned engine still has to be able to play the source. The user
    // preference must not put an engine that does not declare the source's
    // format at the front of the sweep: it would burn every single-use
    // line failing on a format it cannot decode before a capable engine
    // gets its turn. With an unknown format nothing is filtered.
    final capable = source.format.isKnown
        ? scored
              .where((id) {
                final registration = kernel.registry.get(id);

                return registration == null || kernel.selector.formatMatches(registration.capabilities, source);
              })
              .toList(growable: false)
        : scored;

    final engines = capable.isNotEmpty ? capable : scored;

    final pinned = _preferredBackend;

    if (pinned == null) {
      return engines;
    }

    if (!engines.contains(pinned)) {
      // The pin lost its turn because its own declaration excludes this
      // format. Silence here is what makes "I chose ExoPlayer and got mpv"
      // unanswerable from the outside — the preference was honoured all the
      // way to this line and then dropped. Either the declaration is too
      // narrow (FLV was, see `BetterPlayerFormats`) or the engine really
      // cannot open the source, and both are worth a line.
      MediaCoreLog.warning(
        LogCategory.fallback,
        'pinned engine "$pinned" does not declare the source format — falling back to the scored order',
        fields: <String, Object?>{'pinned': pinned, 'format': source.format.name, 'tried': engines.join(',')},
      );

      return engines;
    }

    return <String>[pinned, ...engines.where((id) => id != pinned)];
  }

  void _attach(PlayerHandle handle) {
    _handle = handle;

    if (!_handleController.isClosed) {
      _handleController.add(handle);
    }

    handle.recoveryEnabled = false;

    watchdogs.updateCapabilities(handle.adapter.capabilities);
    watchdogs.setVideoExpected(expected: !_audioOnly);

    // The staged engine plays *before* it is attached: open/play/verify
    // all run while nothing feeds the watchdogs, so their playing state is
    // stale at attach time and the adapter's Playing event - a one-shot on
    // engines with a state latch - may never arrive again. Seed from the
    // declared intent rather than the adapter mirror: live always declares
    // play intent, and the mirror can read "paused" for an engine that
    // paused itself mid-open (mpv does) even though playback is on.
    watchdogs.onPlayingChanged(playing: _playbackRequested, fromUserIntent: false);

    _seedPlaybackState(handle);

    // Dropping these cancels is deliberate: cancelling stops delivery from the
    // retiring handle, and its replacement listener is installed on the very
    // next line, so awaiting would only defer the attach without changing what
    // can still arrive. The cancels in [_releaseHandle] are awaited, because
    // that is the boundary where the player itself goes away.
    unawaited(_adapterSub?.cancel());
    _adapterSub = handle.adapterEvents.listen(_onAdapterEvent, onError: (Object _) {});

    unawaited(_backendSub?.cancel());
    _backendSub = handle.backendChanges.listen((change) {
      watchdogs.updateCapabilities(change.adapter.capabilities);
      watchdogs.setVideoExpected(expected: !_audioOnly);
    });

    if (_audioOnly) {
      unawaited(handle.setAudioOnly(audioOnly: true));
    }
  }

  Future<void> _releaseHandle() async {
    // Awaited: `cancel` is the point at which the subscription guarantees it
    // will call nothing further, and this method is precisely the "the player is
    // going away" boundary. Dropping it would let a late event land on a handle
    // that has already been released.
    await _adapterSub?.cancel();
    _adapterSub = null;
    await _backendSub?.cancel();
    _backendSub = null;

    final handle = _handle;
    _handle = null;
    _currentSource = null;

    if (handle != null && !_handleController.isClosed) {
      _handleController.add(handle);
    }

    watchdogs.updateCapabilities(null);

    if (handle != null) {
      try {
        await kernel.release(handle.id);
      } on Object catch (_) {
        // Best-effort release of an engine that may already be gone.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Watchdogs and adapter events → recover tasks
  // ---------------------------------------------------------------------------

  void _wireWatchdogs() {
    watchdogs.onStall = (kind) {
      // A task already running owns the player: a sweep handles its own
      // failures, and pause/close supersede recovery. Only a stall with
      // the queue idle — normal playback — enqueues a recover task.
      if (!_playbackRequested || _disposed || _draining) {
        return;
      }

      MediaCoreLog.warning(
        LogCategory.recovery,
        'watchdog stall: ${kind.name}',
        fields: <String, Object?>{'line': _currentSource?.uri.toString(), 'backend': backendId},
      );

      // A stall is a failure like any other: reopen the playing line
      // first, then let the sweep decide. Queued behind whatever is in
      // flight; superseded by the next user action.
      _supersedeQueued('superseded by stall recovery');
      _sweepStart = _sourceIndex;

      unawaited(_enqueue(TaskType.recover, _runRecoverTask));
    };

    watchdogs.onRecoveryRequested = (action) {
      if (!_playbackRequested || _disposed) {
        watchdogs.reportRecoveryResult(resumed: false);
        return;
      }

      // reassertPlay is a command, not a recovery: it goes through the
      // handle directly so the watchdog gets its answer immediately.
      final handle = _handle;

      if (handle == null || handle.disposed) {
        watchdogs.reportRecoveryResult(resumed: false);
        return;
      }

      unawaited(
        handle.play().then(
          (_) {
            watchdogs.reportRecoveryResult(resumed: true);
          },
          onError: (Object _) {
            watchdogs.reportRecoveryResult(resumed: false);
          },
        ),
      );
    };
  }

  /// Re-opens a line that just died — after offering the caller a chance to
  /// replace it. See [_refreshSourcesForRecovery].
  Future<void> _runRecoverTask(TaskCancelToken token) async {
    await _refreshSourcesForRecovery();

    await _sweep(startAtCurrent: true);
  }

  /// Re-aligns the mirrored playback state with the adapter's own semantic
  /// state on every position heartbeat.
  ///
  /// The adapter's [PlayerAdapter.state] cannot drift: the adapter updates it
  /// itself for every event it emits. The mirror, however, is fed through
  /// subscriptions that an engine attached mid-playback joins late, so
  /// playback edges (Playing, Buffering(false)) can be missed. Position
  /// events arrive several times a second regardless, which makes them a
  /// free heartbeat: any mirror that says "not playing" while the engine is
  /// playing is corrected within a second. Only upgrades are applied —
  /// downgrades to paused belong to the user-command paths.
  void _reconcileMirroredPlayback() {
    final handle = _handle;
    if (handle == null || handle.disposed) {
      return;
    }

    final truth = handle.adapter.state.playback;
    if (truth == PlayerPlaybackState.playing && state.playback != PlayerPlaybackState.playing) {
      _setState(_liveState(PlayerPlaybackState.playing));
    }
  }

  /// Mirrors the playback state an engine reached before it was attached.
  ///
  /// A staged engine is opened and plays while it is still being verified,
  /// so its `Playing` event — a one-shot edge on engines with a state latch
  /// — fires before this pipeline subscribes to [PlayerHandle.adapterEvents].
  /// Without this seed the mirrored [PlayerCoreState] stays at `opening`
  /// even though audio and video are out, and every consumer that trusts
  /// the mirror (UI play/pause state, `isPlayingNow`) reads the room as
  /// paused forever.
  void _seedPlaybackState(PlayerHandle handle) {
    switch (handle.adapter.state.playback) {
      case PlayerPlaybackState.playing:
        _setState(_liveState(PlayerPlaybackState.playing));
      case PlayerPlaybackState.paused:
        _setState(_liveState(PlayerPlaybackState.paused));

      // Everything else is a transition the sweep itself already reports
      // (`opening`, `buffering`) or a state a live stream is not meant to
      // reach, so mirroring it would overwrite the controller's own write.
      case PlayerPlaybackState.idle:
      case PlayerPlaybackState.opening:
      case PlayerPlaybackState.buffering:
      case PlayerPlaybackState.seeking:
      case PlayerPlaybackState.stopping:
      case PlayerPlaybackState.stopped:
      case PlayerPlaybackState.completed:
      case PlayerPlaybackState.error:
        break;
    }
  }

  void _onAdapterEvent(PlayerAdapterEvent event) {
    if (_disposed) {
      return;
    }

    switch (event) {
      case PlayerAdapterPlaying():
        _setState(_liveState(PlayerPlaybackState.playing));
        watchdogs.onPlayingChanged(playing: true, fromUserIntent: false);

      case PlayerAdapterPaused():
        watchdogs.onPlayingChanged(playing: false, fromUserIntent: !_playbackRequested);

        if (!_playbackRequested) {
          _setState(_liveState(PlayerPlaybackState.paused));
        }

      case PlayerAdapterBuffering(:final buffering):
        _setState(_liveState(buffering ? PlayerPlaybackState.buffering : PlayerPlaybackState.playing));
        watchdogs.onBufferingChanged(buffering: buffering);

      case PlayerAdapterPositionChanged(:final position):
        watchdogs.onPositionProgress(position);
        _reconcileMirroredPlayback();

      case PlayerAdapterVideoFrameProgress():
        watchdogs.onFrameProgress();

      case PlayerAdapterErrorEvent(:final message):
        MediaCoreLog.warning(
          LogCategory.error,
          'adapter error: $message',
          fields: <String, Object?>{'backend': backendId, 'line': _currentSource?.uri.toString()},
        );

        // The queue is the serialization authority. A task already
        // running (a sweep, a pause, a close) owns this failure: the
        // sweep's catch advances to the next candidate, and pause/close
        // supersede recovery outright. Only an error with the queue idle
        // — normal playback — enqueues a recover task.
        if (_draining) {
          _sweepAdapterError = message;
        } else if (_playbackRequested) {
          _supersedeQueued('superseded by adapter error');
          _sweepStart = _sourceIndex;

          unawaited(_enqueue(TaskType.recover, _runRecoverTask));
        }

      case PlayerAdapterVideoSizeChanged():
      case PlayerAdapterStopped():
      case PlayerAdapterCompleted():
      case PlayerAdapterOpened():
      case PlayerAdapterDurationChanged():
      case PlayerAdapterVideoReconfigured():
      case PlayerAdapterHwdecChanged():
      case PlayerAdapterAudioReconfigured():
      case PlayerAdapterAudioDeviceChanged():
      case PlayerAdapterSubtitleChanged():
      case PlayerAdapterCacheChanged():
      case PlayerAdapterMetadataChanged():
      case PlayerAdapterPlaylistChanged():
      case PlayerAdapterClientMessage():
      case PlayerAdapterLogMessage():
      case PlayerAdapterVolumeChanged():
      case PlayerAdapterRateChanged():
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Task queue plumbing
  // ---------------------------------------------------------------------------

  /// Queues [action] as a task and starts draining.
  ///
  /// The action travels with its task: the drain handler dispatches by
  /// task id, so the order actions were enqueued in is the order they run
  /// in, regardless of which enqueue happened to start the drain.
  Future<void> _enqueue(TaskType type, Future<void> Function(TaskCancelToken token) action) {
    final pending = _PendingTask(action);
    final task = _tasks.createAndQueue(
      id: TaskId.generate(),
      type: type,
      playerId: _handle?.id,
      generationId: GenerationId.generate(),
    );

    _pending[task.id] = pending;

    unawaited(_drain());

    return pending.completer.future;
  }

  /// Runs queued tasks one at a time. Capacity is one; this loop is what
  /// turns the queue into the controller's serialization spine.
  Future<void> _drain() async {
    if (_draining) {
      return;
    }

    _draining = true;

    try {
      while (!_disposed && _tasks.hasQueuedTasks) {
        try {
          await _tasks.executeAvailable((task) async {
            final pending = _pending.remove(task.id);

            if (pending == null) {
              return null;
            }

            final token = _tasks.cancelToken(task.id);

            // The operation record lives on the handle (the anchor every
            // consumer holds). A task that creates the handle records from
            // the moment it exists; earlier there is simply nothing to
            // record on.
            _handle?.beginOperation(_operationTypeOf(task.type));

            try {
              if (token == null || !token.isCancelled) {
                await pending.action(token ?? TaskCancelToken());
              }

              pending.completer.complete();
              _handle?.completeOperation();
            } catch (error, stackTrace) {
              pending.completer.completeError(error, stackTrace);
              _handle?.failOperation();
              rethrow;
            }

            return null;
          });
        } on Object catch (error) {
          // A task that threw after its own completer was already settled
          // (or a manager-level failure) ends here; the task record keeps
          // the failure for diagnostics.
          MediaCoreLog.debug(LogCategory.player, 'live task ended: $error');
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Cancels every queued (not yet started) task and releases its waiter.
  void _supersedeQueued(String reason) {
    final cancelled = _tasks.cancelQueuedTasks(reason);

    for (final task in cancelled) {
      _pending.remove(task.id)?.completer.complete();
    }
  }

  /// Task types and operation types describe the same actions; the record
  /// is written in the operation module's vocabulary.
  OperationType _operationTypeOf(TaskType type) {
    return switch (type) {
      TaskType.open => OperationType.open,
      TaskType.load => OperationType.load,
      TaskType.retry => OperationType.retry,
      TaskType.pause => OperationType.pause,
      TaskType.play => OperationType.play,
      TaskType.close => OperationType.close,
      TaskType.recover => OperationType.recover,
      TaskType.fallback => OperationType.fallback,
      _ => OperationType.load,
    };
  }

  bool _abandoned(int generation) {
    return _disposed || !_playbackRequested || generation != _playGeneration;
  }
}

/// A queued action paired with the future of whoever awaited it.
final class _PendingTask {
  _PendingTask(this.action) : completer = Completer<void>();

  final Future<void> Function(TaskCancelToken token) action;
  final Completer<void> completer;
}
