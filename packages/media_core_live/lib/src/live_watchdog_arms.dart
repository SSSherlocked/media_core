part of 'live_watchdogs.dart';

/// The four watchdog arms, each a timer that fires when its signal
/// stops: continuity (unexpected pause), buffering stall, video frame
/// stall and position stall.
///
/// Arming only; the cancels, the observations that drive them and the
/// public entry points live in the main class body.
extension _LiveWatchdogArms on LiveWatchdogs {
  // ---------------------------------------------------------------------------
  // Continuity watchdog
  // ---------------------------------------------------------------------------

  void _armContinuity() {
    _cancelContinuity();

    if (!_canWatch || unexpectedPauseGrace <= Duration.zero || _recoveryPending) {
      return;
    }

    final generation = _watchdogGeneration;

    _continuitySubscription = TimerStream<void>(null, unexpectedPauseGrace).listen((_) {
      if (!_isWatchdogGenerationCurrent(generation)) {
        return;
      }

      if (_playing || _buffering) {
        return;
      }

      _requestReassertPlay(generation);
    });
  }

  /// Requests a playback reassertion from the owner.
  ///
  /// This method intentionally contains no `Future` and no player call.
  ///
  /// The old implementation did:
  ///
  /// ```dart
  /// final resumed = await onReassertPlay();
  /// ```
  ///
  /// That allowed a `play()` Future to remain alive while the player
  /// was being closed or replaced. The watchdog now only emits a
  /// recovery action and lets [PlayerHandle] own the lifecycle.
  void _requestReassertPlay(int generation) {
    if (!_isWatchdogGenerationCurrent(generation) || _recoveryPending || !_canWatch || _playing || _buffering) {
      return;
    }

    _recoveryPending = true;
    _recoveryGeneration = generation;

    _cancelContinuity();

    final handler = onRecoveryRequested;

    if (handler == null) {
      _recoveryPending = false;
      _recoveryGeneration = null;

      if (!_isWatchdogGenerationCurrent(generation)) {
        return;
      }

      onStall?.call(LiveStallKind.unexpectedPauseResumeFailed);

      return;
    }

    try {
      handler(LiveWatchdogRecoveryAction.reassertPlay);
    } on Object catch (_) {
      if (!_isWatchdogGenerationCurrent(generation)) {
        return;
      }

      _recoveryPending = false;
      _recoveryGeneration = null;

      onStall?.call(LiveStallKind.unexpectedPauseResumeFailed);
    }
  }

  // ---------------------------------------------------------------------------
  // Buffering watchdog
  // ---------------------------------------------------------------------------

  void _armBufferingStall() {
    _cancelBufferingStall();

    if (!_canWatch || bufferingStallTimeout <= Duration.zero || !_buffering) {
      return;
    }

    final generation = _watchdogGeneration;

    _bufferingSubscription = TimerStream<void>(null, bufferingStallTimeout).listen((_) {
      if (!_isWatchdogGenerationCurrent(generation)) {
        return;
      }

      if (_buffering) {
        onStall?.call(LiveStallKind.bufferingStallTimeout);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Video frame watchdog
  // ---------------------------------------------------------------------------

  /// Arms the decoded-frame stall deadline.
  ///
  /// All preconditions are checked here so callers do not need to
  /// remember them:
  ///
  /// - the adapter must declare
  ///   [PlayerAdapterCapabilities.supportsVideoFrameProgress]
  /// - the watchdog must be enabled and the timeout non-zero
  /// - video frames must be expected for the session
  ///   ([setVideoExpected]; false for audio-only playback)
  /// - the mounted presentation must be visible
  /// - playback must be running
  /// - buffering must not be in progress (no frames are expected while
  ///   the engine is filling its cache, so a missing heartbeat is not
  ///   a stall)
  void _armVideoFrameStall() {
    _cancelVideoFrameStall();

    final skipReason = _frameStallSkipReason();

    if (skipReason != null) {
      // "Why is the frame watchdog not watching?" is the first question
      // both when a frozen stream goes unnoticed and when recovery keeps
      // reopening a stream that was never stalled. Logging the decision
      // inputs answers it without a debugger — once per decision, not once
      // per re-arm.
      if (skipReason != _loggedFrameStallSkip) {
        _loggedFrameStallSkip = skipReason;

        MediaCoreLog.debug(
          LogCategory.recovery,
          'frame-stall watchdog not armed: $skipReason',
          fields: <String, Object?>{
            'declaresFrameProgress': _capabilities?.supportsVideoFrameProgress,
            'videoExpected': _videoExpected,
            'presentationVisible': _presentationVisible,
            'playing': _playing,
            'buffering': _buffering,
            'timeoutMs': videoFrameStallTimeout.inMilliseconds,
          },
        );
      }

      return;
    }

    _loggedFrameStallSkip = null;

    MediaCoreLog.debug(
      LogCategory.recovery,
      'frame-stall watchdog armed (${videoFrameStallTimeout.inMilliseconds}ms)',
      fields: <String, Object?>{'videoExpected': _videoExpected},
    );

    final generation = _watchdogGeneration;

    _videoFrameSubscription = _frameProgress
        .startWith(null)
        .switchMap<void>((_) => TimerStream<void>(null, videoFrameStallTimeout))
        .listen((_) {
          if (!_isWatchdogGenerationCurrent(generation)) {
            return;
          }

          if (!_presentationVisible || !_playing || !_videoExpected || !_supportsVideoFrameProgress || _buffering) {
            return;
          }

          _cancelVideoFrameStall();

          onStall?.call(LiveStallKind.videoFrameStallTimeout);
        });
  }

  /// Arms the position-stall watchdog.
  ///
  /// Mirrors [_armVideoFrameStall], with one difference in the gating: it
  /// does not consult a capability and does not care whether video is
  /// expected or the presentation is visible. A stream whose position
  /// stops advancing is stuck for an audio-only session and for a
  /// background session too.
  void _armPositionStall({String via = 'unknown'}) {
    _cancelPositionStall();

    final skipReason = _positionStallSkipReason();

    if (skipReason != null) {
      if (skipReason != _loggedPositionStallSkip) {
        _loggedPositionStallSkip = skipReason;

        MediaCoreLog.debug(
          LogCategory.recovery,
          'position-stall watchdog not armed: $skipReason',
          fields: <String, Object?>{
            'hasPositionSignal': _hasPositionSignal,
            'playing': _playing,
            'buffering': _buffering,
            'timeoutMs': positionStallTimeout.inMilliseconds,
          },
        );
      }

      return;
    }

    _loggedPositionStallSkip = null;

    MediaCoreLog.debug(
      LogCategory.recovery,
      'position-stall watchdog armed (${positionStallTimeout.inMilliseconds}ms)',
      // Which observation armed it: a position sample, a playing state that
      // followed one, or the end of buffering. Without this the log shows
      // identical "armed" lines and the sequence that produced them is
      // guesswork.
      fields: <String, Object?>{'via': via, 'positionMs': _lastPositionMs},
    );

    final generation = _watchdogGeneration;

    _positionStallSubscription = _positionProgress
        .startWith(null)
        .switchMap<void>((_) => TimerStream<void>(null, positionStallTimeout))
        .listen((_) {
          if (!_isWatchdogGenerationCurrent(generation)) {
            return;
          }

          if (_positionStallSkipReason() != null) {
            return;
          }

          _cancelPositionStall();

          onStall?.call(LiveStallKind.positionStallTimeout);
        });
  }

  /// Why the position-stall watchdog must not arm, or `null` when it may.
  String? _positionStallSkipReason() {
    if (!_canWatch) return 'watchdogs disabled';
    if (!_hasPositionSignal) return 'engine has not reported position yet';
    if (positionStallTimeout <= Duration.zero) return 'timeout disabled';
    if (!_playing) return 'playback not running';
    if (_buffering) return 'buffering in progress';

    return null;
  }

  /// Why the frame-stall watchdog must not arm, or `null` when it may.
  ///
  /// Returned as text rather than a bool so the reason reaches the log
  /// verbatim: the interesting case is not "it did not arm" but *which*
  /// condition stopped it.
  String? _frameStallSkipReason() {
    if (!_canWatch) return 'watchdogs disabled';
    if (!_supportsVideoFrameProgress) {
      return 'adapter does not declare frame progress';
    }
    if (!_videoExpected) return 'no video frames expected (audio-only)';
    if (videoFrameStallTimeout <= Duration.zero) return 'timeout disabled';
    if (!_presentationVisible) return 'presentation not visible';
    if (!_playing) return 'playback not running';
    if (_buffering) return 'buffering in progress';

    return null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool get _canWatch => enabled && !_disposed;
}
