import 'dart:async';

import 'package:clock/clock.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/recovery/recovery_action.dart';
import 'package:media_core/recovery/recovery_candidate_provider.dart';
import 'package:media_core/recovery/recovery_context.dart';
import 'package:media_core/recovery/recovery_failure.dart';
import 'package:media_core/recovery/recovery_ladder_event.dart';
import 'package:media_core/recovery/recovery_session.dart';
import 'package:media_core/recovery/recovery_snapshot.dart';
import 'package:media_core/recovery/recovery_state.dart';
import 'package:media_core/recovery/recovery_step.dart';
import 'package:media_core/recovery/recovery_target.dart';
import 'package:media_core_logging/media_core_logging.dart';

/// Lifecycle of the ladder.
enum RecoveryLadderStatus {
  /// No run in progress and none finished.
  idle,

  /// A run is escalating.
  running,

  /// A run ended because a step succeeded.
  completed,

  /// A run ended because no step was left.
  exhausted,

  /// Runs are refused until [RecoveryLadder.resume] is called.
  suspended,

  /// The ladder was released.
  disposed,
}

/// The recovery sweep for a standalone player.
///
/// Same shape, deliberately, as the live module's sweep — one source of
/// truth for what recovery means in this framework:
///
/// ```text
/// report(failure)
///   → session from the target (what is playing, what to preserve)
///   → per engine: reopen the current source once, then every other source
///   → sources exhausted → next engine, sweep again
///   → nothing left → exhausted event
/// ```
///
/// Three rules bound it:
///
/// - **one run at a time** — [report] refuses while a step is in flight,
///   so several failure reporters can never start competing recoveries;
/// - **every attempt is verified by the target** — a step that opens
///   cleanly but never plays throws inside the target and counts as a
///   failure here; the ladder never mistakes "open returned" for success;
/// - **bounded by the candidate lists** — each source once per engine,
///   each engine once, no budgets, no backoff, no memory. When the lists
///   run out the run ends and the failure is reported to the caller.
///
/// The escalation itself carries one piece of judgement: a source-level
/// failure (the URL cannot be opened — expired signature, unsupported
/// format) skips the in-place reopen, because replaying the same URL on
/// the same engine reproduces the fault.
///
/// Execution goes through [RecoveryTarget]; this module never touches an
/// adapter, a registry or a session controller.
final class RecoveryLadder {
  /// Creates a ladder.
  ///
  /// [retryDelay] answers "how long before attempt number N", and is what makes
  /// `KernelOptions.retryBaseDelay` mean something: without it a sweep runs its
  /// rungs back to back, so an engine that just refused an open is asked again in
  /// the same millisecond, and a dead source is hammered for as long as the sweep
  /// has rungs left. Null keeps the old immediate escalation.
  RecoveryLadder({required this.target, required this.candidates, this.retryDelay}) {
    _targetEvents = target.executionEvents.listen(_onTargetEvent, onError: (Object _) {});
  }

  /// Layer that executes the physical steps.
  final RecoveryTarget target;

  /// Source of alternative sources and backends.
  final RecoveryCandidateProvider candidates;

  /// How long to wait before each attempt of a sweep, by attempt number.
  final Duration Function(int attempt)? retryDelay;

  final StreamController<RecoveryLadderEvent> _events = StreamController<RecoveryLadderEvent>.broadcast();

  StreamSubscription<RecoveryTargetEvent>? _targetEvents;
  Future<void>? _run;

  RecoveryLadderStatus _status = RecoveryLadderStatus.idle;
  RecoveryFailure? _failure;
  RecoverySession? _session;
  int _attempts = 0;
  int _generation = 0;

  bool _disposed = false;

  /// Decision events of this ladder.
  Stream<RecoveryLadderEvent> get events => _events.stream;

  /// Current lifecycle status.
  RecoveryLadderStatus get status => _status;

  /// Whether a run is currently escalating.
  bool get isRunning => _status == RecoveryLadderStatus.running;

  /// Failure of the current (or last) run.
  RecoveryFailure? get failure => _failure;

  /// Decision context of the current (or last) run.
  RecoverySession? get session => _session;

  /// Steps executed in the current (or last) run.
  int get attempt => _attempts;

  /// Completes when the current run settles.
  Future<void> get settled => _run ?? Future<void>.value();

  /// Diagnostic snapshot in the recovery module's legacy shape.
  RecoverySnapshot get snapshot {
    final current = _failure;

    return RecoverySnapshot(
      state: _recoveryState(),
      context: current == null
          ? null
          : RecoveryContext(
              reason: current.effectiveReason,
              sourceId: current.sourceId,
              generationId: current.generationId,
              message: current.message,
              metadata: <String, Object?>{'reporter': current.source.name},
            ),
    );
  }

  /// Reports a failure and starts a sweep.
  ///
  /// Returns `true` when the sweep started, `false` when it did not —
  /// because one is already running, the ladder is suspended, or the
  /// failure is not recoverable at all. A refusal is not an error: a
  /// second recovery for a failure already being recovered is exactly the
  /// duplicate work this class exists to prevent.
  bool report(RecoveryFailure failure) {
    if (_disposed || _status == RecoveryLadderStatus.suspended) {
      return false;
    }

    // A target with nothing to recover (the caller closed the source) cannot
    // run a single step. Accepting the report would walk straight into the
    // "cannot execute" branch and declare the player exhausted — a critical
    // fatal event for a player that is simply closed. Refusing is the honest
    // answer: there is nothing to recover.
    if (!target.isRecoveryAvailable) {
      MediaCoreLog.debug(
        LogCategory.recovery,
        'report refused: the target has nothing to recover',
        fields: <String, Object?>{'stableKey': failure.stableKey, 'code': failure.code.value},
      );

      return false;
    }

    if (_status == RecoveryLadderStatus.running) {
      MediaCoreLog.debug(
        LogCategory.recovery,
        'report ignored: sweep already running',
        fields: <String, Object?>{'stableKey': failure.stableKey, 'attempt': _attempts},
      );

      return false;
    }

    if (_isNotRecoverable(failure)) {
      MediaCoreLog.debug(
        LogCategory.recovery,
        'report refused: failure is terminal by classification',
        fields: <String, Object?>{'code': failure.code.value},
      );

      return false;
    }

    final generation = ++_generation;

    _status = RecoveryLadderStatus.running;
    _failure = failure;
    _attempts = 0;
    // A run that throws before its first step (a candidate provider that
    // throws) reports `_lastStepFailure ?? failure`; carrying the previous
    // run's step failure into this one would mislabel the cause.
    _lastStepFailure = null;
    _run = _sweep(failure, generation);

    return true;
  }

  /// Stops the current run and returns to idle.
  ///
  /// Called when the lifecycle moves on: a new source open, a close, a
  /// recycle. Recovery for a source that is no longer playing is stale by
  /// definition.
  void reset() {
    if (_disposed) {
      return;
    }

    _abort('Recovery sweep was reset.');
    _status = RecoveryLadderStatus.idle;
  }

  /// Stops the current run and refuses new ones until [resume].
  ///
  /// Called when the user takes over: a user intent is a recovery
  /// boundary, not a recovery opportunity.
  void suspend() {
    if (_disposed) {
      return;
    }

    _abort('Recovery sweep was suspended.');
    _status = RecoveryLadderStatus.suspended;
  }

  /// Accepts reports again after [suspend].
  void resume() {
    if (_disposed) {
      return;
    }

    if (_status == RecoveryLadderStatus.suspended) {
      _status = RecoveryLadderStatus.idle;
    }
  }

  /// Releases the ladder.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _abort('Recovery sweep was disposed.');
    _status = RecoveryLadderStatus.disposed;

    await _targetEvents?.cancel();
    _targetEvents = null;

    await _events.close();
  }

  // ---------------------------------------------------------------------------
  // The sweep
  // ---------------------------------------------------------------------------

  Future<void> _sweep(RecoveryFailure failure, int generation) async {
    try {
      if (!target.isRecoveryAvailable) {
        _finishExhausted(generation, failure, 'The player cannot run recovery right now.');

        return;
      }

      final session = target.buildRecoverySession(failure, candidates.candidatesFor(failure));

      _session = session;

      // A source-level failure is a verdict on the URL/engine pair, not on
      // the stream's state: replaying it reproduces the fault (and on
      // signed live URLs cannot even succeed — the token is spent). The
      // sweep starts at the next line instead.
      final reopenAllowed = !failure.effectiveReason.isSource;
      final planLabel = <String>[if (reopenAllowed) 'reopen', 'nextLine', 'nextBackend'].join(' -> ');

      _emit(RecoveryLadderStarted(failure: failure, plan: _planOf(reopenAllowed)));

      MediaCoreLog.info(
        LogCategory.recovery,
        'sweep started: $planLabel',
        fields: <String, Object?>{
          'reportedBy': failure.source.name,
          'code': failure.code.value,
          'reason': failure.effectiveReason.toString(),
          'message': failure.message,
          'stableKey': failure.stableKey,
          'label': session.label,
          'wasPlaying': session.wasPlaying,
          'positionMs': session.position.inMilliseconds,
          'lines': session.sourceCandidates.length,
          'backends': session.backendCandidates.map((registration) => registration.id).toList(),
        },
      );

      final currentSourceId = session.source?.id.value;

      var triedSources = <String>{?currentSourceId};
      final triedBackends = <String>{?session.backendId};

      var reopenSpent = false;

      while (_isCurrent(generation)) {
        // Rung 1: reopen the current source on the current engine, once
        // per engine.
        if (reopenAllowed && !reopenSpent && session.source != null) {
          reopenSpent = true;

          final step = RecoveryStep.reopen(index: 0, source: session.source);

          if (await _runStep(step, session, generation)) {
            _finishCompleted(generation, step, failure);

            return;
          }

          continue;
        }

        // Rung 2: the next untried source on this engine.
        final sourceStep = _nextSourceStep(session, triedSources);

        if (sourceStep != null) {
          if (await _runStep(sourceStep, session, generation)) {
            _finishCompleted(generation, sourceStep, failure);

            return;
          }

          continue;
        }

        // Rung 3: the next untried engine. Its sweep restarts at the line
        // the user was watching — a line that failed on one engine says
        // nothing about the next one.
        final backendStep = _nextBackendStep(session, triedBackends);

        if (backendStep != null) {
          if (await _runStep(backendStep, session, generation)) {
            triedSources = <String>{?session.source?.id.value};
            reopenSpent = false;

            MediaCoreLog.info(
              LogCategory.fallback,
              'engine failed out — sweeping again on ${backendStep.backendId}',
              fields: <String, Object?>{'enginesTried': triedBackends.length},
            );

            continue;
          }

          continue;
        }

        _finishExhausted(
          generation,
          failure,
          'Every allowed source has been tried'
          '${triedBackends.length > 1 ? ' on every available engine' : ''}.',
        );

        return;
      }
    } on Object catch (error) {
      // A failure inside the sweep itself (a throwing provider) must still
      // end the run: leaving the status at `running` would block every
      // later report.
      _finishExhausted(generation, _lastStepFailure ?? failure, 'Recovery sweep failed: $error');
    }
  }

  /// Whether [failure] may not be recovered at all.
  ///
  /// Cancelled and stale failures are answered by the caller's lifecycle,
  /// not by recovery.
  bool _isNotRecoverable(RecoveryFailure failure) {
    const terminal = <PlayerErrorCode>[
      PlayerErrorCode.cancelled,
      PlayerErrorCode.superseded,
      PlayerErrorCode.staleGeneration,
      PlayerErrorCode.disposed,
    ];

    return terminal.contains(failure.code);
  }

  RecoveryStep? _nextSourceStep(RecoverySession session, Set<String> triedSources) {
    for (final candidate in session.sourceCandidates) {
      if (!triedSources.add(candidate.id.value)) {
        continue;
      }

      return RecoveryStep.nextLine(index: _attempts, source: candidate);
    }

    return null;
  }

  RecoveryStep? _nextBackendStep(RecoverySession session, Set<String> triedBackends) {
    for (final candidate in session.backendCandidates) {
      if (!triedBackends.add(candidate.id)) {
        continue;
      }

      return RecoveryStep.nextBackend(index: _attempts, backendId: candidate.id);
    }

    return null;
  }

  List<RecoveryStepKind> _planOf(bool reopenAllowed) {
    return <RecoveryStepKind>[
      if (reopenAllowed) RecoveryStepKind.sameBackendReopen,
      RecoveryStepKind.nextLine,
      RecoveryStepKind.nextBackend,
    ];
  }

  Future<bool> _runStep(RecoveryStep step, RecoverySession session, int generation) async {
    if (!target.isRecoveryAvailable) {
      return false;
    }

    if (!await _awaitRetryDelay(generation)) {
      // Superseded or disposed while waiting: the run's loop ends on its
      // generation check, and [_abort] has already landed the status.
      return false;
    }

    _attempts++;

    _emit(RecoveryLadderStepStarted(step: step, attempt: _attempts, failure: _failure));

    MediaCoreLog.info(
      LogCategory.recovery,
      'sweep step: $step',
      fields: <String, Object?>{'kind': step.kind.name, 'engine': step.backendId, 'uri': step.source?.uri.toString()},
    );

    try {
      if (step.kind == RecoveryStepKind.nextBackend) {
        await target.swapToForRecovery(step, session);
      } else {
        await target.reopenForRecovery(step, session);
      }

      return true;
    } on Object catch (error, stackTrace) {
      final stepFailure = RecoveryFailure.fromMessage(
        '${step.label} failed: $error',
        error: error,
        stackTrace: stackTrace,
        source: RecoveryFailureSource.kernel,
        sourceId: session.source?.id,
        backendId: step.backendId ?? session.backendId,
        generationId: session.generationId,
      );

      _lastStepFailure = stepFailure;

      MediaCoreLog.warning(
        LogCategory.recovery,
        'sweep step failed: ${step.label}',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'attempt': _attempts, 'kind': step.kind.name},
      );

      _emit(
        RecoveryLadderStepFailed(
          step: step,
          attempt: _attempts,
          failure: stepFailure,
          error: error,
          stackTrace: stackTrace,
        ),
      );

      return false;
    }
  }

  /// Waits the delay [retryDelay] asks for the attempt that is about to run.
  ///
  /// The first attempt of a sweep never waits: the failure that opened the sweep
  /// already cost the viewer the time one retry is worth. Reporting whether the
  /// run may continue is the point of the return value — a wait is the first
  /// moment a sweep can be overtaken by a new open or a close, and executing the
  /// step anyway would reopen something the viewer has already left.
  Future<bool> _awaitRetryDelay(int generation) async {
    final attempt = _attempts + 1;

    if (attempt <= 1) {
      return _isCurrent(generation);
    }

    final delay = retryDelay?.call(attempt) ?? Duration.zero;

    if (delay <= Duration.zero) {
      return _isCurrent(generation);
    }

    await Future<void>.delayed(delay);

    return _isCurrent(generation) && !_disposed;
  }

  // ---------------------------------------------------------------------------
  // Terminal transitions
  // ---------------------------------------------------------------------------

  RecoveryFailure? _lastStepFailure;

  void _finishCompleted(int generation, RecoveryStep step, RecoveryFailure failure) {
    if (!_isCurrent(generation)) {
      return;
    }

    _status = RecoveryLadderStatus.completed;

    MediaCoreLog.info(
      LogCategory.recovery,
      'sweep recovered via ${step.label} after $_attempts attempt(s)',
      fields: <String, Object?>{'backend': step.backendId, 'uri': step.source?.uri.toString()},
    );

    _emit(RecoveryLadderCompleted(step: step, attempt: _attempts, failure: failure));
  }

  void _finishExhausted(int generation, RecoveryFailure failure, String message) {
    if (!_isCurrent(generation)) {
      return;
    }

    _status = RecoveryLadderStatus.exhausted;

    MediaCoreLog.error(
      LogCategory.recovery,
      'sweep exhausted after $_attempts attempt(s): $message',
      fields: <String, Object?>{'code': failure.code.value, 'message': failure.message, 'backend': failure.backendId},
    );

    _emit(RecoveryLadderExhausted(attempt: _attempts, message: message, failure: failure));
  }

  /// Stops the current run without deciding anything.
  ///
  /// The in-flight step is not cancelled — a native backend call cannot
  /// be — but the generation check makes its result unusable, which is the
  /// same guarantee the handle's operation generations provide.
  void _abort(String reason) {
    final wasRunning = _status == RecoveryLadderStatus.running;

    _generation++;

    if (wasRunning) {
      MediaCoreLog.debug(LogCategory.recovery, 'sweep cancelled after $_attempts attempt(s): $reason');

      // The run has to land in a *terminal* status. Bumping the generation
      // alone stops the in-flight sweep, but both terminal finishers bail on
      // their generation check — so the status would stay `running` forever,
      // every later report would be refused, and `settled` would never
      // complete. `idle` is the right terminal value here: nothing was
      // decided, and the next report may start a fresh sweep.
      _status = RecoveryLadderStatus.idle;

      _emit(RecoveryLadderCancelled(attempt: _attempts, message: reason, failure: _failure));
    }

    _failure = null;
    _session = null;
    _attempts = 0;
    _lastStepFailure = null;
  }

  /// The target can no longer execute anything: stop escalating instead of
  /// feeding steps into a player that has already given up.
  void _onTargetEvent(RecoveryTargetEvent event) {
    if (_disposed || !event.aborted) {
      return;
    }

    _abort('The recovery target can no longer recover.');
  }

  bool _isCurrent(int generation) {
    return !_disposed && _status == RecoveryLadderStatus.running && generation == _generation;
  }

  void _emit(RecoveryLadderEvent event) {
    if (_events.isClosed) {
      return;
    }

    _events.add(event);
  }

  RecoveryState _recoveryState() {
    final action = switch (_status) {
      RecoveryLadderStatus.running => const RecoveryAction.retry(),
      RecoveryLadderStatus.completed => const RecoveryAction.retry(),
      RecoveryLadderStatus.exhausted => const RecoveryAction.stop(),
      _ => const RecoveryAction.none(),
    };

    return RecoveryState(
      action: action,
      attempt: _attempts,
      active: _status == RecoveryLadderStatus.running,
      completed: _status == RecoveryLadderStatus.completed,
      exhausted: _status == RecoveryLadderStatus.exhausted,
      updatedAt: clock.now(),
    );
  }

  @override
  String toString() {
    return 'RecoveryLadder(${_status.name}, attempt: $_attempts)';
  }
}
