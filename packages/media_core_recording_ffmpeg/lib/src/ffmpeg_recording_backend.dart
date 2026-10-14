import 'dart:async';
import 'dart:io';

import 'package:media_core/media_core.dart';
import 'package:media_core_native/media_core_native.dart';

import 'package:media_core_recording_ffmpeg/src/ffmpeg_executor.dart';
import 'package:media_core_recording_ffmpeg/src/ffmpeg_probe.dart';
import 'package:media_core_recording_ffmpeg/src/ffmpeg_record_arguments.dart';
import 'package:media_core_recording_ffmpeg/src/ffmpeg_record_config.dart';
import 'package:media_core_recording_ffmpeg/src/output_path.dart';
import 'package:media_core_recording_ffmpeg/src/recording_manifest.dart';
import 'package:media_core_recording_ffmpeg/src/recording_recovery.dart';
import 'package:media_core_recording_ffmpeg/src/recording_remuxer.dart';
import 'package:media_core_recording_ffmpeg/src/recording_verification.dart';

/// Decision trail for a recording.
///
/// The argument list is logged at debug because an FFmpeg failure is usually a
/// statement about the arguments, and the exit code alone ("255") says nothing.
/// The list is what a developer pastes into a shell to reproduce it.
final LogModule _log = MediaCoreLog.of(LogCategory.recording);

/// Ledger of the running recording.
///
/// Reported in measured bytes: FFmpeg's statistics say how much has been written,
/// so a recording in progress shows up in a memory report as a real number —
/// which is what makes it possible to tell a recording that is writing a lot
/// from a queue that is holding a lot.
final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.recording);

/// What the caller asked for when a recording ended.
///
/// FFmpeg reports `255` both for a stream that died and for a process that was
/// killed on purpose, so the exit code alone cannot say whether a recording
/// succeeded. The intent is tracked here and decides how the end is reported.
///
/// [stall] is the backend asking for its own end: the watchdog found an input
/// that stopped advancing, and the process has to be replaced rather than
/// waited on. Like [none] it is recoverable, unlike [none] it says why.
enum _StopIntent { none, stop, cancel, stall }

/// Records network streams with FFmpeg.
///
/// Responsibilities:
///
/// - build the FFmpeg argument list for a source and configuration
/// - own the process: start it, observe progress, end it
/// - map process outcomes onto the recording contract's states and results
///
/// It does not:
///
/// - choose what to record (the host does)
/// - manage several recordings or queue them (the core `RecordingManager` does)
/// - join segments into a single file (a separate step; the journal is written
///   for whoever does it)
///
/// ## Segmented output, on purpose
///
/// The capture writes MPEG-TS segments plus a CSV journal rather than one growing
/// file. A live recording has no natural end: if the process dies, or the phone
/// kills the app, a single file is usually unplayable because its index was
/// never written. Segments are playable individually, and the journal says how
/// they join — so the worst case is "a few seconds lost", not "hours lost".
///
/// ## Intent, not exit code
///
/// A user-requested stop is a **successful** recording: the file exists and is
/// playable. The same exit code from a crashed input is an error. The backend
/// therefore tracks why it ended the process instead of inferring it from the
/// code, and reports [RecordingResult.success] accordingly.
///
/// ## A result is a file, not a process
///
/// Intent settles *why* the process ended; it says nothing about whether
/// anything was captured. An FFmpeg that is killed after opening a bad URL exits
/// like any other killed process, and a `success: true` on an empty directory is
/// a recording the user has to discover is missing. So before [stop] reports, the
/// journal is read back and the segments it names are checked — sized on disk,
/// and opened by FFprobe when a [FfmpegProbe] is in use
/// (`config.verifyOutput`). The byte total reported is
/// then the one measured from those files, not the muxer's own counter, which for
/// a segmented capture describes the child file being written rather than the
/// recording so far.
///
/// ## A dropped stream is a source problem, not a session problem
///
/// A live recording's input dies on its own — a CDN rotates, a room's encoder
/// restarts, a signature expires — and FFmpeg leaves with `255`, the same code a
/// user's stop produces. The backend treats an end nobody asked for as the
/// source's failure and re-opens it: with a jittered backoff
/// ([FfmpegRecordConfig.restartBackoff], capped at `restartBackoffMax`), up to
/// [FfmpegRecordConfig.restartLimit] consecutive attempts that never reached
/// [FfmpegRecordConfig.healthyAfter], and through `urlRefresher` when the host
/// can mint a new URL. Each attempt gets its own segment files and its own
/// journal, so nothing is overwritten and the whole recording is the list of
/// them in order. A run that lasted is not counted against the limit: a stream
/// that drops once an hour and recovers every time is a recording, not a failing
/// one.
///
/// Two things the re-open cannot fix are watched separately. A stalled input
/// (bytes arriving, or nothing arriving, with no media time advancing) trips
/// [FfmpegRecordConfig.stallTimeout] and is ended by the backend so recovery
/// runs at all — FFmpeg's own read timeout does not cover it. And a directory
/// that is out of space is refused before the first segment
/// ([FfmpegRecordConfig.diskWatermarkBytes] with a `diskSpace` probe) rather than
/// reported afterwards as an exit code.
final class FfmpegRecordingBackend implements RecordingBackend {
  /// Creates the backend.
  ///
  /// [executor] defaults to the FFmpegKit implementation; pass a fake in tests.
  /// [outputDirectory] is the default location for recordings, overridable per
  /// start through `RecordingConfig.outputPath`. [probe] defaults to the
  /// plugin's own FFprobe and is used only when
  /// [FfmpegRecordConfig.verifyPlayability] is on.
  ///
  /// [urlRefresher] is asked for a new address every time the source has to be
  /// re-opened. It exists because a live room's URL is usually signed and
  /// expiring: the address that was right when the user pressed record is wrong
  /// by the next segment, and only the host can get a fresh one. Null keeps
  /// re-opening the address it was given, which is the right thing for a stream
  /// whose URL does not expire and the wrong thing for one whose does — a
  /// non-refreshing restart of an expired URL is a backoff loop that always
  /// fails.
  ///
  /// [diskSpace] reports bytes free in the output directory. Null skips the
  /// check (see [FfmpegRecordConfig.diskWatermarkBytes] for why there is no
  /// default).
  FfmpegRecordingBackend({
    FfmpegExecutor? executor,
    this.config = FfmpegRecordConfig.defaults,
    this.outputDirectory,
    BackgroundExecutionStarter? keepAliveStarter,
    FfmpegProbe? probe,
    UrlRefresher? urlRefresher,
    DiskSpaceProbe? diskSpace,
  }) : _executor = executor,
       _keepAliveStarter = keepAliveStarter ?? BackgroundExecution.acquire,
       _probe = probe,
       _urlRefresher = urlRefresher,
       _diskSpace = diskSpace;

  /// This instance's key in the shared account: a module can have several
  /// live instances, and a report sums their contributions rather than
  /// keeping whichever reported last.
  late final String _memoryKey = memoryContributorKey(this);

  /// Recording tunables.
  final FfmpegRecordConfig config;

  FfmpegExecutor? _executor;

  /// Default directory a recording is written to when `RecordingConfig.outputPath`
  /// does not name one. Changeable, because a host decides it after the backend
  /// exists - the storage path is usually not known when the player is built.
  String? outputDirectory;
  final BackgroundExecutionStarter _keepAliveStarter;
  final FfmpegProbe? _probe;
  final UrlRefresher? _urlRefresher;
  final DiskSpaceProbe? _diskSpace;

  /// The session holding this recording's process alive, if any.
  BackgroundExecutionLease? _keepAlive;

  /// What the notification says, without the moving parts: the title, icon and
  /// kind the host chose, kept so an update can replace only the second line.
  BackgroundNotification? _keepAliveNotification;

  /// Media time of the last notification update, so FFmpeg's twice-a-second
  /// statistics do not become twice-a-second notification replacements.
  Duration _notifiedAt = Duration.zero;

  /// File prefix of the running recording, for the notification's second line.
  String _activePrefix = '';

  final StreamController<RecordingState> _stateController = StreamController<RecordingState>.broadcast();

  /// Segments the running recording has closed, announced as they appear.
  final StreamController<FfmpegJournalledSegment> _segmentController =
      StreamController<FfmpegJournalledSegment>.broadcast();

  Timer? _journalWatcher;

  /// Segments already announced for the current attempt.
  ///
  /// Counted per attempt rather than per recording, because each attempt has its
  /// own journal starting again at segment zero.
  int _reportedSegments = 0;

  RecordingState _state = const RecordingState();
  FfmpegExecution? _execution;
  _StopIntent _intent = _StopIntent.none;
  StreamSubscription<int>? _exitWatcher;
  late RecordingSource _activeSource;
  String? _activeDirectory;

  /// The sanitised prefix this recording was started with, reused by every
  /// re-opened attempt so one recording's files stay one family.
  String _basePrefix = '';

  /// What the recording that last ran wrote, kept so a host can find its files
  /// again without re-deriving the naming rules.
  FfmpegRecordingManifest? _lastManifest;

  /// Wall-clock start of the running recording, kept because the manifest has to
  /// say when the first attempt began, not when the current one did.
  DateTime? _startedAt;

  /// Journals of every attempt of the running recording, oldest first.
  ///
  /// A restart writes new files rather than continuing the old ones — FFmpeg's
  /// `-n` refuses an existing output on purpose — so the recording as a whole is
  /// this list, and the final verdict is read over all of it.
  final List<String> _journalPaths = <String>[];

  /// Whether this recording's outcome has been handed to `MediaJobReporting`.
  ///
  /// A recording that ended on its own and was then stopped by a host reaches both
  /// terminal paths once; the viewer should get one line, not two.
  bool _outcomeReported = false;

  Timer? _stallWatchdog;

  /// Checks of the watchdog that saw no progress, and the period they are taken at.
  ///
  /// The count, not the clock: a timer is the only clock that behaves the same
  /// under a host's test zone and on a device, and the window is what the count
  /// is multiplied by.
  int _stallTicks = 0;
  Duration _stallInterval = Duration.zero;
  Duration _recordedMediaTime = Duration.zero;
  bool _attemptSettled = true;
  int _consecutiveQuickFailures = 0;
  FfmpegRecordingCheck? _lastCheck;
  Duration _lastMediaTime = Duration.zero;
  int _lastBytes = 0;
  bool _disposed = false;

  /// Current state.
  @override
  RecordingState get state => _state;

  /// State changes.
  Stream<RecordingState> get onStateChanged => _stateController.stream;

  /// A segment as the recording finishes writing it.
  ///
  /// The one signal FFmpeg will not give: it closes a segment mid-process and
  /// keeps going, and the only evidence a host gets is the name appearing in the
  /// list the muxer rewrites — so this is a poll of that list, not a callback.
  /// A host that wants to show progress by files, upload a finished part while the
  /// next is being written, or delete a segment it has already re-muxed subscribes
  /// here.
  ///
  /// The segment a recording ends on is never announced: it was still open when the
  /// process stopped, so the list does not name it. That one only shows up in the
  /// final [lastCheck], which is the honest end of the sequence.
  Stream<FfmpegJournalledSegment> get onSegmentClosed => _segmentController.stream;

  /// How many segments of the current attempt have been announced.
  int get segmentsClosed => _reportedSegments;

  /// Whether this backend can record right now.
  ///
  /// True as soon as it exists: the native FFmpeg loads lazily on the first
  /// start, and reporting "unavailable" until an explicit initialization would
  /// make a host gate its record button on a step the user does not care about.
  @override
  bool get isAvailable => !_disposed;

  /// Output directory the last recording was written to.
  String? get activeDirectory => _activeDirectory;

  /// How the last finished recording's output was judged.
  ///
  /// Null for a recording that has not ended, and for one ended while
  /// [FfmpegRecordConfig.verifyOutput] was off. A host that needs more than the
  /// core's `RecordingResult` — segment counts, which parts are missing — reads
  /// this instead of the directory.
  FfmpegRecordingCheck? get lastCheck => _lastCheck;

  /// Warms the native FFmpeg up.
  Future<void> initialize() async {
    _ensureNotDisposed();
    await _executorOf().initialize();
  }

  @override
  Future<void> start(RecordingSource source, RecordingConfig config) async {
    _ensureNotDisposed();
    // The state, not just the process: a recording that is between attempts has
    // no process running and is still very much a recording.
    if (_execution != null || _state.status.isActive) {
      throw StateError('A recording is already running.');
    }
    if (!source.isValid) {
      throw ArgumentError.value(source, 'source', 'Recording source is empty.');
    }
    if (source.type == RecordingSourceType.file) {
      throw UnsupportedError('FFmpeg recording captures network sources; a local file is already recorded.');
    }

    final directory = config.outputPath ?? outputDirectory;
    if (directory == null || StringUtils.isBlank(directory)) {
      throw StateError('No recording directory configured. Set one on the backend or in RecordingConfig.outputPath.');
    }

    // The prefix is resolved once, here: a re-opened attempt that recomputed a
    // timestamp prefix would scatter one recording's files over several names and
    // drop the first attempt's journal out of the verdict.
    // `config` here is the core's RecordingConfig (the per-start overrides), so the
    // tunables are read from the field.
    final prefix = FfmpegRecordArguments.filePrefixFor(this.config);
    final recordingDirectory = this.config.subdirectoryPerRecording ? joinOutputPath(directory, prefix) : directory;

    // A fresh state, not a copy: `copyWith` cannot clear an error from a
    // previous attempt, and a stale error would make a running recording look
    // failed.
    _emit(const RecordingState(status: RecordingStatus.starting));

    _activeSource = source;
    _activeDirectory = recordingDirectory;
    _basePrefix = prefix;
    _startedAt = DateTime.now();
    _journalPaths.clear();
    _outcomeReported = false;
    _recordedMediaTime = Duration.zero;
    _consecutiveQuickFailures = 0;
    _lastCheck = null;
    _intent = _StopIntent.none;

    try {
      await Directory(recordingDirectory).create(recursive: true);
      // The volume is asked before anything is written. A disk that is full
      // accepts the directory, takes the first megabytes, and then fails in the
      // middle of a segment with an exit code that says nothing about space.
      await _refuseIfNoRoom(recordingDirectory);
      await _launch(source.value);
    } catch (error, stackTrace) {
      await _releaseKeepAlive();
      _log.error('could not start the recording', error: error, fields: <String, Object?>{'url': source.value});
      _emit(_state.copyWith(status: RecordingStatus.error, error: error));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Opens one FFmpeg process for the running recording and starts watching it.
  ///
  /// Every attempt builds its own argument list, journal and segment names: the
  /// address may have been refreshed since the last process, and `-n` means a
  /// restart that reused the first attempt's files would refuse to run — or, if
  /// it did not, would overwrite the list that says where the earlier segments
  /// are. Attempt 0 keeps the plain names, so a recording that never dropped a
  /// stream is named exactly as it was before re-opening existed.
  Future<void> _launch(String url) async {
    if (_intent == _StopIntent.stop || _intent == _StopIntent.cancel) {
      throw StateError('The recording was ended while its source was being re-opened.');
    }

    final directory = _activeDirectory!;
    final attempt = _journalPaths.length;
    final prefix = attempt == 0 ? _basePrefix : '${_basePrefix}_r$attempt';
    final segmentPattern = '${prefix}_%06d${config.resolvedSegmentSuffix}';
    final journalPath = joinOutputPath(directory, '$prefix${config.journalSuffix}');
    final arguments = FfmpegRecordArguments(config: config).recordArguments(
      url: url,
      outputDirectory: directory,
      segmentPattern: segmentPattern,
      journalPath: journalPath,
      filePrefix: prefix,
    );

    _journalPaths.add(journalPath);
    _writeManifest();
    _lastMediaTime = Duration.zero;
    _lastBytes = 0;
    _attemptSettled = false;
    _stallTicks = 0;
    _reportedSegments = 0;

    _log
      ..info(
        attempt == 0 ? 'starting a recording' : 're-opening the source',
        fields: <String, Object?>{
          'url': url,
          'directory': directory,
          'segmentPattern': segmentPattern,
          'attempt': attempt,
        },
      )
      ..debug('ffmpeg arguments', fields: <String, Object?>{'argv': arguments.join(' ')});

    if (attempt == 0) {
      // The lease is taken before the process exists. The wake lock must not
      // begin a moment after the recording does, and with nothing running yet
      // there is no process to unwind when a platform refuses or throws.
      await _acquireKeepAlive(prefix);
    }

    // The previous attempt's watcher has already delivered its one exit value;
    // leaving it subscribed would keep a closed subscription alive for the rest
    // of the session.
    await _exitWatcher?.cancel();

    final execution = await _executorOf().start(arguments: arguments, onStatistics: _handleStatistics);
    _execution = execution;
    _emit(_state.copyWith(status: RecordingStatus.recording));
    _log.info(
      'recording started',
      fields: <String, Object?>{'session': identityHashCode(execution), 'attempt': attempt},
    );
    _exitWatcher = execution.exitCode.asStream().listen(_handleExit);
    _armStallWatchdog();
    _armJournalWatcher();
  }

  /// Writes the manifest that says what this recording is.
  ///
  /// Rewritten on every attempt rather than appended: the file is the current
  /// truth about a recording in progress, and a reader that found a stale copy
  /// (two journals where the file lists one) would be worse off than one that
  /// found none. A failure to write it is logged, never fatal — the segments are
  /// the recording, and stopping a recording because a sidecar would not land
  /// trades the user's data for metadata.
  void _writeManifest() {
    if (!config.writeManifest) {
      return;
    }

    final directory = _activeDirectory;
    final startedAt = _startedAt;

    if (directory == null || startedAt == null) {
      return;
    }

    final manifest = FfmpegRecordingManifest(
      prefix: _basePrefix,
      container: config.container,
      segmentTime: config.segmentTime,
      startedAt: startedAt,
      sourceLabel: recordingSourceLabel(_activeSource),
      journals: List<String>.unmodifiable(_journalPaths),
      attempts: _journalPaths.length,
    );

    try {
      File(joinOutputPath(directory, recordingManifestName(_basePrefix))).writeAsStringSync(manifest.toJson());
      _lastManifest = manifest;
    } on Object catch (error) {
      _log.warning(
        'the recording manifest could not be written',
        error: error,
        fields: <String, Object?>{'directory': directory},
      );
    }
  }

  /// Throws when the output volume is below the watermark.
  ///
  /// A probe that cannot answer is not a refusal: the recording is the thing the
  /// user asked for, and FFmpeg's own write failure is still a report.
  Future<void> _refuseIfNoRoom(String directory) async {
    final probe = _diskSpace;

    if (probe == null) {
      return;
    }

    final free = await probe(directory);

    if (free != null && free < config.diskWatermarkBytes) {
      throw FfmpegRecordingDiskFullException(
        directory: directory,
        freeBytes: free,
        watermarkBytes: config.diskWatermarkBytes,
      );
    }
  }

  @override
  Future<RecordingResult> stop() async {
    _ensureNotDisposed();
    if (_journalPaths.isEmpty) {
      return RecordingResult(success: false, outputPath: _activeDirectory, error: StateError('No recording to stop.'));
    }

    // The intent must be set before the process ends, or the exit watcher sees
    // an unexplained 255 and reports an error for a recording the user ended.
    _intent = _StopIntent.stop;
    _cancelStallWatchdog();

    // A stop that lands while the source is being re-opened has no process to
    // end: the recording is then whatever the earlier attempts wrote, and that
    // is still a recording the user asked to stop.
    final execution = _execution;
    int? exitCode;

    if (execution != null) {
      _log.info('stopping the recording', fields: <String, Object?>{'session': identityHashCode(execution)});
      _emit(_state.copyWith(status: RecordingStatus.stopping));
      await execution.stop();
      exitCode = await _awaitExit(execution);
    }

    _settleAttempt();
    // One last read: the segment closed in the final moments belongs
    // to the sequence, and a host counting files would otherwise be one short.
    _checkJournalGrowth();
    _cancelJournalWatcher();
    await _releaseKeepAlive();

    final check = await _verifyOutput(exitCode: exitCode);
    final failure = _failureOf(check, exitCode: exitCode, endingWasAskedFor: true);
    // Measured, not reported: for a segmented capture the statistics figure
    // describes the muxer's own counter, and the recording is the segments.
    final bytesWritten = check?.bytesOnDisk ?? _lastBytes;

    _log.info(
      'recording stopped',
      fields: <String, Object?>{
        'directory': _activeDirectory,
        'durationMs': _recordedMediaTime.inMilliseconds,
        'bytesWritten': bytesWritten,
        'exitCode': exitCode,
        'attempts': _journalPaths.length,
        'segments': check?.segments,
        'verdict': check?.verdict.name,
        if (check?.reason case final String reason) 'output': reason,
      },
    );

    _emit(
      _state.copyWith(
        status: failure == null ? RecordingStatus.completed : RecordingStatus.error,
        duration: _recordedMediaTime,
        bytesWritten: bytesWritten,
        error: failure,
      ),
    );

    _reportOutcome(success: failure == null, bytesWritten: bytesWritten, error: failure);

    return RecordingResult(
      success: failure == null,
      outputPath: _activeDirectory,
      duration: _recordedMediaTime,
      bytesWritten: bytesWritten,
      error: failure,
    );
  }

  /// Hands this recording's verdict to the notification layer, at most once.
  ///
  /// The label is the prefix the files carry rather than the address: a signed
  /// live URL's query is a credential, and the name on the files is the thing the
  /// viewer recognises. A recording that ended on its own and was then stopped
  /// reaches both terminal paths, and one line is the honest answer.
  void _reportOutcome({required bool success, required int bytesWritten, Object? error}) {
    if (_outcomeReported) {
      return;
    }

    _outcomeReported = true;

    MediaJobReporting.reporter?.report(
      MediaJobOutcome(
        kind: MediaJobKind.recording,
        label: _basePrefix.isEmpty ? 'recording' : _basePrefix,
        success: success,
        bytesWritten: bytesWritten,
        elapsed: _recordedMediaTime,
        error: error,
      ),
    );
  }

  @override
  Future<void> cancel() async {
    _ensureNotDisposed();
    if (_journalPaths.isEmpty) {
      return;
    }

    final execution = _execution;

    _log.info('cancelling the recording', fields: <String, Object?>{'session': identityHashCode(execution)});
    // Set before anything is ended, and re-read when a re-opening delay wakes:
    // this is what keeps a cancelled recording from being started again.
    _intent = _StopIntent.cancel;
    _cancelStallWatchdog();
    _cancelJournalWatcher();
    _settleAttempt();

    if (execution != null) {
      await execution.cancel();
      await _awaitExit(execution);
    }

    await _releaseKeepAlive();
    _emit(_state.copyWith(status: RecordingStatus.cancelled));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    // Set before the process is looked for: a recording that is between
    // attempts has none, and it is the pending delay that must not start one.
    _intent = _StopIntent.cancel;
    _cancelStallWatchdog();
    _cancelJournalWatcher();

    final execution = _execution;
    if (execution != null) {
      await execution.cancel();
      await _awaitExit(execution);
    }

    await _releaseKeepAlive();

    _disposed = true;
    _memory.withdraw(_memoryKey);
    await _exitWatcher?.cancel();
    _exitWatcher = null;
    await _segmentController.close();
    await _executor?.dispose();
    await _stateController.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  FfmpegExecutor _executorOf() => _executor ??= FfmpegKitExecutor();

  /// The probe used to open a segment before claiming it is playable.
  ///
  /// Defaults to the plugin's FFprobe, which is the same native library the
  /// recording just ran on; a host that cannot afford the call passes one that
  /// answers null, or switches [FfmpegRecordConfig.verifyPlayability] off.
  FfmpegProbe _probeOf() => _probe ?? const FFprobeKitFfmpegProbe();

  /// Holds the process alive for as long as this recording runs.
  ///
  /// A platform that refuses (no implementation, or no permission to run the
  /// service at all) leaves the recording unprotected rather than failing it:
  /// the user asked for a recording, not for a notification. A declined
  /// <em>notification</em> is not even that: the session is still held and only
  /// the notification stays hidden.
  Future<void> _acquireKeepAlive(String prefix) async {
    _activePrefix = prefix;
    _notifiedAt = Duration.zero;

    if (!config.keepAlive) {
      return;
    }

    final notification = BackgroundNotification(
      title: config.keepAliveTitle ?? 'Recording',
      text: prefix,
      kind: BackgroundJobKind.record,
      icon: config.keepAliveIcon,
      // A live recording has no total, so the honest shape is a spinner; the
      // numbers the user can act on go in the text, one update per second.
      progress: const BackgroundProgress.indeterminate(),
    );

    final session = await _keepAliveStarter(notification: notification, wakeLock: true);

    _keepAlive = session;
    _keepAliveNotification = session == null ? null : notification;

    if (session == null) {
      _log.debug('no background execution on this platform; the recording is unprotected');
    } else {
      _log.info('background execution held', fields: <String, Object?>{'session': session.id});
    }
  }

  /// Keeps the notification's second line moving: what is being written, how
  /// long it has been running, how much has landed.
  ///
  /// Throttled by media time rather than wall clock, because that is the clock
  /// FFmpeg reports on and the one a user compares the number against.
  void _updateKeepAlive() {
    final session = _keepAlive;
    final notification = _keepAliveNotification;

    if (session == null || notification == null) {
      return;
    }

    // A live source can restart its timeline inside one process (a re-open after
    // a dropout reports a smaller `out_time_ms` than the last one). Below the
    // last notified point the window arithmetic reads "not yet due" forever, and
    // the line would freeze for the rest of the recording - so a backwards jump
    // re-opens the window instead of waiting it out.
    if (_lastMediaTime < _notifiedAt) {
      _notifiedAt = Duration.zero;
    }

    if (_lastMediaTime - _notifiedAt < const Duration(seconds: 1)) {
      return;
    }

    _notifiedAt = _lastMediaTime;

    final parts = <String>[
      _activePrefix,
      _formatDuration(_totalMediaTime),
      if (_formatBytes(_lastBytes) case final String bytes) bytes,
    ];

    unawaited(session.update(notification.copyWith(text: parts.join(' · '))));
  }

  /// `00:12:34` — fixed width, so the line does not jump as it counts.
  static String _formatDuration(Duration duration) {
    String pad(int value) => value.toString().padLeft(2, '0');

    return '${pad(duration.inHours)}:${pad(duration.inMinutes % 60)}:${pad(duration.inSeconds % 60)}';
  }

  /// Bytes written, or null before anything has landed.
  static String? _formatBytes(int bytes) {
    if (bytes <= 0) {
      return null;
    }

    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _releaseKeepAlive() async {
    final session = _keepAlive;

    _keepAlive = null;
    _keepAliveNotification = null;

    await session?.release();
  }

  void _handleStatistics(FfmpegStatistics statistics) {
    if (_disposed) {
      return;
    }
    // The watchdog counts silence between *advances*, not between reports: a
    // stalled input keeps sending statistics that repeat the last figures, and a
    // timer reset by those would never fire.
    if (statistics.timeMs > _lastMediaTime.inMilliseconds || statistics.sizeBytes > _lastBytes) {
      _stallTicks = 0;
    }
    _lastMediaTime = Duration(milliseconds: statistics.timeMs);
    _lastBytes = statistics.sizeBytes;
    _memory.report(_memoryKey, items: 1, bytes: _lastBytes, note: 'recording, ${_totalMediaTime.inSeconds}s written');
    if (_state.status != RecordingStatus.recording) {
      return;
    }
    _emit(_state.copyWith(duration: _totalMediaTime, bytesWritten: _lastBytes));
    _updateKeepAlive();
  }

  /// How many FFmpeg processes this recording has run.
  int get attempts => _journalPaths.length;

  /// What the recording that last ran wrote, as its own manifest says.
  ///
  /// Null before anything has run. It outlives the process on purpose: the question a
  /// host asks after a recording is where its files are, and that question is asked
  /// long after FFmpeg has gone.
  FfmpegRecordingManifest? get lastManifest => _lastManifest;

  /// Joins the last recording's segments into one file.
  ///
  /// Deliberately not part of [stop]: merging six hours of segments costs real time,
  /// and a phone must stay free to start the next recording while this one is tidied.
  /// A failed join reports itself and never touches the segments, which already are the
  /// recording. See [FfmpegRecordingRemuxer] for what the join reads and when it skips.
  Future<FfmpegRemuxResult> combineLastRecording({FfmpegRemuxTarget target = FfmpegRemuxTarget.mp4}) {
    final directory = _activeDirectory;
    final manifest = _lastManifest;

    if (directory == null || manifest == null) {
      return Future<FfmpegRemuxResult>.value(
        const FfmpegRemuxResult.failed(
          outputPath: '',
          error: FfmpegRemuxException('no recording has run on this backend yet'),
        ),
      );
    }

    return FfmpegRecordingRemuxer(
      executor: _executor,
      probe: _probe,
    ).run(manifest: manifest, directory: directory, target: target);
  }

  /// Adds the ended process's media time to the recording's total.
  ///
  /// Every FFmpeg run counts its own timeline from zero, so a recording whose
  /// source was re-opened five times is the sum of its runs; reporting the last
  /// run's clock would say a two-hour recording lasted four minutes.
  Duration _settleAttempt() {
    if (_attemptSettled) {
      return Duration.zero;
    }

    _attemptSettled = true;
    _recordedMediaTime += _lastMediaTime;

    return _lastMediaTime;
  }

  /// Media time across every attempt, including the one still running.
  Duration get _totalMediaTime => _recordedMediaTime + _lastMediaTime;

  /// Reacts to a process that ended.
  ///
  /// [stop] and [cancel] set the intent before ending the process and await the
  /// same future, so their outcome is already decided by the time this runs.
  /// Everything else - a source that died, an input the watchdog gave up on - is
  /// decided by [_recover].
  void _handleExit(int? code) {
    if (_disposed) {
      return;
    }

    final intent = _intent;

    _execution = null;
    _cancelStallWatchdog();
    _memory.withdraw(_memoryKey);

    if (intent == _StopIntent.stop || intent == _StopIntent.cancel) {
      return;
    }

    // The stall was the backend's own doing, and recovery starts a process that
    // has no decision attached to it yet - leaving the intent set would make the
    // loop below read the next end as another stall of the same one.
    _intent = _StopIntent.none;

    // The keep-alive is *not* released here: a recording that is between
    // attempts still holds the job the user asked for, and a wake lock that came
    // and went with each drop would let the phone freeze the process in exactly
    // the window where it is most fragile.
    unawaited(_recover(code, ended: _settleAttempt(), stalled: intent == _StopIntent.stall));
  }

  /// Brings the recording back after a process that ended on its own.
  ///
  /// Returns as soon as a process is running again: the next ending re-enters
  /// here with its own code, so a day of drops is a day of short recoveries
  /// instead of one long loop holding state.
  ///
  /// A run that reached [FfmpegRecordConfig.healthyAfter] is a source that works
  /// and dropped, and does not count against [FfmpegRecordConfig.restartLimit];
  /// what counts is a failure that never got going, because that is the shape of
  /// an address that expired - re-opening one is a retry that cannot succeed.
  Future<void> _recover(int? exitCode, {required Duration ended, required bool stalled}) async {
    var code = exitCode;
    var lastEnded = ended;
    var cause = stalled
        ? 'the input advanced nothing for ${config.stallTimeout.inSeconds}s'
        : 'the source ended (exit code $code)';

    while (!_disposed && _intent == _StopIntent.none) {
      if (code == 0 && !stalled) {
        // The input ran out on its own terms - a playlist that reached its end.
        // Nothing is broken, so nothing is re-opened.
        await _finish(exitCode: code);

        return;
      }

      if (lastEnded >= config.healthyAfter) {
        _consecutiveQuickFailures = 0;
      } else {
        _consecutiveQuickFailures++;
      }

      if (config.restartLimit <= 0 || _consecutiveQuickFailures > config.restartLimit) {
        await _finish(cause: cause, exitCode: code);

        return;
      }

      final delay = RetryUtils.backoff(
        _consecutiveQuickFailures,
        base: config.restartBackoff,
        max: config.restartBackoffMax,
      );

      _log.warning(
        'the recording source ended; re-opening it',
        fields: <String, Object?>{
          'reason': cause,
          'delayMs': delay.inMilliseconds,
          'attempt': _journalPaths.length,
          'exitCode': code,
        },
      );

      await Future<void>.delayed(delay);

      if (_disposed || _intent != _StopIntent.none) {
        // The user decided while this was waiting; their outcome is the one
        // already reported.
        return;
      }

      try {
        await _relaunch();

        return;
      } on Object catch (error) {
        if (_intent != _StopIntent.none || error is FfmpegRecordingDiskFullException) {
          await _finish(cause: error.toString(), exitCode: code);

          return;
        }

        // A re-opening that never started produces no exit code, so this pass is
        // the only record of it - counting it as a quick failure is what bounds
        // the loop.
        cause = error.toString();
        lastEnded = Duration.zero;
        code = null;
      }
    }
  }

  /// Re-opens the source with a fresh address where the host can supply one.
  Future<void> _relaunch() async {
    final source = _activeSource;
    var url = source.value;

    final refresher = _urlRefresher;

    if (refresher != null) {
      final refreshed = await refresher(source);

      if (refreshed == null || StringUtils.isBlank(refreshed)) {
        throw StateError('The stream address could not be refreshed for ${source.id ?? source.value}.');
      }

      url = refreshed;
    }

    await _refuseIfNoRoom(_activeDirectory!);
    await _launch(url);
  }

  /// Reports a recording that ended without the user asking it to.
  ///
  /// A null [cause] is the clean case: the input finished. Anything else is the
  /// recording stopping early, and the segments it did write are reported as what
  /// was kept rather than as a recording.
  Future<void> _finish({String? cause, int? exitCode}) async {
    _cancelStallWatchdog();
    await _releaseKeepAlive();

    final check = await _verifyOutput(exitCode: exitCode);

    if (_disposed) {
      return;
    }

    final bytesWritten = check?.bytesOnDisk ?? _lastBytes;
    final failure = cause == null
        // A zero exit code says the process finished its work; whether there is
        // anything to show for it is the journal's answer, not the process's.
        ? _failureOf(check, exitCode: exitCode, endingWasAskedFor: false)
        : FfmpegRecordingGaveUpException(
            cause: '$cause; ${check?.segments ?? 0} segment(s), ${check?.bytesOnDisk ?? 0}B kept',
            attempts: _journalPaths.length,
            exitCode: exitCode,
          );

    if (failure == null) {
      _log.info(
        'recording finished on its own',
        fields: <String, Object?>{
          'exitCode': exitCode,
          'durationMs': _recordedMediaTime.inMilliseconds,
          'attempts': _journalPaths.length,
          'segments': check?.segments,
        },
      );
    } else {
      _log.error(
        'recording ended with a failure',
        fields: <String, Object?>{
          'exitCode': exitCode,
          'durationMs': _recordedMediaTime.inMilliseconds,
          'bytesWritten': bytesWritten,
          'output': failure.toString(),
        },
      );
    }

    _emit(
      RecordingState(
        status: failure == null ? RecordingStatus.completed : RecordingStatus.error,
        duration: _recordedMediaTime,
        bytesWritten: bytesWritten,
        error: failure,
      ),
    );

    _reportOutcome(success: failure == null, bytesWritten: bytesWritten, error: failure);
  }

  /// Starts watching one process for an input that stopped advancing.
  ///
  /// `-rw_timeout` bounds a read that never returns, and this bounds what it
  /// cannot see: bytes arriving with no media time behind them - a playlist
  /// refreshing without a new segment, a connection kept alive by nothing. The
  /// window is checked four times over, floored at 200 ms so a long window does
  /// not cost a timer every few milliseconds and a short one still notices.
  void _armStallWatchdog() {
    _cancelStallWatchdog();

    if (config.stallTimeout <= Duration.zero) {
      return;
    }

    final interval = Duration(
      microseconds: (config.stallTimeout.inMicroseconds ~/ 4).clamp(
        const Duration(milliseconds: 200).inMicroseconds,
        const Duration(seconds: 10).inMicroseconds,
      ),
    );

    _stallInterval = interval;
    _stallWatchdog = Timer.periodic(interval, (_) => _checkForStall());
  }

  /// Starts watching the current attempt's journal for segments it has closed.
  ///
  /// Once a second, because that is the fastest a host can use the information and
  /// the cheapest thing this can be: the file is a few kilobytes of names, and a
  /// segment is on the order of minutes. A fraction of a second would wake the CPU
  /// for no news.
  void _armJournalWatcher() {
    _cancelJournalWatcher();
    _journalWatcher = Timer.periodic(const Duration(seconds: 1), (_) => _checkJournalGrowth());
  }

  void _cancelJournalWatcher() {
    _journalWatcher?.cancel();
    _journalWatcher = null;
  }

  /// Announces the segments the journal has gained since the last look.
  void _checkJournalGrowth() {
    if (_disposed || _journalPaths.isEmpty || _segmentController.isClosed) {
      return;
    }

    final FfmpegSegmentJournal journal;

    try {
      journal = FfmpegSegmentJournal.fromFile(File(_journalPaths.last));
    } on Object {
      // A journal that cannot be read is a journal with no news; the next poll
      // tries again, and the final verification says what really happened.
      return;
    }

    for (var index = _reportedSegments; index < journal.length; index++) {
      final entry = journal.entries[index];

      _reportedSegments = index + 1;
      _segmentController.add(entry);

      _log.debug(
        'segment closed',
        fields: <String, Object?>{'segment': entry.index, 'name': entry.name, 'bytes': entry.bytes},
      );
    }
  }

  void _cancelStallWatchdog() {
    _stallWatchdog?.cancel();
    _stallWatchdog = null;
  }

  void _checkForStall() {
    final execution = _execution;

    if (_disposed || execution == null || _intent != _StopIntent.none) {
      return;
    }

    _stallTicks++;

    if (_stallInterval * _stallTicks < config.stallTimeout) {
      return;
    }

    // Ending it is the only option left: an input that is not advancing will not
    // start advancing, and the process holding the segment open is what blocks
    // the re-opening that would get a working one.
    _intent = _StopIntent.stall;

    _log.warning(
      'the input stopped advancing',
      fields: <String, Object?>{'silentFor': config.stallTimeout.inSeconds, 'session': identityHashCode(execution)},
    );
    unawaited(execution.cancel());
  }

  Future<int?> _awaitExit(FfmpegExecution execution) async {
    try {
      return await execution.exitCode;
    } on Object catch (_) {
      // A process that cannot be reaped is still gone; the caller's intent
      // already decided the outcome.
      return null;
    } finally {
      if (identical(_execution, execution)) {
        _execution = null;
      }
    }
  }

  /// Reads the recording back from what it left on disk.
  ///
  /// Null means *no judgement was made*: the check is switched off, or the
  /// journal could not be read. Both leave the caller to report on the exit code
  /// alone, because a failure to inspect a recording must not itself be reported
  /// as a failure of the recording.
  Future<FfmpegRecordingCheck?> _verifyOutput({int? exitCode}) async {
    if (!config.verifyOutput || _journalPaths.isEmpty) {
      _lastCheck = null;

      return null;
    }

    final FfmpegSegmentJournal journal;

    try {
      journal = FfmpegSegmentJournal.fromFiles(_journalPaths.map(File.new));
    } on Object catch (error) {
      _log.error(
        'the segment journal could not be read',
        error: error,
        fields: <String, Object?>{'journals': _journalPaths.length},
      );

      return null;
    }

    final check = await FfmpegRecordingCheck.evaluate(
      journal: journal,
      claimedDuration: _recordedMediaTime,
      probe: config.verifyPlayability ? _probeOf() : null,
    );

    _lastCheck = check;

    if (check.verdict != FfmpegRecordingVerdict.complete) {
      _log.warning('the recording output is ${check.verdict.name}', fields: <String, Object?>{'output': check.reason});
    }

    return check;
  }

  /// Why a finished recording is reported as a failure, or null when it is not.
  ///
  /// [endingWasAskedFor] is what makes the same code mean two things: a user
  /// stop kills FFmpeg, and a killed FFmpeg reports `255` exactly like a crashed
  /// one does.
  Object? _failureOf(FfmpegRecordingCheck? check, {required int? exitCode, required bool endingWasAskedFor}) {
    if (check != null && !check.isUsable) {
      return FfmpegRecordingFailure(check, exitCode: exitCode);
    }

    final isExpectedCode = exitCode == null || exitCode == 0 || (endingWasAskedFor && exitCode == 255);

    if (isExpectedCode) {
      return null;
    }

    // What was written goes into the message: a failure code after two hours of
    // segments is a different bug from one after none, and the code alone cannot
    // tell them apart.
    final detail = check == null
        ? ''
        : ' after ${check.segments} segment(s), ${check.bytesOnDisk}B'
              '${check.reason == null ? '' : ' (${check.reason})'}';

    return StateError('FFmpeg exited with code $exitCode$detail');
  }

  void _emit(RecordingState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('FfmpegRecordingBackend has been disposed.');
    }
  }
}

/// Starts a background-execution session for a recording.
///
/// A function rather than a direct call so a host — or a test, which has no
/// platform to hold a wake lock — can supply its own: the point of the seam is
/// that the backend's lifecycle (acquire on start, release on *every* end) is
/// what matters, and that is worth observing without a device.
typedef BackgroundExecutionStarter =
    Future<BackgroundExecutionLease?> Function({required BackgroundNotification notification, bool wakeLock});
