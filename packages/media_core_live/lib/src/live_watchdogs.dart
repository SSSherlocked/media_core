import 'dart:async';

import 'package:media_core/media_core.dart';
import 'package:media_core_live/src/live_playback_models.dart';
import 'package:rxdart/rxdart.dart';

/// Recovery action requested by [LiveWatchdogs].
///
// The four watchdog arms — continuity, buffering, video frame and
// position stall — live in `live_watchdog_arms.dart` next to this file.
part 'live_watchdog_arms.dart';

/// The watchdog only reports what kind of recovery should be attempted.
/// It never owns the player and never calls backend operations directly.
///
/// The actual recovery is executed by the playback owner, normally:
///
/// ```text
/// LiveWatchdogs
///      ↓
/// LiveWatchdogRecoveryAction
///      ↓
/// LivePlaybackController
///      ↓
/// PlayerHandle
///      ↓
/// PlayerAdapter
/// ```

/// Watchdog-driven orchestration for live (non-seekable) streams.
///
/// RxDart is used for watchdog scheduling while the actual live playback
/// semantics remain owned by this class.
///
/// A stall is an inference, not a backend report: the watchdog observed
/// a missing expectation rather than an explicit player error.
///
/// The watchdogs are:
///
/// - [LiveStallKind.sourceReadyTimeout]
///   Opened but produced no playing state in time.
///
/// - [LiveStallKind.unexpectedPauseResumed]
///   Reserved for continuity recovery when an unexpected pause recovers.
///
/// - [LiveStallKind.unexpectedPauseResumeFailed]
///   Reasserted playback did not recover.
///
/// - [LiveStallKind.unexpectedPauseTimeout]
///   Playback remained paused after the continuity retry.
///
/// - [LiveStallKind.bufferingStallTimeout]
///   Buffering never ended within the deadline.
///
/// - [LiveStallKind.videoFrameStallTimeout]
///   Playing state remained true but no new video frame arrived.
///
/// - [LiveStallKind.positionStallTimeout]
///   Playing, not buffering, and the position stopped advancing. The
///   detector of last resort: every adapter reports position, so this is
///   the one that works on engines with no frame heartbeat. It only arms
///   after the engine has reported a position at all.
///
/// All watchdogs are source-local. The owner should call [cancelAll] when
/// the current source/generation is retired.
///
/// Capability handling follows the single-source-of-truth rule: this
/// class holds a [PlayerAdapterCapabilities] snapshot and reads the
/// fields it cares about directly. It does not declare its own
/// `supportsXxx` flags, mirror getters, or per-capability setters. The
/// snapshot is bound through [updateCapabilities] and re-bound whenever
/// the active adapter changes (fallback, engine switch, close).
///
/// A capability describes what an adapter *can* produce; a session can
/// still rule a signal out. Audio-only playback is that case:
/// [setVideoExpected] with `false` keeps the frame watchdog disarmed for
/// the whole session, because an audio-only source has no video track and
/// therefore never produces the heartbeat it waits for.
///
/// This class intentionally does not execute player operations.
///
/// In particular, it does not:
///
/// - hold a PlayerHandle
/// - call `play()`
/// - call `pause()`
/// - call adapter methods
/// - await backend operations
/// - own recovery Futures
///
/// When recovery is needed it emits [LiveWatchdogRecoveryAction] through
/// [onRecoveryRequested]. The playback owner is responsible for executing
/// that action through the lifecycle-safe PlayerHandle boundary and then
/// reporting the result through [reportRecoveryResult].
final class LiveWatchdogs {
  LiveWatchdogs({
    PlayerAdapterCapabilities? capabilities,
    this.sourceReadyTimeout = const Duration(seconds: 18),
    this.unexpectedPauseGrace = const Duration(milliseconds: 350),
    this.unexpectedPauseFailureGrace = const Duration(seconds: 5),
    this.bufferingStallTimeout = const Duration(seconds: 12),
    this.videoFrameStallTimeout = const Duration(seconds: 10),
    this.positionStallTimeout = const Duration(seconds: 15),
    this.enabled = true,
  }) : _capabilities = capabilities;

  /// Opened-but-not-playing deadline.
  ///
  /// Zero disables this watchdog.
  ///
  /// This is also how long the sweep's verification gives a candidate to
  /// produce its first position advance — one question, one deadline.
  /// Verification runs *before* this watchdog is armed, so the two never
  /// overlap; they are the same tolerance applied to consecutive phases.
  ///
  /// It is deliberately generous. A live source can legitimately take this
  /// long to show a position while the engine is still working: an HLS
  /// master whose variants carry no CODECS attributes makes the demuxer
  /// probe every rendition — playlist, init segment and media segment per
  /// rendition, each one a separate connection — before the first frame
  /// exists. Judging that phase by a tighter window condemned healthy
  /// players (Steam broadcasts took ~8s of probing and were torn down at
  /// exactly that point, and a single-variant AWS IVS line legitimately
  /// needed 6.8s).
  final Duration sourceReadyTimeout;

  /// Grace before an unexpected `playing=false` triggers a resume request.
  final Duration unexpectedPauseGrace;

  /// Grace for resumed playback to actually start playing.
  final Duration unexpectedPauseFailureGrace;

  /// Deadline for a single uninterrupted buffering episode.
  final Duration bufferingStallTimeout;

  /// Deadline without any new video frame while playing.
  ///
  /// Only consulted when the bound capability snapshot declares
  /// [PlayerAdapterCapabilities.supportsVideoFrameProgress].
  final Duration videoFrameStallTimeout;

  /// How long playback position may stand still before it counts as a
  /// stall.
  ///
  /// Deliberately longer than [videoFrameStallTimeout]: a live stream may
  /// legitimately hold its position for a moment while the engine swaps a
  /// segment, and a false stall costs a full reopen. The watchdog also
  /// only arms after the engine has proven it reports position at all, so
  /// this timeout never judges an engine that does not.
  final Duration positionStallTimeout;

  /// Master switch.
  ///
  /// Disabled watchdogs never arm.
  final bool enabled;

  /// How far the position must move past the first sample of a buffering
  /// episode before the episode counts as over.
  ///
  /// mpv's `time-pos` stands still while it waits for its cache
  /// (`paused-for-cache`), so a whole second of media time proves data is
  /// arriving and being played. An engine whose buffering flag stays set
  /// after that (media_kit's flag can miss the property change that clears
  /// it) is treated as having ended the buffering.
  static const Duration bufferingProgress = Duration(seconds: 1);

  /// How much further the position may move than the wall clock did since
  /// the first sample before the move is taken for a jump (a timestamp
  /// discontinuity, a seek) rather than playback. A jump restarts the
  /// measurement from the new position.
  static const Duration bufferingProgressSlack = Duration(seconds: 2);

  // ---------------------------------------------------------------------------
  // Bound capabilities
  // ---------------------------------------------------------------------------

  PlayerAdapterCapabilities? _capabilities;

  /// The capability snapshot currently bound to these watchdogs.
  ///
  /// This is a bound view, not the authoritative declaration — the
  /// authority is the adapter's own `capabilities`. Read this only for
  /// diagnostics and tests.
  PlayerAdapterCapabilities? get capabilities => _capabilities;

  /// Binds the capability snapshot of the active adapter.
  ///
  /// Call this whenever the active adapter is created, replaced, or
  /// released:
  ///
  /// - after the handle is bound for a new source
  /// - after the engine is switched via `attachAdapter`
  /// - with null on [close] and [dispose], so a stale snapshot never
  ///   leaks into the next source
  ///
  /// Passing null clears the snapshot; the frame-progress watchdog then
  /// treats the adapter as not supporting the signal.
  ///
  /// Only the fields this bundle actually consumes are read, and they
  /// are read directly from the snapshot. No capability is mirrored as
  /// a field, getter, or constructor parameter here.
  ///
  /// Re-binding is a no-op when the snapshot compares equal, so calling
  /// this on every open with the same adapter does not reset a running
  /// video-frame timeout window. The watchdog only reacts when the
  /// consumed capability (`supportsVideoFrameProgress`) actually
  /// changes value.
  void updateCapabilities(PlayerAdapterCapabilities? capabilities) {
    if (_disposed) return;

    if (_capabilities == capabilities) {
      return;
    }

    final wasSupported = _supportsVideoFrameProgress;

    _capabilities = capabilities;

    final nowSupported = _supportsVideoFrameProgress;

    // Only the frame-progress signal is capability-gated. Re-evaluate
    // it so a live subscription never outlives a change of declaration
    // in either direction. Other watchdogs derive from state
    // transitions and are not affected by capability changes.
    if (wasSupported == nowSupported) {
      return;
    }

    if (!nowSupported) {
      _cancelVideoFrameStall();
      return;
    }

    if (_playing && !_buffering && _presentationVisible && _videoExpected) {
      _armVideoFrameStall();
    }

    // A different engine may or may not report position: wait for its first
    // event before judging it.
    _hasPositionSignal = false;
    _cancelPositionStall();
  }

  /// Whether the bound adapter declares a decoded-frame heartbeat.
  bool get _supportsVideoFrameProgress => _capabilities?.supportsVideoFrameProgress ?? false;

  // ---------------------------------------------------------------------------
  // Watchdog generation
  // ---------------------------------------------------------------------------

  /// Monotonically increasing watchdog lifecycle generation.
  ///
  /// Every source/generation reset invalidates all callbacks that were
  /// scheduled for the previous observation window.
  ///
  /// This is intentionally local to the watchdog. It is not a replacement
  /// for PlayerHandle's lifecycle generation or OperationCancelToken.
  int _watchdogGeneration = 0;

  /// Invalidates all pending watchdog callbacks.
  int _invalidateWatchdogGeneration() {
    return ++_watchdogGeneration;
  }

  /// Returns whether [generation] still belongs to the current watchdog
  /// observation window.
  bool _isWatchdogGenerationCurrent(int generation) {
    return !_disposed && generation == _watchdogGeneration;
  }

  // ---------------------------------------------------------------------------
  // RxDart event sources
  // ---------------------------------------------------------------------------

  /// Emits whenever a new decoded video frame is observed.
  ///
  /// The frame watchdog uses switchMap so every new frame cancels the
  /// previous timeout and starts a fresh timeout window.
  final PublishSubject<void> _frameProgress = PublishSubject<void>();

  /// Position heartbeats of the active source.
  ///
  /// Resets the position-stall timer on every event, exactly like
  /// [_frameProgress] does for the frame watchdog.
  final PublishSubject<void> _positionProgress = PublishSubject<void>();

  /// Whether the current engine has reported position at least once.
  ///
  /// The position watchdog arms on this and not on a capability, because
  /// there is no capability for "reports position" — every adapter does.
  /// Waiting for the first event is what keeps the watchdog honest: an
  /// engine that never reports position is never judged by it, instead of
  /// looking stalled from the first second.
  bool _hasPositionSignal = false;

  /// Last position sample, reported alongside the arm log so the two arms
  /// of one session are distinguishable by their value.
  int? _lastPositionMs;

  /// First position sample of the current buffering episode, or null when
  /// none was seen yet (or the measurement was restarted).
  int? _bufferingBaseMs;

  /// Wall clock since [_bufferingBaseMs] was taken.
  final Stopwatch _bufferingBaseClock = Stopwatch();

  // ---------------------------------------------------------------------------
  // Active watchdog subscriptions
  // ---------------------------------------------------------------------------

  StreamSubscription<void>? _sourceReadySubscription;
  StreamSubscription<void>? _continuitySubscription;
  StreamSubscription<void>? _bufferingSubscription;
  StreamSubscription<void>? _videoFrameSubscription;
  StreamSubscription<void>? _positionStallSubscription;

  /// The last "not armed" reason each watchdog reported.
  ///
  /// While a stream is stalled the watchdogs are re-armed on every position
  /// tick, so the same decision line was written several times a second — the
  /// frame watchdog alone printed thousands of identical lines in the minute
  /// that a frozen source was being recovered, burying the stall that caused
  /// them. The line is emitted when the decision changes instead, which is the
  /// information it carries anyway.
  String? _loggedFrameStallSkip;
  String? _loggedPositionStallSkip;

  // ---------------------------------------------------------------------------
  // Current playback observations
  // ---------------------------------------------------------------------------

  bool _playing = false;
  bool _buffering = false;
  bool _presentationVisible = true;
  bool _videoExpected = true;
  bool _disposed = false;

  /// Whether a reassert-play request is currently waiting for the
  /// playback owner to report its result.
  ///
  /// This replaces the old async `onReassertPlay` Future callback.
  ///
  /// The watchdog never awaits the recovery operation anymore.
  bool _recoveryPending = false;

  /// Generation of the currently pending recovery request.
  ///
  /// A recovery result from an older request must never settle a newer
  /// request.
  int? _recoveryGeneration;

  /// Called when a stall is inferred.
  ///
  /// May be invoked from an RxDart timer callback. The owner decides
  /// how recovery should be scheduled.
  void Function(LiveStallKind kind)? onStall;

  /// Called when the watchdog wants the playback owner to perform
  /// a lifecycle-safe recovery action.
  ///
  /// The callback must not directly manipulate a backend player.
  /// The recommended implementation is:
  ///
  /// ```dart
  /// onRecoveryRequested = (action) {
  ///   switch (action) {
  ///     case LiveWatchdogRecoveryAction.reassertPlay:
  ///       controller.reassertPlay();
  ///   }
  /// };
  /// ```
  void Function(LiveWatchdogRecoveryAction action)? onRecoveryRequested;

  // ---------------------------------------------------------------------------
  // Source ready
  // ---------------------------------------------------------------------------

  /// Arms the source-ready deadline after a successful open.
  void armSourceReady() {
    _cancelSourceReady();

    if (_disposed) {
      return;
    }

    _recoveryPending = false;
    _recoveryGeneration = null;

    if (!_canWatch || sourceReadyTimeout <= Duration.zero || _playing) {
      return;
    }

    final generation = _watchdogGeneration;

    _sourceReadySubscription = TimerStream<void>(null, sourceReadyTimeout).listen((_) {
      if (!_isWatchdogGenerationCurrent(generation)) {
        return;
      }

      if (!_playing) {
        onStall?.call(LiveStallKind.sourceReadyTimeout);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Playing state
  // ---------------------------------------------------------------------------

  void onPlayingChanged(bool playing, {required bool fromUserIntent}) {
    if (_disposed) {
      return;
    }

    _playing = playing;

    if (!playing) {
      // Position does not move while paused; resuming measures afresh.
      _resetBufferingProgress();
    }

    _cancelSourceReady();

    if (playing) {
      _recoveryPending = false;
      _recoveryGeneration = null;

      _cancelContinuity();

      if (_buffering) {
        _armBufferingStall();
      } else {
        _armVideoFrameStall();
      }

      // A position sample that arrived while the engine was still settling
      // could not arm the stall detector. Now that playback is known to be
      // running, arm it - see [onPositionProgress].
      if (_hasPositionSignal && _positionStallSubscription == null) {
        _armPositionStall(via: 'playing');
      }

      return;
    }

    _cancelVideoFrameStall();

    if (fromUserIntent) {
      _recoveryPending = false;
      _recoveryGeneration = null;

      _cancelContinuity();
      _cancelBufferingStall();

      return;
    }

    if (_buffering) {
      _armBufferingStall();
    } else {
      _armContinuity();
    }
  }

  // ---------------------------------------------------------------------------
  // Buffering state
  // ---------------------------------------------------------------------------

  void onBufferingChanged(bool buffering) {
    if (_disposed) {
      return;
    }

    _buffering = buffering;

    // Every buffering episode is measured from its own first position.
    _resetBufferingProgress();

    if (!buffering && _hasPositionSignal && _positionStallSubscription == null) {
      // Buffering was the reason arming was refused; it is over now.
      _armPositionStall(via: 'bufferingEnd');
    }

    if (buffering) {
      _cancelVideoFrameStall();
      _cancelContinuity();
      _armBufferingStall();

      return;
    }

    _cancelBufferingStall();

    if (_playing) {
      _armVideoFrameStall();
    } else {
      _armContinuity();
    }
  }

  // ---------------------------------------------------------------------------
  // Video frame progress
  // ---------------------------------------------------------------------------

  /// Feeds a real decoded-video-frame observation.
  ///
  /// This must only be called from [PlayerAdapterEvent.videoFrameProgress].
  ///
  /// Video-size changes, position changes, metadata changes, and other
  /// backend events must not be treated as decoded-frame progress.
  void onFrameProgress() {
    if (_disposed || !_playing || !_presentationVisible || !_videoExpected || !_supportsVideoFrameProgress) {
      return;
    }

    _frameProgress.add(null);
  }

  /// Feeds a playback-position update.
  ///
  /// Position is the one progress signal every engine reports, which makes
  /// it the only stall detector that works everywhere — including on
  /// engines that declare no frame heartbeat, where a frozen picture is
  /// otherwise indistinguishable from a healthy stream.
  ///
  /// Returns true when this sample ended a buffering episode the engine
  /// never ended itself (see [bufferingProgress]); the owner then shows the
  /// stream as playing again, exactly as the engine's own buffering-end
  /// notification would have.
  bool onPositionProgress(Duration position) {
    if (_disposed) {
      return false;
    }

    _lastPositionMs = position.inMilliseconds;

    if (!_hasPositionSignal) {
      // First position of this source: the engine reports position, so the
      // watchdog may start judging it.
      _hasPositionSignal = true;

      MediaCoreLog.debug(
        LogCategory.recovery,
        'position-stall watchdog enabled (${positionStallTimeout.inMilliseconds}ms)',
        fields: <String, Object?>{'positionMs': position.inMilliseconds},
      );
    }

    // Arming is attempted on every sample, not only on the first one.
    //
    // The first position of a source routinely arrives while the engine is
    // still settling - mpv pauses and restarts itself right after open, so
    // the sample lands before the playing state is known. A one-shot arm
    // attempt was refused in that moment ("playback not running") and the
    // detector then stayed dead for the rest of the source: later samples
    // only fed a stream nobody was subscribed to, a frozen picture was
    // never detected, and the room simply appeared to have failed to
    // start. Retrying here costs one comparison and keeps the only
    // engine-independent stall detector alive.
    //
    // The buffering check runs first: when it ends the episode, the
    // position-stall watchdog that buffering kept disarmed is armed by it.
    final bufferingEnded = _endBufferingOnProgress(position);

    if (_positionStallSubscription == null) {
      _armPositionStall(via: 'position');

      return bufferingEnded;
    }

    _positionProgress.add(null);

    return bufferingEnded;
  }

  /// Ends the current buffering episode when [position] shows playback
  /// moving through it; returns whether it did.
  ///
  /// Without this the buffering deadline judged the engine's flag alone: a
  /// flag left set while the position moved fired
  /// [LiveStallKind.bufferingStallTimeout] after [bufferingStallTimeout] and
  /// reopened a stream that was playing.
  ///
  /// Only an engine that is playing counts: a pause ends nothing. A position
  /// that moved backwards, or further than the wall clock allows
  /// ([bufferingProgressSlack]), restarts the measurement from itself.
  bool _endBufferingOnProgress(Duration position) {
    if (!_buffering || !_playing) {
      return false;
    }

    final positionMs = position.inMilliseconds;
    final baseMs = _bufferingBaseMs;

    if (baseMs == null) {
      _startBufferingProgress(positionMs);
      return false;
    }

    final advancedMs = positionMs - baseMs;
    final allowedMs = _bufferingBaseClock.elapsedMilliseconds + bufferingProgressSlack.inMilliseconds;

    if (advancedMs < 0 || advancedMs > allowedMs) {
      _startBufferingProgress(positionMs);
      return false;
    }

    if (advancedMs < bufferingProgress.inMilliseconds) {
      return false;
    }

    MediaCoreLog.info(
      LogCategory.recovery,
      'buffering ended by position progress; the engine still reports buffering',
      fields: <String, Object?>{
        'fromMs': baseMs,
        'toMs': positionMs,
        'elapsedMs': _bufferingBaseClock.elapsedMilliseconds,
      },
    );

    onBufferingChanged(false);

    return true;
  }

  void _startBufferingProgress(int positionMs) {
    _bufferingBaseMs = positionMs;
    _bufferingBaseClock
      ..reset()
      ..start();
  }

  void _resetBufferingProgress() {
    _bufferingBaseMs = null;
    _bufferingBaseClock
      ..stop()
      ..reset();
  }

  // ---------------------------------------------------------------------------
  // Presentation
  // ---------------------------------------------------------------------------

  /// Marks whether a route currently owns the mounted video presentation.
  ///
  /// Hidden presentations do not run the frame watchdog. Buffering state
  /// is checked by [armVideoFrameStall] itself, so this method does not
  /// need to duplicate it.
  void setPresentationVisible(bool visible) {
    if (_disposed) {
      return;
    }

    _presentationVisible = visible;

    if (!visible) {
      _cancelVideoFrameStall();
    } else if (_playing) {
      _armVideoFrameStall();
    }
  }

  /// Marks whether decoded video frames are expected for the session.
  ///
  /// Audio-only playback has no video track, so no frame heartbeat can
  /// ever arrive and a missing one proves nothing. Passing `false` keeps
  /// the frame watchdog disarmed instead of inferring a stall from a
  /// signal the session was never going to produce; passing `true` arms
  /// it again for the current playback state.
  ///
  /// This is a session-level mode rather than a per-source state, like
  /// [setPresentationVisible], so it survives source changes.
  void setVideoExpected(bool expected) {
    if (_disposed) {
      return;
    }

    if (_videoExpected == expected) {
      return;
    }

    _videoExpected = expected;

    if (!expected) {
      _cancelVideoFrameStall();
      return;
    }

    if (_playing && !_buffering && _presentationVisible) {
      _armVideoFrameStall();
    }
  }

  bool get isPlaying => _playing;

  // ---------------------------------------------------------------------------
  // Recovery result
  // ---------------------------------------------------------------------------

  /// Reports the result of a recovery action requested through
  /// [onRecoveryRequested].
  ///
  /// This method is intentionally called by the playback owner after
  /// it has executed the action through [PlayerHandle].
  ///
  /// The watchdog does not await that operation itself. This keeps
  /// player lifecycle ownership outside the watchdog.
  ///
  /// `resumed` should indicate whether the recovery command was accepted
  /// and the owner believes playback was successfully reasserted.
  ///
  /// If playback has not actually returned to a valid playing/buffering
  /// state yet, the failure grace window remains available so the normal
  /// playback-state callback can settle the result.
  void reportRecoveryResult(bool resumed) {
    if (_disposed) {
      return;
    }

    if (!_recoveryPending) {
      return;
    }

    final recoveryGeneration = _recoveryGeneration;

    if (recoveryGeneration == null || !_isWatchdogGenerationCurrent(recoveryGeneration)) {
      return;
    }

    _recoveryPending = false;
    _recoveryGeneration = null;

    if (resumed && (_playing || _buffering)) {
      return;
    }

    if (!_canWatch || unexpectedPauseFailureGrace <= Duration.zero) {
      onStall?.call(LiveStallKind.unexpectedPauseResumeFailed);

      return;
    }

    _armRecoveryFailureGrace(recoveryGeneration);
  }

  void _armRecoveryFailureGrace(int generation) {
    _cancelContinuity();

    if (!_isWatchdogGenerationCurrent(generation)) {
      return;
    }

    _continuitySubscription = TimerStream<void>(null, unexpectedPauseFailureGrace).listen((_) {
      if (!_isWatchdogGenerationCurrent(generation)) {
        return;
      }

      if (!_playing) {
        onStall?.call(LiveStallKind.unexpectedPauseTimeout);
      }
    });
  }



  // ---------------------------------------------------------------------------
  // Cancellation
  // ---------------------------------------------------------------------------

  void _cancelSourceReady() {
    final subscription = _sourceReadySubscription;

    _sourceReadySubscription = null;

    subscription?.cancel();
  }

  void _cancelContinuity() {
    final subscription = _continuitySubscription;

    _continuitySubscription = null;

    subscription?.cancel();
  }

  void _cancelBufferingStall() {
    final subscription = _bufferingSubscription;

    _bufferingSubscription = null;

    subscription?.cancel();
  }

  void _cancelVideoFrameStall() {
    final subscription = _videoFrameSubscription;

    _videoFrameSubscription = null;

    subscription?.cancel();
  }

  /// Cancels every watchdog and clears the observations behind them.
  ///
  /// The observed playback flags are dropped together with the timers so
  /// a retired source cannot influence the next one. They are read back
  /// by [armSourceReady] and by [updateCapabilities] when the next
  /// adapter is bound, and a leftover `playing` would either disable the
  /// source-ready deadline or arm the frame deadline before the new
  /// source has produced anything.
  ///
  /// Call this when:
  ///
  /// - the source changes
  /// - the playback generation changes
  /// - the user pauses
  /// - recovery takes ownership
  /// - the controller closes the current source
  void cancelAll() {
    _cancelPositionStall();
    if (_disposed) {
      return;
    }

    // Invalidate every timer callback before cancelling subscriptions.
    // StreamSubscription.cancel() alone cannot protect a callback that
    // has already been queued by the event loop.
    _invalidateWatchdogGeneration();

    _playing = false;
    _buffering = false;
    _recoveryPending = false;
    _recoveryGeneration = null;
    _resetBufferingProgress();

    _cancelSourceReady();
    _cancelContinuity();
    _cancelBufferingStall();
    _cancelVideoFrameStall();
  }

  /// Releases the watchdog bundle.
  void dispose() {
    if (_disposed) {
      return;
    }

    // Invalidate callbacks before marking the object disposed so any
    // already queued RxDart timer callback becomes stale immediately.
    _invalidateWatchdogGeneration();

    _disposed = true;

    _playing = false;
    _buffering = false;
    _recoveryPending = false;
    _recoveryGeneration = null;
    _resetBufferingProgress();

    _cancelSourceReady();
    _cancelContinuity();
    _cancelBufferingStall();
    _cancelVideoFrameStall();

    onStall = null;
    onRecoveryRequested = null;
    _capabilities = null;

    _positionProgress.close();
    _frameProgress.close();
  }

  /// Forgets the position signal of the previous engine or source.
  ///
  /// Called when the adapter or the source changed: whether the new one
  /// reports position is unknown until it does, and judging it by the
  /// previous one's signal would either false-stall or false-clear.
  void resetPositionSignal() {
    if (_disposed) {
      return;
    }

    _hasPositionSignal = false;
    _resetBufferingProgress();

    _cancelPositionStall();
  }
}
