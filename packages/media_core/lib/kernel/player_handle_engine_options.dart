part of 'player_handle.dart';

/// Runtime engine configuration.
///
/// Everything here speaks the engine's own vocabulary: keys are mpv
/// property names on media_kit, mdk property names on fvp, ijkplayer
/// option names on ijk. The framework never invents values — it only
/// transports what the caller declared to the live engine, and rebuilds
/// the engine when a value cannot take effect on a running instance.
extension PlayerHandleEngineOptions on PlayerHandle {
  /// Applies [options] to the engine behind this handle.
  ///
  /// Options are remembered by the handle and replayed whenever the
  /// engine instance is replaced — a recovery backend swap,
  /// [rebuildEngine], or an internal rebuild triggered by this call — so
  /// a configuration survives everything the framework does to the
  /// player afterwards.
  ///
  /// With [effect] set to [EngineOptionEffect.immediate] (the default),
  /// an option the current engine instance cannot take live is applied
  /// by rebuilding the engine on the same backend, preserving the open
  /// source, position, volume, rate and play intent. With
  /// [EngineOptionEffect.nextOpen] nothing is ever rebuilt: options that
  /// cannot apply live simply wait for the next open or engine creation.
  Future<EngineOptionReport> applyEngineOptions(
    List<EngineOption> options, {
    EngineOptionEffect effect = EngineOptionEffect.immediate,
  }) {
    _ensureNotDisposed();

    for (final option in options) {
      _engineOptions[(option.domain ?? '', option.key)] = option;
    }

    // The rebuild is queued as its own operation, deliberately outside the
    // task that talks to the current engine: [_recreateBackend] enqueues
    // itself, and nesting it inside this task would deadlock the queue
    // against itself.
    return _record(OperationType.applyEngineOptions, () async {
      final classified = await _enqueue(() async {
        if (_disposed) {
          return null;
        }

        final outcomes = await _runtime.adapter.applyEngineOptions(options);

        final appliedLive = <EngineOption>[];
        final stagedForNextOpen = <EngineOption>[];
        final rebuiltFor = <EngineOption>[];
        final unsupported = <EngineOption>[];

        for (var i = 0; i < options.length; i++) {
          switch (outcomes[i]) {
            case EngineOptionOutcome.appliedLive:
              appliedLive.add(options[i]);

            case EngineOptionOutcome.stagedForNextOpen:
              stagedForNextOpen.add(options[i]);

            case EngineOptionOutcome.needsRebuild:
              if (effect == EngineOptionEffect.immediate) {
                rebuiltFor.add(options[i]);
              } else {
                stagedForNextOpen.add(options[i]);
              }

            case EngineOptionOutcome.unsupported:
              unsupported.add(options[i]);
          }
        }

        return (
          appliedLive: appliedLive,
          stagedForNextOpen: stagedForNextOpen,
          rebuiltFor: rebuiltFor,
          unsupported: unsupported,
        );
      });

      if (classified == null) {
        return EngineOptionReport(unsupported: List<EngineOption>.of(options));
      }

      if (classified.rebuiltFor.isNotEmpty) {
        await _recreateBackend(reason: 'engine options cannot apply live (${classified.rebuiltFor.length} option(s))');
      }

      return EngineOptionReport(
        appliedLive: classified.appliedLive,
        stagedForNextOpen: classified.stagedForNextOpen,
        rebuiltFor: classified.rebuiltFor,
        unsupported: classified.unsupported,
      );
    }());
  }

  /// Replaces the engine instance behind this handle with a fresh one
  /// from the same backend registration.
  ///
  /// The open source, position, volume, rate and play intent are
  /// restored, and every option applied through [applyEngineOptions] is
  /// replayed on the new instance before it opens. Consumers that hold
  /// per-adapter state re-read it from [PlayerHandle.adapter] after the
  /// [PlayerHandle.backendChanges] event, exactly as after a recovery
  /// backend swap.
  Future<void> rebuildEngine({String reason = 'requested by caller'}) {
    _ensureNotDisposed();

    return _record(OperationType.applyEngineOptions, _recreateBackend(reason: reason));
  }

  /// Replays the persisted engine options on [adapter].
  ///
  /// Best effort: an engine that rejects an option during a rebuild must
  /// not fail the rebuild itself.
  Future<void> _replayEngineOptions(PlayerAdapter adapter) async {
    final options = _engineOptions.values.toList(growable: false);

    if (options.isEmpty) {
      return;
    }

    try {
      await adapter.applyEngineOptions(options);
    } on Object catch (error) {
      MediaCoreLog.warning(LogCategory.player, 'engine options could not be replayed on ${adapter.id}: $error');
    }
  }

  /// Same-backend counterpart of the recovery swap: builds a fresh
  /// adapter from the current registration, prepares it out of sight and
  /// installs it only once it holds the same playback again.
  Future<void> _recreateBackend({required String reason}) {
    final operationGeneration = _invalidateOperations();
    final source = _currentSource;
    final registration = _registration;
    final backendId = registration.id;

    final current = _runtime.playback.current;
    final session = RecoverySession(
      failure: RecoveryFailure.fromMessage(reason),
      source: source,
      position: current.position,
      // The caller's intent wins over the adapter mirror; see the play
      // intent field for why a buffering session still counts as playing.
      wasPlaying:
          playIntent ??
          _runtime.session.state.status == SessionStatus.playing ||
              _runtime.session.state.status == SessionStatus.buffering,
      volume: current.volume,
      rate: current.rate,
      backendId: backendId,
      generationId: _runtime.session.generation.id,
    );

    return _enqueue(() async {
      if (!_isOperationCurrent(operationGeneration) || _disposed) {
        throw StateError('Engine rebuild on $backendId was superseded.');
      }

      MediaCoreLog.info(
        LogCategory.player,
        'rebuilding engine $backendId: $reason',
        fields: <String, Object?>{
          'source': source?.uri.toString(),
          'wasPlaying': session.wasPlaying,
          'positionMs': session.position.inMilliseconds,
        },
      );

      final nextAdapter = registration.factory.create(registration.id);

      var committed = false;

      try {
        await nextAdapter.initialize(_adapterContext);

        if (!_isOperationCurrent(operationGeneration) || _disposed) {
          throw StateError('Engine rebuild on $backendId was superseded.');
        }

        // The caller's persisted engine options are applied before the
        // source opens, so the fresh engine is born configured.
        await _replayEngineOptions(nextAdapter);

        if (source != null) {
          await nextAdapter.open(source);
          await _prepareStagedAdapter(nextAdapter, session, source);
        }

        if (!_isOperationCurrent(operationGeneration) || _disposed) {
          throw StateError('Engine rebuild on $backendId was superseded.');
        }

        await _installAdapter(nextAdapter, registration);

        committed = true;

        if (source != null) {
          await _runtime.sessionController.open();

          if (!_isOperationCurrent(operationGeneration) || _disposed) {
            throw StateError('Engine rebuild on $backendId was superseded.');
          }

          _currentSource = source;
          _backendReady = true;

          await _applyAudioOnly(nextAdapter);
        } else {
          _backendReady = false;
        }

        _publish(PlayerEventType.player, <String, Object?>{
          'action': 'engineRebuilt',
          'backend': backendId,
          'reason': reason,
        });
      } on Object catch (error, stackTrace) {
        if (!committed) {
          // The previous engine is still attached and still owns its
          // subscription: there is nothing to roll back.
          try {
            await nextAdapter.dispose();
          } on Object catch (_) {
            // Best-effort cleanup of the failed replacement.
          }
        }

        MediaCoreLog.error(
          LogCategory.player,
          'engine rebuild on $backendId failed: $error',
          error: error,
          stackTrace: stackTrace,
        );

        rethrow;
      }
    });
  }
}
