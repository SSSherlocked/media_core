part of 'player_handle.dart';

/// Recovery-facing surface: the knobs a playback owner sets before
/// reporting failures, [reportFailure] itself, and the physical step
/// implementations behind the [RecoveryTarget] overrides.
///
/// The ladder decides; everything in this extension performs.
///
/// Recovery toggles and the declared play intent are public fields on
/// [PlayerHandle] (`recoveryEnabled`, `engineFallbackEnabled`,
/// `playIntent`), not methods here, because extensions cannot own
/// storage.
extension PlayerHandleRecovery on PlayerHandle {
  /// Declares the alternative sources recovery may fall back to.
  ///
  /// The caller owns this list — for live playback it is the line list of
  /// the current request. Passing an empty list disables the next-line
  /// rung, which is the correct behaviour for a single-URL source.
  void setSourceCandidates(List<PlayerSource> candidates) {
    _sourceCandidates = List<PlayerSource>.unmodifiable(candidates);
  }

  /// Restricts playback to the audio track on whichever adapter is
  /// attached.
  ///
  /// Remembered by the handle, not by the caller: the ladder can attach
  /// another adapter without the caller being involved, and a fresh
  /// engine must not silently restore video. Applied again by [open] and
  /// after every backend swap.
  Future<void> setAudioOnly({required bool audioOnly}) {
    _ensureNotDisposed();

    _audioOnly = audioOnly;

    return _applyAudioOnly(_runtime.adapter);
  }

  /// Reports a failure for recovery.
  ///
  /// This is the only entry point into recovery. Returns `true` when the
  /// ladder accepted the report — a run started, or it was already
  /// escalating and the report was folded into it. Returns `false` when
  /// the ladder refused it (already running, suspended, or out of
  /// budget), which is not an error: a second recovery for a failure
  /// that is already being recovered is exactly the duplicate work this
  /// design removes.
  bool reportFailure(RecoveryFailure failure, {RecoveryFailureSource source = RecoveryFailureSource.unknown}) {
    _ensureNotDisposed();

    if (!recoveryEnabled) {
      return false;
    }

    final report = failure
        .copyWith(source: failure.source == RecoveryFailureSource.unknown ? source : failure.source)
        .enriched(
          sourceId: _currentSource?.id,
          backendId: _registration.id,
          generationId: _runtime.session.generation.id,
          uri: _currentSource?.uri.toString(),
        );

    final accepted = _ladder.report(report);

    MediaCoreLog.log(
      accepted ? LogLevel.info : LogLevel.debug,
      LogCategory.recovery,
      'failure reported by ${report.source.name}: ${report.code.value} '
      '(${report.effectiveReason})${accepted ? ' -> recovery started' : ' -> no recovery (see preceding reason)'}',
      fields: <String, Object?>{
        'message': report.message,
        'backend': report.backendId,
        'uri': report.uri,
        'stableKey': report.stableKey,
        'accepted': accepted,
      },
    );

    _publish(PlayerEventType.recovery, <String, Object?>{
      'action': accepted ? 'reported' : 'ignored',
      'code': report.code.value,
      'reason': report.effectiveReason.toString(),
      'reporter': report.source.name,
      'stableKey': report.stableKey,
    });

    return accepted;
  }

  /// How long the ladder waits before attempt [attempt] of a sweep.
  ///
  /// The two numbers are the host's `KernelOptions.retryBaseDelay` and
  /// `retryMaxDelay`, which were documented as the recovery backoff and read by
  /// nothing: the sweep ran its rungs back to back, so an engine that had just
  /// refused an open was asked again in the same millisecond, and a dead CDN was
  /// hammered for as long as rungs were left. Attempt 1 stays immediate — the
  /// failure that opened the sweep already cost the viewer the time one retry is
  /// worth.
  Duration _retryDelayForAttempt(int attempt) {
    if (attempt <= 1) {
      return Duration.zero;
    }

    return RetryUtils.backoff(attempt - 1, base: _options.retryBaseDelay, max: _options.retryMaxDelay);
  }

  // ---------------------------------------------------------------------------
  // Step execution
  // ---------------------------------------------------------------------------

  /// Proves a recovery step actually produced playback.
  ///
  /// "open() returned" is not success. A broken live stream opens cleanly
  /// and then never delivers a frame: no error event, no position events,
  /// nothing. If the ladder took the clean open as success, the run would
  /// end on a stream that never plays — the watchdogs that could catch it
  /// later arm only from the first position event, which never comes, and
  /// the player looks frozen forever with recovery believing it has
  /// already fixed everything.
  ///
  /// So every recovery step that intends to play is verified: within the
  /// grace window the playback position must actually advance. If it does
  /// not, the step throws like any other failure and the ladder escalates.
  /// This one check is what makes the ladder's "all engines failed" verdict
  /// trustworthy.
  Future<void> _verifyPlayback(RecoveryStep step, RecoverySession session, {required int operationGeneration}) async {
    if (!session.wasPlaying) {
      // The caller wants the stream paused; there is no progress to
      // expect, and a clean open is the whole contract.
      return;
    }

    const grace = Duration(seconds: 8);
    var last = _runtime.playback.current.position;
    final until = DateTime.now().add(grace);

    while (DateTime.now().isBefore(until)) {
      if (_disposed) {
        throw StateError('Recovery step ${step.label} was interrupted by disposal.');
      }

      // A caller-issued open()/close() invalidates this step. Without this
      // check the loop would keep polling - and then report success or
      // failure - for a source that no longer exists, which is exactly the
      // stale-commit the lifecycle generation exists to prevent.
      if (!_isOperationCurrent(operationGeneration)) {
        throw StateError('Recovery step ${step.label} was superseded while verifying playback.');
      }

      final current = _runtime.playback.current;

      // A reopen restarts the demuxer clock: re-baseline when the mirror
      // holds a position from the previous session, or a healthy reopen
      // reads as frozen at the stale value.
      if (current.position < last) {
        last = current.position;
        continue;
      }

      // Any positive progress counts. Some live streams start their
      // demuxer clock near zero and creep forward by tens of
      // milliseconds while the picture is already on screen; demanding
      // a large jump used to condemn those healthy streams. A stream
      // that stops moving *later* is the position-stall watchdog's job.
      if (current.position > last) {
        MediaCoreLog.debug(
          LogCategory.recovery,
          'recovery step verified: position advancing (${current.position.inMilliseconds}ms)',
          fields: <String, Object?>{'step': step.label, 'backend': _registration.id},
        );

        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    throw StateError(
      'Recovery step ${step.label} opened ${session.source?.uri} on ${_registration.id} '
      'but playback did not progress within ${grace.inSeconds}s.',
    );
  }

  /// Reopens a source on the currently attached backend.
  ///
  /// Serves both [RecoveryStepKind.sameBackendReopen] and
  /// [RecoveryStepKind.nextLine]: the only difference is which source is
  /// opened. A different source advances the session generation, because
  /// a generation identifies one source lifecycle.
  Future<void> _reopenOnCurrentBackend(RecoveryStep step, PlayerSource source, RecoverySession session) {
    final operationGeneration = _invalidateOperations();
    final changedSource = _currentSource?.id != source.id;

    // `_currentSource` is set here, before the queued step runs, because every
    // operation staleness check reads it. The *announcement* and the session
    // context, however, wait for the step to actually open the source: a step
    // that is superseded or fails must not tell sourceChanges consumers that a
    // source they never saw went live.
    _currentSource = source;
    _backendReady = false;

    return _enqueue(() async {
      if (!_isOperationCurrent(operationGeneration) || _disposed) {
        throw StateError('Recovery reopen of ${source.uri} was superseded.');
      }

      if (changedSource) {
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
      }

      _emitTargetEvent(RecoveryTargetEventKind.stepStarted, step, sourceId: source.id);

      MediaCoreLog.info(
        LogCategory.recovery,
        'reopen on ${_registration.id}: ${source.uri}'
        '${changedSource ? ' (new source)' : ' (same source)'}',
        fields: <String, Object?>{
          'step': step.label,
          'wasPlaying': session.wasPlaying,
          'positionMs': session.position.inMilliseconds,
        },
      );

      try {
        // A reopen starts from a clean backend: closing first is what
        // makes this a recovery rather than a second open on a backend
        // that is still holding the broken stream.
        try {
          await _runtime.adapter.close();
        } on Object catch (_) {
          // Releasing an already released backend is not a reason to abort.
        }

        _backendReady = false;

        if (!_isOperationCurrent(operationGeneration) || _disposed) {
          throw StateError('Recovery reopen of ${source.uri} was superseded.');
        }

        await _runtime.sessionController.open();
        await _runtime.adapter.open(source);

        // The open is the longest await in the framework. Re-check before
        // committing: a caller-issued open()/close() during it supersedes this
        // step, and committing `_backendReady` then would hand playback
        // commands to an adapter that no longer owns the current source.
        if (!_isOperationCurrent(operationGeneration) || _disposed) {
          throw StateError('Recovery reopen of ${source.uri} was superseded.');
        }

        _backendReady = true;

        if (changedSource) {
          _announceSource(source);
        }

        await _restoreSession(session, source: source);
        await _applyAudioOnly(_runtime.adapter);

        // Not done until playback is real: see [_verifyPlayback].
        await _verifyPlayback(step, session, operationGeneration: operationGeneration);

        _emitTargetEvent(RecoveryTargetEventKind.stepSucceeded, step, sourceId: source.id, position: session.position);

        _publish(PlayerEventType.recovery, <String, Object?>{
          'action': 'reopened',
          'step': step.label,
          'uri': source.uri.toString(),
          'backend': _registration.id,
        });
      } catch (error, stackTrace) {
        // Only the operation that still owns the player may clear its ready
        // flag: a superseded step failing late would otherwise disable the
        // source the caller opened in the meantime.
        if (_isOperationCurrent(operationGeneration) && !_disposed) {
          _backendReady = false;
        }

        _emitTargetEvent(
          RecoveryTargetEventKind.stepFailed,
          step,
          sourceId: source.id,
          message: '$error',
          error: error,
          stackTrace: stackTrace,
        );

        rethrow;
      }
    });
  }

  /// Attaches [registration] and opens the session's source on it.
  ///
  /// The previous backend is left untouched until the replacement has
  /// proven itself: it is initialized, opened, positioned and playing
  /// before the runtime is told to swap. A backend that fails to attach
  /// therefore costs one adapter, not the playback.
  Future<void> _swapTo(RecoveryStep step, PlayerAdapterRegistration registration, RecoverySession session) {
    final operationGeneration = _invalidateOperations();
    final source = step.source ?? session.source ?? _currentSource;
    final previousId = _registration.id;

    return _enqueue(() async {
      if (!_isOperationCurrent(operationGeneration) || _disposed) {
        throw StateError('Recovery backend swap to ${registration.id} was superseded.');
      }

      if (registration.id == previousId) {
        throw StateError('Backend ${registration.id} is already attached.');
      }

      _emitTargetEvent(RecoveryTargetEventKind.stepStarted, step, backendId: registration.id, sourceId: source?.id);

      MediaCoreLog.warning(
        LogCategory.fallback,
        'switching backend: $previousId -> ${registration.id}'
        '${source == null ? ' (no source open)' : ' for ${source.uri}'}',
        fields: <String, Object?>{
          'step': step.label,
          'reason': session.failure.code.value,
          'reasonDetail': session.failure.message,
          'reportedBy': session.failure.source.name,
          'wasPlaying': session.wasPlaying,
          'positionMs': session.position.inMilliseconds,
        },
      );

      final nextAdapter = registration.factory.create(registration.id);

      var committed = false;

      try {
        await nextAdapter.initialize(_adapterContext);

        if (!_isOperationCurrent(operationGeneration) || _disposed) {
          throw StateError('Recovery backend swap to ${registration.id} was superseded.');
        }

        // The caller's persisted engine options ride along to every fresh
        // engine, so configuration survives a fallback swap.
        await _replayEngineOptions(nextAdapter);

        if (source != null) {
          await nextAdapter.open(source);
          await _prepareStagedAdapter(nextAdapter, session, source);
        }

        if (!_isOperationCurrent(operationGeneration) || _disposed) {
          throw StateError('Recovery backend swap to ${registration.id} was superseded.');
        }

        // The replacement is fully prepared: hand it to the runtime,
        // which detaches the old bindings, swaps the adapter and rebuilds
        // the bindings against the new backend.
        await _installAdapter(nextAdapter, registration);

        committed = true;

        // The session followed the *old* engine, and after an adapter error it
        // is typically sitting in `error` - a status that cannot be played
        // from. Re-opening the session is what makes the new engine's playback
        // events meaningful, and it mirrors what a reopen does.
        await _runtime.sessionController.open();

        if (!_isOperationCurrent(operationGeneration) || _disposed) {
          throw StateError('Recovery backend swap to ${registration.id} was superseded.');
        }

        _currentSource = source;
        _backendReady = source != null;

        await _applyAudioOnly(nextAdapter);

        // Not done until playback is real: see [_verifyPlayback]. The
        // staged adapter was already told to play; this waits for evidence.
        await _verifyPlayback(step, session, operationGeneration: operationGeneration);

        _emitTargetEvent(
          RecoveryTargetEventKind.stepSucceeded,
          step,
          backendId: registration.id,
          sourceId: source?.id,
          position: session.position,
        );

        _publish(PlayerEventType.fallback, <String, Object?>{
          'action': 'backendAttached',
          'step': step.label,
          'from': previousId,
          'to': registration.id,
        });
      } on Object catch (error, stackTrace) {
        if (!committed) {
          // The previous backend is still attached and still owns its
          // subscription: there is nothing to roll back.
          try {
            await nextAdapter.dispose();
          } on Object catch (_) {
            // Best-effort cleanup of the failed replacement adapter.
          }
        }

        _emitTargetEvent(
          RecoveryTargetEventKind.stepFailed,
          step,
          backendId: registration.id,
          sourceId: source?.id,
          message: '$error',
          error: error,
          stackTrace: stackTrace,
        );

        rethrow;
      }
    });
  }

  /// Sends the session state to a staged adapter before it goes live.
  ///
  /// The position restore is skipped for a live source: the saved
  /// position is a moment in a broadcast that no longer exists, and
  /// seeking a live stream to it either fails or lands the viewer
  /// behind the edge.
  Future<void> _prepareStagedAdapter(PlayerAdapter adapter, RecoverySession session, PlayerSource source) async {
    await _applyAudioOnly(adapter);

    if (session.volume != 1.0) {
      await adapter.setVolume(session.volume);
    }

    if (session.rate != 1.0) {
      await adapter.setRate(session.rate);
    }

    if (session.position > Duration.zero && !source.isLive) {
      await adapter.seek(session.position);
    }

    if (session.wasPlaying) {
      await adapter.play();
    }
  }

  /// Restores the session state on the currently attached adapter.
  ///
  /// The runtime's own bindings mirror adapter events into the playback
  /// and session controllers, but they never re-issue commands: after a
  /// reopen the playback controller still reports whatever the user last
  /// asked for, and it must be told to seek and resume again.
  Future<void> _restoreSession(RecoverySession session, {required PlayerSource? source}) async {
    final adapter = _runtime.adapter;

    if (session.volume != 1.0) {
      await adapter.setVolume(session.volume);
    }

    if (session.rate != 1.0) {
      await adapter.setRate(session.rate);
    }

    // A live source has no position to return to: the saved value is a
    // moment in a broadcast that is already gone, and seeking to it
    // either errors or strands the viewer behind the live edge.
    if (session.position > Duration.zero && source?.isLive != true) {
      await adapter.seek(session.position);

      await _runtime.playback.seek(session.position);
    }

    if (session.wasPlaying) {
      await adapter.play();

      await _runtime.playback.play();
      await _runtime.sessionController.play();
    } else {
      await adapter.pause();

      await _runtime.playback.pause();
      await _runtime.sessionController.pause();
    }
  }

  void _emitTargetEvent(
    RecoveryTargetEventKind kind,
    RecoveryStep step, {
    SourceId? sourceId,
    String? backendId,
    String? message,
    Object? error,
    StackTrace? stackTrace,
    Duration position = Duration.zero,
  }) {
    if (_targetEvents.isClosed) {
      return;
    }

    _targetEvents.add(
      RecoveryTargetEvent(
        kind: kind,
        step: step,
        message: message,
        error: error,
        stackTrace: stackTrace,
        sourceId: sourceId,
        backendId: backendId,
        position: position,
      ),
    );
  }

  /// Projects a ladder decision onto the event bus.
  ///
  /// The ladder stream is recovery's own diagnostic surface; the event
  /// bus is the framework-wide one. Both are fed, because a consumer that
  /// already tracks player events should not have to subscribe twice.
  void _onLadderEvent(RecoveryLadderEvent event) {
    if (_disposed) {
      return;
    }

    switch (event) {
      case RecoveryLadderStarted(failure: final failure, :final plan):
        _publish(PlayerEventType.recovery, <String, Object?>{
          'action': 'started',
          'code': failure?.code.value,
          'reason': failure?.effectiveReason.toString(),
          'reporter': failure?.source.name,
          'plan': plan.map((kind) => kind.name).toList(),
        });

      case RecoveryLadderStepStarted(step: final step, attempt: final attempt):
        _publish(PlayerEventType.recovery, <String, Object?>{
          'action': 'step',
          'step': step?.label,
          'kind': step?.kind.name,
          'attempt': attempt,
        });

      case RecoveryLadderStepFailed(step: final step, failure: final failure, attempt: final attempt):
        _publish(PlayerEventType.recovery, <String, Object?>{
          'action': 'stepFailed',
          'step': step?.label,
          'attempt': attempt,
          'code': failure?.code.value,
          'message': failure?.message,
        });

      case RecoveryLadderCompleted(step: final step, attempt: final attempt):
        _publish(PlayerEventType.recovery, <String, Object?>{
          'action': 'completed',
          'step': step?.label,
          'attempt': attempt,
        });

      case RecoveryLadderExhausted(failure: final failure, attempt: final attempt, message: final message):
        _publish(PlayerEventType.recovery, <String, Object?>{
          'action': 'exhausted',
          'attempts': attempt,
          'reason': message,
        });

        _publishFatal(failure);

      case RecoveryLadderCancelled(attempt: final attempt, message: final message):
        _publish(PlayerEventType.recovery, <String, Object?>{
          'action': 'cancelled',
          'attempt': attempt,
          'reason': message,
        });
    }
  }

  /// Publishes the terminal error of a player whose recovery gave up.
  ///
  /// This used to live in the kernel, which meant the kernel had to know
  /// per-player recovery outcomes. The ladder reports it where it
  /// happens; the kernel only aggregates the event bus.
  void _publishFatal(RecoveryFailure? failure) {
    MediaCoreLog.error(
      LogCategory.recovery,
      'recovery exhausted: playback is terminal'
      '${failure == null ? '' : ' (${failure.code.value}: ${failure.message})'}',
      fields: <String, Object?>{'backend': _registration.id, 'uri': _currentSource?.uri.toString()},
    );

    if (!_options.enableEventBus) {
      return;
    }

    final message = failure?.message ?? 'Playback failed and recovery was exhausted.';

    _eventBus.publish(
      PlayerErrorEvent(
        error: failure?.cause ?? message,
        stackTrace: failure?.stackTrace,
        priority: EventPriority.critical,
        context: _buildContext(),
      ),
    );

    _eventBus.publish(
      GenericPlayerEvent(
        type: PlayerEventType.fallback,
        data: <String, Object?>{'action': 'exhausted', 'code': failure?.code.value, 'backend': _registration.id},
        priority: EventPriority.critical,
        context: _buildContext(),
      ),
    );
  }
}
