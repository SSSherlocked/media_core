part of 'live_playback_controller.dart';

/// The sweep: engine × source candidates, each opened, staged and
/// verified before it is committed — the recovery story of one play.
extension _LivePlaybackSweep on LivePlaybackController {
  // ---------------------------------------------------------------------------
  // The sweep: engine × source, verified
  // ---------------------------------------------------------------------------

  Future<void> _startPlayback() async {
    final engines = _engineOrder();
    final primary = _sources.isNotEmpty ? _sources.first : null;
    final handle = _handle;

    // A duplicate play of exactly the playback already running - a
    // double-tap, or the app re-entering its play flow while the first
    // sweep is still verifying - must not supersede and tear down what it
    // just asked for. Full-URI comparison: refreshed signatures share the
    // path but differ in query, so a legitimate re-play still runs.
    if (handle != null &&
        !handle.disposed &&
        _playbackRequested &&
        primary != null &&
        _currentSource?.uri == primary.uri &&
        (engines.isEmpty || handle.backendId == engines.first)) {
      return;
    }

    _engines = engines;
    _reportMemory();
    _engineIndex = 0;
    _sourceIndex = 0;

    await _sweep();
  }

  /// Whether the newer command that superseded the current play generation
  /// is a play of exactly [source] on [engine] - in which case committing the
  /// staged player is correct, and discarding it would only fail the sweep and
  /// burn the request's single-use URLs on a replay.
  bool _supersededBySamePlayback(String engine, PlayerSource source) {
    return _playbackRequested &&
        _request != null &&
        _sourceIndex < _sources.length &&
        _engineIndex < _engines.length &&
        _sources[_sourceIndex].uri == source.uri &&
        _engines[_engineIndex] == engine;
  }

  Future<void> _openCurrentSource() async {
    if (_engines.isEmpty || _engineIndex >= _engines.length) {
      _engines = _engineOrder();
      _engineIndex = 0;
    }

    await _sweep(startAtCurrent: true);
  }

  /// Tries candidates in order until one verifies, then reports failure.
  ///
  /// The whole sweep runs inside one queued task, so the only things that
  /// can interrupt it are a user action taking the queue or the task being
  /// cancelled — never another recovery path.
  Future<void> _sweep({bool startAtCurrent = false}) async {
    final generation = _playGeneration;
    var first = true;

    while (!_disposed && _playbackRequested && generation == _playGeneration) {
      final source = _sources[_sourceIndex];
      final engine = _engines[_engineIndex];

      try {
        await _openOn(engine, source);

        return;
      } on Object catch (error) {
        MediaCoreLog.warning(
          LogCategory.recovery,
          'candidate failed: ${source.uri} on $engine'
          '${first && startAtCurrent ? ' (reopen of the playing line)' : ''}',
          error: error,
          fields: <String, Object?>{'sourceIndex': _sourceIndex, 'engineIndex': _engineIndex},
        );

        first = false;
      }

      if (!await _nextCandidate()) {
        await _reportExhausted(source, engine);

        return;
      }
    }
  }

  /// Moves to the next candidate: next source, else next engine (when
  /// allowed) restarting its sweep at the line the user was watching.
  ///
  /// Before the engine switch, [onEngineFallbackSources] gets one chance
  /// to hand over fresh lines: signed live URLs are frequently single-use,
  /// and replaying them on the next engine would fail the whole sweep for
  /// an expired signature rather than a broken engine.
  Future<bool> _nextCandidate() async {
    if (_sourceIndex + 1 < _sources.length) {
      _sourceIndex++;

      return true;
    }

    if (!_engineFallbackAllowed || _engineIndex + 1 >= _engines.length) {
      return false;
    }

    final nextEngine = _engines[_engineIndex + 1];

    var nextSources = _sources;
    var resumeAt = _sweepStart;

    final resolver = onEngineFallbackSources;

    if (resolver != null) {
      try {
        final refreshed = await resolver(nextEngine, _sources);

        if (refreshed.isNotEmpty) {
          nextSources = List<PlayerSource>.unmodifiable(refreshed);
          resumeAt = 0;

          MediaCoreLog.info(
            LogCategory.fallback,
            'engine switch sources refreshed by the caller',
            fields: <String, Object?>{'nextEngine': nextEngine, 'lines': nextSources.length},
          );
        }
      } on Object catch (error) {
        MediaCoreLog.warning(
          LogCategory.fallback,
          'engine switch source refresh failed — reusing the current lines',
          error: error,
          fields: <String, Object?>{'nextEngine': nextEngine},
        );
      }
    }

    MediaCoreLog.info(
      LogCategory.fallback,
      'all sources failed on ${_engines[_engineIndex]} — switching to $nextEngine',
      fields: <String, Object?>{
        'from': _engines[_engineIndex],
        'to': nextEngine,
        'resumeAtLine': resumeAt,
        'refreshed': !identical(nextSources, _sources),
      },
    );

    _sources = nextSources;
    _sweepStart = resumeAt;
    _engineIndex++;
    _sourceIndex = resumeAt;

    return true;
  }

  /// Offers [onRecoverySources] the lines that just died and adopts what it
  /// hands back.
  ///
  /// A signed live URL expires on the platform's clock, not the player's, so
  /// re-opening the line that stalled retries an address the server has
  /// already rejected — the sweep then burns every candidate and every engine
  /// on one stale signature and reports the stream as dead. The refresh is a
  /// round-trip to the platform, which makes it the recovery's only await
  /// that a newer command can overtake: the answer is fenced on the play
  /// generation, and a caller that throws or has nothing fresher leaves the
  /// sweep on the lines it already holds.
  Future<void> _refreshSourcesForRecovery() async {
    final resolver = onRecoverySources;

    if (resolver == null || _sources.isEmpty) {
      return;
    }

    final generation = _playGeneration;

    try {
      final refreshed = await resolver(_sources);

      // play, switchLine, retry, pause, close and dispose all bump the
      // generation before they queue their own task; a refresh that lands
      // after one of them belongs to a playback that no longer exists, and
      // adopting it would swap the lines out from under the newer command.
      if (generation != _playGeneration || refreshed.isEmpty) {
        return;
      }

      _sources = List<PlayerSource>.unmodifiable(refreshed);
      // The refreshed list arrives in preference order, so the line to try
      // first is index 0 — and the engine-switch resume point follows it,
      // having been the line the user was watching before the refresh.
      _sourceIndex = 0;
      _sweepStart = 0;

      _reportMemory();

      MediaCoreLog.info(
        LogCategory.recovery,
        'recovery sources refreshed by the caller',
        fields: <String, Object?>{'lines': _sources.length, 'first': _sources.first.uri.toString()},
      );
    } on Object catch (error) {
      MediaCoreLog.warning(
        LogCategory.recovery,
        'recovery source refresh failed — reusing the current lines',
        error: error,
        fields: <String, Object?>{'lines': _sources.length},
      );
    }
  }

  /// Opens [source] on [engine], starts playback and verifies it.
  ///
  /// Line switches inside one engine re-open the existing handle. An
  /// engine switch is **staged**: the replacement player is created,
  /// opened and verified *alongside* the current one, and only a verified
  /// player is committed. Committing after verification is what keeps the
  /// engine-switch black flash short - the mounted surface is replaced at
  /// the moment the new engine already has a decoded frame, instead of
  /// showing a placeholder for the engine's whole time-to-first-frame.
  Future<void> _openOn(String engine, PlayerSource source) async {
    final generation = _playGeneration;

    final current = _handle;
    final sameEngine = current != null && !current.disposed && current.backendId == engine;

    if (!sameEngine) {
      await _openOnStaged(engine, source, generation: generation, previous: current);
      return;
    }

    final handle = current;

    _setState(_liveState(PlayerPlaybackState.opening));

    // Recovery is this module's job; the handle's own ladder stays
    // dormant so there is exactly one recovery path.
    handle
      ..recoveryEnabled = false
      ..playIntent = true;

    // Every watchdog armed for a previous candidate is stale now: cancel
    // them, and clear the position observation so the new source starts
    // unobserved. The first position sample of the *new* source is then
    // what enables and arms the stall detector - exactly once.
    watchdogs
      ..cancelAll()
      ..resetPositionSignal();

    _sweepAdapterError = null;

    await handle.open(source);

    if (_abandoned(generation)) {
      return;
    }

    await handle.play();

    // The step that separates "opened" from "playing": without it an
    // engine that accepts a source but never delivers a frame reads as
    // success and the sweep stops on a frozen player.
    await _verifyPlayback(handle, source);

    if (_abandoned(generation)) {
      return;
    }

    _currentSource = source;

    watchdogs.armSourceReady();

    _setState(_liveState(PlayerPlaybackState.buffering));
  }

  /// Builds the replacement player for [engine], proves it plays, then
  /// commits it. Any failure disposes the staged player and rethrows - the
  /// sweep moves on, and nothing already on screen is torn down for a
  /// lost race.
  Future<void> _openOnStaged(
    String engine,
    PlayerSource source, {
    required int generation,
    required PlayerHandle? previous,
  }) async {
    MediaCoreLog.info(
      LogCategory.fallback,
      'attaching engine $engine for ${source.uri}',
      fields: <String, Object?>{'line': _sourceIndex, 'staged': previous != null},
    );

    _setState(_liveState(PlayerPlaybackState.opening));

    watchdogs.cancelAll();

    _sweepAdapterError = null;

    // The engine being replaced keeps playing while this attempt runs, and
    // its subscription is otherwise only swapped at commit - so for the
    // whole verification window it kept feeding observations (position,
    // playing, buffering) to a watchdog set that had just been cancelled
    // for this attempt. That is what produced a second "armed" line per
    // engine switch, armed from the retiring source's samples. Detach it
    // for the attempt; a failed attempt restores the subscription so the
    // still-running playback keeps its coverage.
    final retireeSub = previous == null ? null : _adapterSub;

    if (retireeSub != null) {
      _adapterSub = null;

      await retireeSub.cancel();
    }

    final staged = await kernel.create(preferredBackend: engine);

    // A staged attempt owns no subscription until it commits, so an engine
    // that fails *while opening* — a playlist that 404s, a refused connection
    // — told the sweep nothing at all: verification sat out its whole window
    // and then reported "position frozen", blaming the stream for what the
    // engine had already stated. Observe errors only; playback state and the
    // watchdogs stay unattached until commit, exactly as before.
    final stagedErrors = staged.adapterEvents.listen((event) {
      if (event case PlayerAdapterErrorEvent(:final message)) {
        _sweepAdapterError ??= message;
      }
    }, onError: (Object _) {});

    try {
      staged
        ..recoveryEnabled = false
        ..playIntent = true;

      if (_audioOnly) {
        await staged.setAudioOnly(audioOnly: true);
      }

      await staged.open(source);

      if (_abandoned(generation) && !_supersededBySamePlayback(engine, source)) {
        throw StateError('Staged engine $engine was abandoned mid-open.');
      }

      await staged.play();
      await _verifyPlayback(staged, source);

      if (_abandoned(generation) && !_supersededBySamePlayback(engine, source)) {
        throw StateError('Staged engine $engine was abandoned mid-verify.');
      }

      // Commit: the replacement has proven itself. Surface consumers see
      // the new handle through onHandleChanged and rebind at this moment,
      // when the first frame is already decoded.
      //
      // The per-source position observation is cleared first: the retiring
      // engine has been feeding the watchdogs throughout verification (its
      // subscription is only replaced by _attach), so its samples would
      // otherwise arm the stall detector for a source that is going away -
      // one arm per engine switch too many in the log.
      watchdogs.resetPositionSignal();

      _attach(staged);

      // After the commit, not before: cancelling first would open a gap in
      // which an error event reaches neither listener.
      await stagedErrors.cancel();

      if (previous != null && !previous.disposed) {
        try {
          await kernel.release(previous.id);
        } on Object catch (_) {
          // Best-effort release of the retired engine.
        }
      }
    } on Object catch (_) {
      await stagedErrors.cancel();

      try {
        await kernel.release(staged.id);
      } on Object catch (_) {
        // Best-effort cleanup of the failed staging.
      }

      // The retired engine is still the active one after a failed attempt:
      // give its adapter events back, or a stream that keeps playing would
      // run without stall detection until the next candidate commits. The
      // watchdog capabilities and playing state are re-seeded with it -
      // the attempt cancelled them, and the retiring handle's Playing event
      // is long past, so without this the position stall could never re-arm
      // for a stream that is in fact still running.
      if (previous != null && !previous.disposed && identical(_handle, previous) && _adapterSub == null) {
        _adapterSub = previous.adapterEvents.listen(_onAdapterEvent, onError: (Object _) {});

        watchdogs.updateCapabilities(previous.adapter.capabilities);
        watchdogs.setVideoExpected(expected: !_audioOnly);
        watchdogs.onPlayingChanged(playing: _playbackRequested, fromUserIntent: false);
      }

      rethrow;
    }

    if (_abandoned(generation)) {
      return;
    }

    _currentSource = source;

    watchdogs.armSourceReady();

    _setState(_liveState(PlayerPlaybackState.buffering));
  }

  /// Waits until [handle] shows any sign of real playback.
  ///
  /// An engine that accepts a source but never delivers a frame — the
  /// "freeze that looks like success" — fails here instead of ending the
  /// sweep on a silent player.
  ///
  /// The success bar is *any* positive position progress, not a jump:
  /// some live sources (huya FLV, for one) start their demuxer clock near
  /// zero and only creep forward a few tens of milliseconds while the
  /// picture is in fact playing. Requiring a 400ms jump used to condemn
  /// exactly those healthy streams, and the sweep then tore down engine
  /// after engine that was already on screen. A stream that moves at all
  /// has passed verification; if it later stops moving, the position-stall
  /// watchdog is the detector for that, not this gate.
  ///
  /// The deadline is [LiveWatchdogs.sourceReadyTimeout] — the tolerance
  /// this module already declares for "opened but not playing", of which
  /// this is the first phase. It used to be a private, tighter constant,
  /// which meant one question with two deadlines and the stricter one
  /// winning: engines that were demonstrably still working (fetching the
  /// renditions of a multi-variant HLS master) were reported as frozen.
  /// Silence at this point is not evidence of death, because there is no
  /// signal that says "still probing" — no position and no buffering
  /// report exist until the demuxer has finished opening.
  Future<void> _verifyPlayback(PlayerHandle handle, PlayerSource source) async {
    final window = watchdogs.sourceReadyTimeout;

    // Zero turns the deadline off, and verification *is* that deadline.
    if (window <= Duration.zero) {
      return;
    }

    final until = DateTime.now().add(window);
    var last = handle.playbackStream.value.position;

    while (DateTime.now().isBefore(until)) {
      if (_disposed || !_playbackRequested) {
        throw StateError('Playback verification abandoned: playback was stopped.');
      }

      final adapterError = _sweepAdapterError;

      if (adapterError != null) {
        throw StateError('${source.uri} on ${handle.backendId} failed while verifying: $adapterError');
      }

      final position = handle.playbackStream.value.position;

      // A reopen restarts the demuxer clock: the mirror still holds the
      // previous playback's position (18s of the old session, say), and
      // the fresh stream starts near zero. Without re-baselining, every
      // new sample is "smaller than last" and a perfectly healthy reopen
      // is condemned as frozen at the stale value.
      if (position < last) {
        last = position;
        continue;
      }

      if (position > last) {
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    throw StateError(
      '${source.uri} on ${handle.backendId} opened but never played '
      '(position frozen at ${last.inMilliseconds}ms for '
      '${window.inSeconds}s).',
    );
  }

  /// Terminal: every allowed candidate failed. Exactly one failure per
  /// sweep — the caller decides what happens next.
  Future<void> _reportExhausted(PlayerSource source, String engine) async {
    MediaCoreLog.error(
      LogCategory.recovery,
      'live sweep exhausted — reporting to the caller',
      fields: <String, Object?>{
        'sources': _sources.length,
        'enginesTried': _engineFallbackAllowed ? _engineIndex + 1 : 1,
        'lastEngine': engine,
        'lastLine': source.uri.toString(),
      },
    );

    _setState(_liveState(PlayerPlaybackState.error));

    if (!_failureController.isClosed) {
      _failureController.add(
        PlayerFailure(
          code: PlayerErrorCode.noPlayableStream,
          message:
              'Live playback failed after trying ${_sources.length} source(s)'
              '${_engineFallbackAllowed ? ' across ${_engineIndex + 1} engine(s)' : ''}. '
              'Last attempt: ${source.uri} on $engine.',
        ),
      );
    }
  }
}
