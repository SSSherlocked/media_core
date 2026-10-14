import 'package:example/demos/fakes/fake_ffmpeg.dart';
import 'package:example/demos/module_demo.dart';
import 'package:media_core/media_core.dart' show RecordingConfig, RecordingSource;
import 'package:media_core_recording_ffmpeg/media_core_recording_ffmpeg.dart';

/// Recording a live stream: the argument list, then the process lifecycle.
///
/// FFmpeg failures are almost always statement about the argument list, and
/// "exit code 255" says nothing on its own — so the demo prints the exact argv it
/// would hand to FFmpeg, and then drives the state machine with a fake process so
/// the transitions are visible on a machine that has no FFmpeg installed.
class RecordingDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'recording';

  @override
  ModuleCategory get category => ModuleCategory.capability;

  @override
  String get nameZh => '录播：FFmpeg 参数与状态机';

  @override
  String get nameEn => 'Recording: FFmpeg arguments and the state machine';

  @override
  String get purposeZh =>
      '录播把一条直播流转成分段 MPEG-TS 文件：分段让"失败只丢几秒而不是整场"，音频中继让同一份录制里既有流也能有本地音轨。参数构造是纯函数（可复制去 shell 复现），状态机与退出码归因由 backend 负责，两者都能在没有 FFmpeg 的机器上跑。';

  @override
  String get purposeEn =>
      'Recording turns a live stream into segmented MPEG-TS files: segments make a failure cost seconds instead of a whole session, and the audio relay lets one recording carry both the stream and a local audio track. The argument builder is a pure function (paste it into a shell to reproduce), and the state machine plus exit-code attribution sit in the backend — both run without FFmpeg installed.';

  @override
  List<String> get pointsZh => const <String>[
    'FfmpegRecordArguments.recordArguments — 纯函数：URL / 输出目录 / 分段模板 / CSV 日志路径',
    '分段：segmentTime + %06d 模式，边录边出可播文件',
    '同一 FFmpeg 里多一路输入做音频中继（-map 两路），避免二次封装',
    '退出码 255 既可能是流断了也可能是被主动停止，所以 backend 记录"停止意图"来归因',
    '停止结果按产物判定：读回 CSV 清单、核对段文件（默认再用 FFprobe 打开首尾两段），空目录不再报成功',
    '断流会自动重开：每次尝试重建整套参数（新地址 + 新段名前缀 + 新清单），restartLimit 只数"从没跑起来"的连续失败',
    '统计回调给出已写字节与媒体时间 → 同时喂给进度条和 memory 模块',
    '容器只有两种（分段 TS / 分段 MP4），判据是「每段可播、被杀不废」；一次录制一个目录与前缀；录完用 concat 复制成一个文件',
    'FfmpegLiveRecordingWatcher 先问房间「直播中吗」，直播才录；一场开播/关播只通知一次，轮询带抖动',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'FfmpegRecordArguments.recordArguments — a pure function: URL, output directory, segment pattern, CSV journal path',
    'Segmentation: segmentTime with a %06d pattern, so playable files appear while recording',
    'A second input inside the same FFmpeg relays audio (-map twice), avoiding a re-mux step',
    'Exit code 255 means both "the stream died" and "someone stopped us", so the backend tracks the stop intent to attribute it',
    'A stop is judged by its output: the journal is read back and the segments it names are checked (FFprobe opens the first and last by default), so an empty directory is no longer a success',
    'A dropped stream is re-opened: every attempt rebuilds the whole argument list (fresh address, new segment prefix, new journal), and restartLimit counts only the failures that never got going',
    'The statistics callback gives bytes written and media time — feeding a progress bar and the memory module at once',
    'Two containers only (segmented TS, fragmented MP4) on one test: every segment playable, nothing lost to a kill; one directory and prefix per recording; a concat copy joins them afterwards',
    'FfmpegLiveRecordingWatcher asks the room whether it is live and records only then — one start and one end notification per session, jittered polling',
  ];

  @override
  String get snippet => r'''
final backend = FfmpegRecordingBackend(outputDirectory: '${dir}/recordings');

backend.onStateChanged.listen((state) => print('${state.status.name}: ${state.bytesWritten}B'));

await backend.start(
  RecordingSource.network('https://example.com/live/stream.flv'),
  const RecordingConfig(recordAudio: true),
);

// ... and later:
final result = await backend.stop();   // per-segment files are already playable
print('${result.success} ${backend.lastCheck}');  // judged by the files, not the exit code
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();

    _argumentsSection(buffer);
    await _lifecycleSection(buffer);

    return buffer.toString();
  }

  /// The argument list, which is what an FFmpeg failure is usually about.
  void _argumentsSection(StringBuffer buffer) {
    buffer.writeln('argument list for a segmented capture (paste it into a shell to reproduce):');

    final cases = <({String label, String url, FfmpegRecordConfig config})>[
      (label: 'FLV live stream', url: 'https://example.com/live/room.flv', config: FfmpegRecordConfig.defaults),
      (
        label: 'HLS stream, 10-minute segments, no best-stream preference',
        url: 'https://example.com/live/room.m3u8',
        config: const FfmpegRecordConfig(segmentTime: 600, preferBestStream: false, filePrefix: 'room-8891'),
      ),
      (
        label: 'RTMP with a 5s read timeout and a short journal',
        url: 'rtmp://example.com/app/stream',
        // rwTimeout is in seconds.
        config: const FfmpegRecordConfig(rwTimeout: 5, journalSuffix: '.csv'),
      ),
    ];

    for (final item in cases) {
      final arguments = FfmpegRecordArguments(config: item.config).recordArguments(
        url: item.url,
        outputDirectory: '/data/recordings',
        segmentPattern:
            '${FfmpegRecordArguments.safeFilePrefix(item.config.filePrefix)}_%06d${item.config.segmentSuffix}',
        journalPath: '/data/recordings/journal${item.config.journalSuffix}',
        filePrefix: FfmpegRecordArguments.safeFilePrefix(item.config.filePrefix),
      );

      buffer
        ..writeln()
        ..writeln('  ${item.label}:')
        ..writeln('    ffmpeg ${arguments.join(' ')}');
    }

    buffer
      ..writeln()
      ..writeln('  → -c copy: the capture is a remux, not a transcode (no quality loss, no CPU)')
      ..writeln('  → -f segment + the %06d pattern: every N seconds a finished, playable file appears')
      ..writeln('  → per-scheme input options: HLS gets its own flags, RTMP its timeout, FLV its buffering')
      ..writeln();
  }

  /// The state machine, driven by a fake process.
  Future<void> _lifecycleSection(StringBuffer buffer) async {
    final executor = FakeFfmpegExecutor(statisticsInterval: const Duration(milliseconds: 40));
    const directory = '/tmp/media_core_recording_demo';
    // The fake process has no FFprobe behind it, so the playability layer is
    // switched off and the check is the one the fake can actually answer: the
    // journal and the segment files it leaves on disk.
    const recordConfig = FfmpegRecordConfig(verifyPlayability: false);
    final backend = FfmpegRecordingBackend(executor: executor, config: recordConfig, outputDirectory: directory);

    final transitions = <String>[];
    final subscription = backend.onStateChanged.listen((state) {
      transitions.add(
        '${state.status.name}'
        '${state.bytesWritten == 0 ? '' : ' (${state.bytesWritten ~/ 1024}KB)'}',
      );
    });

    buffer.writeln('state machine (fake FFmpeg, no native library involved):');

    await backend.initialize();
    await backend.start(const RecordingSource.network('https://example.com/live/room.flv'), const RecordingConfig());

    // Let a few statistics ticks arrive.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final result = await backend.stop();
    await subscription.cancel();

    buffer
      ..writeln('  ${transitions.join(' → ')}')
      ..writeln(
        '  stop() reported success=${result.success}, '
        'duration=${result.duration.inMilliseconds}ms, '
        'bytes=${result.bytesWritten}',
      )
      ..writeln('  output check: ${backend.lastCheck}')
      ..writeln(
        '  → the byte figure is what the segments occupy; the statistics line the ticks above '
        'reported is the muxer counter for the child file being written, not the recording',
      )
      ..writeln(
        '  executor.initialized=${executor.initialized} — initialize() only warms the native '
        'library up; the first start loads it. Sessions: ${executor.started.length}',
      )
      ..writeln();

    // The case an exit code cannot express: the process was killed after it had
    // written nothing, and a `success: true` here is a recording nobody will
    // ever find.
    final empty = FakeFfmpegExecutor(statisticsInterval: const Duration(milliseconds: 30), segmentsToWrite: 0);
    final third = FfmpegRecordingBackend(executor: empty, config: recordConfig, outputDirectory: '$directory/empty');
    await third.initialize();
    await third.start(const RecordingSource.network('https://example.com/live/gone.flv'), const RecordingConfig());
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final emptyResult = await third.stop();

    buffer
      ..writeln('a stop with no output behind it:')
      ..writeln('  success=${emptyResult.success}, error=${emptyResult.error}')
      ..writeln('  → the process ended exactly like a good recording; only the journal knows')
      ..writeln();

    await third.dispose();

    // The "nobody stopped it" case: the stream died. The same 255 a user's stop
    // produces is what makes it recoverable rather than fatal - the intent the
    // caller set is what tells them apart.
    var refreshes = 0;
    final failing = FakeFfmpegExecutor(statisticsInterval: const Duration(milliseconds: 30));
    final second = FfmpegRecordingBackend(
      executor: failing,
      config: recordConfig.copyWith(
        restartLimit: 2,
        restartBackoff: const Duration(milliseconds: 40),
        restartBackoffMax: const Duration(milliseconds: 40),
      ),
      outputDirectory: '$directory/recovered',
      urlRefresher: (source) async => 'https://example.com/live/room.flv?sign=${++refreshes}',
    );
    await second.initialize();
    await second.start(const RecordingSource.network('https://example.com/live/dying.flv'), const RecordingConfig());
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await failing.last?.cancel(); // the process ends on its own, with 255
    await Future<void>.delayed(const Duration(milliseconds: 250));

    buffer
      ..writeln('a stream that drops (the backend re-opens it):')
      ..writeln('  processes: ${failing.started.length}, status=${second.state.status.name}')
      ..writeln(
        '  second attempt -i: '
        '${_argumentValue(failing.started.length > 1 ? failing.started[1] : failing.started.last, '-i')}',
      )
      ..writeln('  → the address the host refreshed is used, and the attempt writes its own segments')
      ..writeln('  → the same 255 would be a normal stop if stop() had been called first')
      ..writeln();

    final givenUp = FfmpegRecordingBackend(
      executor: failing,
      config: recordConfig.copyWith(
        restartLimit: 0,
        restartBackoff: const Duration(milliseconds: 20),
        restartBackoffMax: const Duration(milliseconds: 20),
      ),
      outputDirectory: '$directory/gave-up',
    );
    await givenUp.initialize();
    await givenUp.start(const RecordingSource.network('https://example.com/live/off-air.flv'), const RecordingConfig());
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await failing.last?.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    buffer
      ..writeln('the same drop with restartLimit 0:')
      ..writeln('  status=${givenUp.state.status.name}, error=${givenUp.state.error}')
      ..writeln('  → this is what a host that only records on user action wants')
      ..writeln();

    await _watchSection(buffer, directory, recordConfig);

    buffer.writeln(
      "memory module view of a running recording: the account reports FFmpeg's "
      'written bytes — one of the few measured figures in the framework.',
    );

    await backend.dispose();
    await second.dispose();
    await givenUp.dispose();
  }

  /// The watch loop: a room that is not live yet, goes live, and closes again.
  Future<void> _watchSection(StringBuffer buffer, String directory, FfmpegRecordConfig recordConfig) async {
    // Recovery is off in this section so what the output shows is the watcher's
    // own decision — record, notice the end, ask again later — rather than the
    // backend re-opening the same process underneath it.
    final executor = FakeFfmpegExecutor(statisticsInterval: const Duration(milliseconds: 30));
    final watched = FfmpegRecordingBackend(
      executor: executor,
      config: recordConfig.copyWith(restartLimit: 0),
      outputDirectory: '$directory/watched',
    );

    const script = <FfmpegLiveRoomStatus>[
      FfmpegLiveRoomStatus.offline(),
      FfmpegLiveRoomStatus.live('https://example.com/live/room.flv?sign=once'),
      FfmpegLiveRoomStatus.offline(),
    ];

    var asked = 0;
    var starts = 0;
    var ends = 0;
    final watcher = FfmpegLiveRecordingWatcher(
      backend: watched,
      statusProbe: (source) async {
        final answer = script[asked < script.length ? asked : script.length - 1];
        asked++;

        return answer;
      },
      pollInterval: const Duration(milliseconds: 40),
      recheckInterval: const Duration(milliseconds: 20),
      shortRecordingAfter: const Duration(seconds: 5),
      onLiveStart: (_) => starts++,
      onLiveEnd: (_) => ends++,
    );
    final sessions = <FfmpegLiveRecordingSession>[];
    final subscription = watcher.onSessionChanged.listen(sessions.add);

    await watched.initialize();
    await watcher.watch(const RecordingSource.network('https://example.com/live/room.flv', id: 'room-8891'));
    final offlineAtFirst = executor.started.length;

    // The room goes live on the second poll.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final recording = executor.last?.isRunning ?? false;

    // The stream ends on its own, which is how the watcher learns the session is
    // over — it does not poll while a recording runs.
    await executor.last?.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await subscription.cancel();
    await watcher.dispose();
    await watched.dispose();

    buffer
      ..writeln('a room watched rather than guessed at:')
      ..writeln('  started before the room was live: $offlineAtFirst, recording after it went live: $recording')
      ..writeln(
        '  probe asked $asked times, processes ${executor.started.length}, notifications start=$starts end=$ends',
      )
      ..writeln(
        sessions.isEmpty
            ? '  no session was announced'
            : '  session: ${sessions.last.recordings.length} recording(s), '
                  '${sessions.last.recordings.isEmpty ? '' : sessions.last.recordings.first}',
      )
      ..writeln('  → one start and one end per live session; a flicker is not a new session')
      ..writeln('  → the address the probe resolved is what got recorded, so a signed URL is fetched once')
      ..writeln();
  }

  /// The value that follows [option] in an FFmpeg argument list.
  static String _argumentValue(List<String> arguments, String option) {
    final index = arguments.indexOf(option);

    return index < 0 ? '(not passed)' : arguments[index + 1];
  }
}
