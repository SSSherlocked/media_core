import 'dart:async';

import 'package:media_core/media_core.dart'
    show
        LogCategory,
        MediaCoreLog,
        RecordingConfig,
        RecordingSource,
        RecordingState,
        RecordingStatus,
        RecordingStatusX,
        RetryUtils;
import 'package:media_core_recording_ffmpeg/src/ffmpeg_recording_backend.dart';
import 'package:media_core_recording_ffmpeg/src/recording_verification.dart';

/// What a room's own API says about it right now.
final class FfmpegLiveRoomStatus {
  /// Creates a status.
  const FfmpegLiveRoomStatus({required this.isLive, this.title, this.source});

  /// A room that is not broadcasting.
  const FfmpegLiveRoomStatus.offline({this.title}) : isLive = false, source = null;

  /// A room that is broadcasting at [source].
  const FfmpegLiveRoomStatus.live(this.source, {this.title}) : isLive = true;

  /// Whether recording is worth starting.
  final bool isLive;

  /// The room's title, for whoever is watching the list.
  final String? title;

  /// The address to record, when the probe had to resolve one to answer.
  ///
  /// A status endpoint usually returns the stream URL with the status, and asking
  /// it for the status only to throw the address away and fetch it again shortly
  /// after is a second signed request for the same thing — and signed addresses
  /// are the kind that expire between the two.
  final String? source;
}

/// Asks a room what it is doing.
///
/// This is the whole reason the watcher exists: only the host knows how its
/// platform says "live", and only it should hold the credentials that say so.
typedef LiveRoomStatusProbe = Future<FfmpegLiveRoomStatus> Function(RecordingSource source);

/// The result of one recording a watcher started.
///
/// The core's `RecordingResult` says what the backend reported for one call; this
/// adds the two facts a scheduler keeps: when the recording ran, and what its
/// files turned out to be.
final class FfmpegRecordingOutcome {
  /// Creates an outcome.
  const FfmpegRecordingOutcome({
    required this.startedAt,
    required this.finishedAt,
    required this.success,
    required this.bytesWritten,
    required this.directory,
    this.segments,
    this.error,
  });

  /// When the recording was started.
  final DateTime startedAt;

  /// When it ended.
  final DateTime finishedAt;

  /// Whether its own files say it worked.
  final bool success;

  /// Bytes on disk for this recording, measured by the backend's verification.
  final int bytesWritten;

  /// Segments the journal listed, or null when the backend was told not to verify.
  final int? segments;

  /// Directory the segments were written to.
  final String? directory;

  /// Why it failed, when it did.
  final Object? error;

  /// How long the recording ran.
  Duration get elapsed => finishedAt.difference(startedAt);

  @override
  String toString() =>
      'FfmpegRecordingOutcome(${success ? 'ok' : 'failed'}, ${elapsed.inSeconds}s, ${bytesWritten}B'
      '${segments == null ? '' : ', $segments segments'}${error == null ? '' : ', $error'})';
}

/// One live session: the time the room was seen live, the recordings it produced,
/// and the time it was seen offline.
final class FfmpegLiveRecordingSession {
  /// Creates a session.
  const FfmpegLiveRecordingSession({required this.startedAt, required this.recordings, this.endedAt, this.title});

  /// When the room was first seen live.
  final DateTime startedAt;

  /// The recordings made during this session, in order.
  ///
  /// More than one is normal: a stream that drops and is not recovered by the
  /// backend is recorded again the next time the room is found live, and the
  /// segments from those two runs are not one file.
  final List<FfmpegRecordingOutcome> recordings;

  /// When the room was first seen offline, or null while it is still live.
  final DateTime? endedAt;

  /// The title the probe last reported.
  final String? title;

  /// Total media across this session's recordings.
  Duration get recordedFor => recordings.fold(Duration.zero, (total, outcome) => total + outcome.elapsed);

  @override
  String toString() =>
      'FfmpegLiveRecordingSession(${startedAt.toIso8601String()} → '
      '${endedAt?.toIso8601String() ?? 'live'}, ${recordings.length} recording(s), ${recordedFor.inSeconds}s)';
}

/// Watches a room and records it while it is live.
///
/// A recording backend answers "record this address". It does not know that the
/// address belongs to someone who has not started broadcasting yet, or that they
/// will go offline in the night and be live again tomorrow. That is the gap this
/// fills, and it is the shape the reference implementation is built around: ask the
/// room, record while it says live, notice when it stops saying so, ask again later.
///
/// Three of its details are load-bearing rather than decorative:
///
/// - **One start notification per live session.** [onLiveStart] fires the first
///   time the room is seen live and [onLiveEnd] the first time it is seen offline
///   after that. A stream that flickers would otherwise produce a message per poll,
///   which is how a monitor of twenty rooms becomes noise and gets muted.
/// - **Jittered polling** ([RetryUtils.backoff]), so a host watching many rooms does
///   not reach the platform's endpoint with all of them in the same second and trip
///   its risk control.
/// - **A recording that ended almost immediately is checked again soon.** A
///   streamer restarting their encoder looks exactly like a room that closed, and
///   waiting the full interval there costs the beginning of the real session: a
///   recording shorter than [shortRecordingAfter] sends the next check at
///   [recheckInterval] instead.
///
/// It does not poll while a recording is running. A stream that dies is noticed by
/// the recording itself — FFmpeg's read timeout ends the process and the backend's
/// re-opening gives up after its own limit — and the watcher learns the room is over
/// from the recording ending, then asks the room once more. Two independent timers
/// watching the same fact would only disagree about it.
class FfmpegLiveRecordingWatcher {
  /// Creates a watcher for one room.
  ///
  /// [statusProbe] is asked, once per poll, whether the room is live. The
  /// notifications are host-side: a watcher that pushed its own message would need
  /// the host's credentials and its choice of channel anyway.
  FfmpegLiveRecordingWatcher({
    required FfmpegRecordingBackend backend,
    required LiveRoomStatusProbe statusProbe,
    this.pollInterval = const Duration(seconds: 60),
    this.recheckInterval = const Duration(seconds: 15),
    this.shortRecordingAfter = const Duration(minutes: 1),
    this.maxConsecutiveProbeFailures = 5,
    this.maxAlmostStartRechecks = 10,
    this.onLiveStart,
    this.onLiveEnd,
  }) : _backend = backend,
       _statusProbe = statusProbe;

  /// The backend each recording runs on.
  final FfmpegRecordingBackend _backend;

  /// The room's own status endpoint.
  final LiveRoomStatusProbe _statusProbe;

  /// How long to wait between checks when nothing just went wrong.
  ///
  /// A minute, plus up to half again of jitter. A live room's schedule is
  /// measured in tens of minutes; polling faster buys the host rate limits.
  final Duration pollInterval;

  /// How long to wait after a recording that ended almost immediately.
  final Duration recheckInterval;

  /// A recording shorter than this counts as an almost-start, not a session.
  final Duration shortRecordingAfter;

  /// How many short-interval checks an almost-start earns before the wait goes back
  /// to [pollInterval].
  ///
  /// Without a bound, a room that closed in the middle of a restart attempt would be
  /// asked every few seconds for the rest of the night — the fast re-check is for the
  /// seconds around a restart, not a permanent polling rate.
  final int maxAlmostStartRechecks;

  /// How many probe failures in a row end the watch.
  ///
  /// Polling an endpoint that is down forever is how a transient API problem
  /// becomes a permanently silent room; giving up says so instead.
  final int maxConsecutiveProbeFailures;

  /// Called once per live session, when the room is first seen live.
  final void Function(FfmpegLiveRecordingSession session)? onLiveStart;

  /// Called once per live session, when the room is first seen offline after it.
  final void Function(FfmpegLiveRecordingSession session)? onLiveEnd;

  final StreamController<FfmpegLiveRecordingSession> _sessions =
      StreamController<FfmpegLiveRecordingSession>.broadcast();

  StreamSubscription<RecordingState>? _states;
  Timer? _timer;
  Future<void>? _pollInFlight;
  List<FfmpegRecordingOutcome> _recordings = <FfmpegRecordingOutcome>[];
  RecordingSource? _source;
  RecordingConfig? _config;
  DateTime? _liveSince;
  DateTime? _recordingStartedAt;
  String? _title;
  FfmpegLiveRecordingSession? _session;
  int _probeFailures = 0;
  bool _running = false;
  bool _recording = false;
  bool _recheckSoon = false;
  int _rechecksTaken = 0;
  bool _disposed = false;

  /// The room being watched, while one is.
  RecordingSource? get source => _source;

  /// Whether a recording is running right now.
  bool get isRecording => _recording;

  /// The session being watched, or the last completed one.
  FfmpegLiveRecordingSession? get session => _session;

  /// Sessions as they begin, gain a recording, and end.
  Stream<FfmpegLiveRecordingSession> get onSessionChanged => _sessions.stream;

  /// Starts watching [source], and returns after the first status check.
  ///
  /// Whether a recording is running by then answers a different question: a room
  /// that is not live yet is a normal outcome, not a failure.
  Future<void> watch(RecordingSource source, {RecordingConfig config = const RecordingConfig()}) async {
    if (_disposed) {
      throw StateError('FfmpegLiveRecordingWatcher has been disposed.');
    }
    if (_running) {
      throw StateError('This watcher is already watching ${_source?.value ?? 'a room'}.');
    }
    if (!source.isValid) {
      throw ArgumentError.value(source, 'source', 'A watched room needs an address.');
    }

    _running = true;
    _source = source;
    _config = config;
    _recordings = <FfmpegRecordingOutcome>[];
    _probeFailures = 0;
    _recheckSoon = false;
    _rechecksTaken = 0;

    // The recording's own end is the event that matters, and the backend is the
    // only one who sees it: a stream that dies, a stall the watchdog ended, and a
    // user's stop all arrive here as a terminal state.
    _states = _backend.onStateChanged.listen(_onRecordingState);

    await _check();
  }

  /// Stops watching. A recording in progress is ended rather than abandoned.
  ///
  /// The watcher was the only thing that knew the room went away, and a segment
  /// left open behind it is a segment nobody is closing over.
  Future<void> stop() async {
    if (!_running) {
      return;
    }

    _running = false;
    _cancelTimer();

    if (_recording) {
      await _backend.stop();

      // The terminal state reaches this class as a stream event, and a continuation
      // of this method is not guaranteed to be scheduled behind it. Take the state
      // the backend holds now: a session read straight after `stop()` has to say
      // what it recorded. [_onRecordingState] no longer sees a recording by then, so
      // the outcome is recorded once either way.
      final endState = _backend.state;
      if (_recording && endState.status.isTerminal) {
        _finishRecording(endState);
      }
    }

    await _states?.cancel();
    _states = null;
    _endSession();
  }

  /// Releases the watcher for good.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    await stop();
    _disposed = true;
    await _sessions.close();
  }

  /// One poll: ask the room, act, then wait — unless a recording is now running.
  Future<void> _check() async {
    if (!_running || _pollInFlight != null) {
      return;
    }

    final poll = _poll();
    _pollInFlight = poll;

    try {
      await poll;
    } finally {
      _pollInFlight = null;
    }

    if (!_running || _recording) {
      // A running recording owns the next step: [\_onRecordingState] schedules the
      // poll that follows it.
      return;
    }

    _schedule();
  }

  Future<void> _poll() async {
    final source = _source;
    final config = _config;

    if (source == null || config == null || _recording) {
      return;
    }

    final FfmpegLiveRoomStatus status;

    try {
      status = await _statusProbe(source);
      _probeFailures = 0;
    } on Object catch (error) {
      _probeFailures++;
      _lastProbeError = error;

      if (_probeFailures >= maxConsecutiveProbeFailures) {
        _running = false;
        MediaCoreLog.of(LogCategory.recording).error(
          'the room status endpoint kept failing; the watch stopped',
          error: error,
          fields: <String, Object?>{'failures': _probeFailures, 'room': source.value},
        );
      }

      return;
    }

    if (!status.isLive) {
      // The wait shortens only while the restart is plausible; past
      // that, this room is closed and the ordinary interval is the honest one.
      if (_rechecksTaken >= maxAlmostStartRechecks) {
        _recheckSoon = false;
      }

      _endSession();

      return;
    }

    // Found live: what the fast re-check was waiting for.
    _recheckSoon = false;
    _rechecksTaken = 0;

    _title = status.title ?? _title;

    if (_liveSince == null) {
      _liveSince = DateTime.now();
      _recordings = <FfmpegRecordingOutcome>[];
      _announce();
      onLiveStart?.call(_session!);
    }

    final address = status.source;

    try {
      await _backend.start(
        // The room's title travels with the source it records, because that is
        // what the backend names the files after: the address changes per session
        // and a signed URL is not a name anyone can read back.
        RecordingSource(
          type: source.type,
          value: address == null || address.isEmpty ? source.value : address,
          id: source.id,
          title: status.title ?? source.title,
        ),
        config,
      );
      _recording = true;
      _recordingStartedAt = DateTime.now();
    } on Object catch (error) {
      // A start that threw is not a reason to stop watching: the room is live, and
      // the next poll asks again. An almost-start is exactly the case that deserves
      // the short re-check delay.
      _lastProbeError = error;
      _recheckSoon = true;
    }
  }

  Object? _lastProbeError;

  /// Why the last probe or start failed, when one most recently did.
  Object? get lastError => _lastProbeError;

  /// Reacts to the backend's own state, which is where a recording ends.
  void _onRecordingState(RecordingState state) {
    if (!_recording || !state.status.isTerminal) {
      return;
    }

    _finishRecording(state);

    if (!_running) {
      return;
    }

    // The callback cannot await a poll, and the poll handles its own errors: a
    // recording that just ended is no reason to block the stream that reported it.
    unawaited(_check());
  }

  void _finishRecording(RecordingState state) {
    _recording = false;

    final startedAt = _recordingStartedAt ?? DateTime.now();
    final finishedAt = DateTime.now();
    final check = _backend.lastCheck;

    _recordings.add(
      FfmpegRecordingOutcome(
        startedAt: startedAt,
        finishedAt: finishedAt,
        // The backend's verdict, not its exit code: a recording that wrote no
        // segment is a failure even when the state says it finished.
        success: state.status == RecordingStatus.completed && !state.hasError,
        bytesWritten: check?.bytesOnDisk ?? state.bytesWritten,
        segments: check?.segments,
        directory: _backend.activeDirectory,
        error: state.error ?? _failureOf(state, check),
      ),
    );

    _recheckSoon = finishedAt.difference(startedAt) < shortRecordingAfter;
    _rechecksTaken = 0;
    _announce();
  }

  /// The verification's own complaint, when the state carried none.
  ///
  /// A backend that reported `completed` with a journal that lists no segments has
  /// already said so through [FfmpegRecordingBackend.lastCheck], and a scheduler
  /// that ignored that would log a successful recording of nothing.
  Object? _failureOf(RecordingState state, FfmpegRecordingCheck? check) {
    if (check == null || check.isUsable || state.status != RecordingStatus.completed) {
      return null;
    }

    return check;
  }

  void _schedule() {
    _cancelTimer();

    if (!_running) {
      return;
    }

    if (_recheckSoon) {
      _rechecksTaken++;
    }

    final base = _recheckSoon || _probeFailures > 0 ? recheckInterval : pollInterval;

    // `attempt: 1` with a ceiling of 1.5× the interval is the jitter, not a
    // backoff: the interval is what the room's schedule warrants, and the extra
    // up to half again is only so that N rooms do not share a second.
    _timer = Timer(RetryUtils.backoff(1, base: base, max: base * 1.5), () => unawaited(_check()));
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _endSession() {
    if (_liveSince == null) {
      return;
    }

    final finished = _announce(endedAt: DateTime.now());

    _liveSince = null;

    if (finished != null) {
      onLiveEnd?.call(finished);
    }
  }

  FfmpegLiveRecordingSession? _announce({DateTime? endedAt}) {
    if (_liveSince == null) {
      return null;
    }

    final session = FfmpegLiveRecordingSession(
      startedAt: _liveSince!,
      recordings: List<FfmpegRecordingOutcome>.unmodifiable(_recordings),
      endedAt: endedAt,
      title: _title,
    );

    _session = session;

    if (!_sessions.isClosed) {
      _sessions.add(session);
    }

    return session;
  }
}
