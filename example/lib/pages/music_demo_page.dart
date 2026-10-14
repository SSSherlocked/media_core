import 'dart:async';
import 'dart:io';

import 'package:example/ui/demo_log.dart';
import 'package:example/ui/demo_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_audio/media_core_audio.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';

/// A lyric the demo can show without any network call.
///
/// Two timestamps on one line, a `[offset:]` tag and a translation track: the
/// shapes real lyric files use, so the parser is exercised rather than
/// flattered.
const String kDemoLrc = '''
[ti:示例歌词 / demo lyric]
[ar:media_core]
[offset:0]
[00:00.50]第一句歌词
[00:04.00][00:20.00]重复出现的一句
[00:08.50]第三句 —— 带翻译
[00:13.00]最后一句
''';

/// The matching translation track for [kDemoLrc].
const String kDemoLrcTranslation = '''
[00:00.50]First line
[00:04.00]Repeated line
[00:08.50]Third line - with translation
[00:13.00]Last line
''';

/// A [MusicSource] that serves whatever URLs the developer types in.
///
/// The example of the extension point: a source declares *how* to find and
/// resolve music, and the player never learns which platform it is. A real
/// source does the platform's signing and header work here.
final class DemoMusicSource extends MusicSource {
  /// Creates the demo source.
  new();

  /// URLs to serve, one track each.
  List<String> urls = const <String>[];

  @override
  String get id => 'demo';

  @override
  String get name => '示例音源 / demo source';

  @override
  Future<MusicSourcePage<MusicTrack>> search(String keyword, {int page = 1, int pageSize = 30}) async {
    final needle = keyword.trim().toLowerCase();

    final tracks = <MusicTrack>[
      for (final url in urls)
        MusicTrack(
          id: url.hashCode.toString(),
          title: Uri.parse(url).pathSegments.isEmpty ? url : Uri.parse(url).pathSegments.last,
          artist: 'demo',
          sourceId: id,
          metadata: <String, Object?>{'url': url},
        ),
    ];

    return MusicSourcePage<MusicTrack>(
      items: needle.isEmpty
          ? tracks
          : tracks.where((track) => track.title.toLowerCase().contains(needle)).toList(growable: false),
      total: tracks.length,
    );
  }

  @override
  Future<TrackSource> resolveTrackSource(MusicTrack track, {MusicQuality? quality}) async {
    final url = track.metadataValue<String>('url') ?? track.localPath;

    if (url == null) {
      throw StateError('DemoMusicSource has no URL for ${track.id}');
    }

    final uri = Uri.parse(url);

    // A real platform would sign the URL here and set expiresAt; the demo
    // leaves it open, so nothing expires mid-song.
    return TrackSource(uri: uri, format: SourceFormat.fromUri(uri), quality: quality ?? MusicQuality.auto);
  }

  @override
  Future<MusicLyricPayload?> resolveLyric(MusicTrack track) async {
    return const MusicLyricPayload(lyric: kDemoLrc, translation: kDemoLrcTranslation);
  }
}

/// Music playback: queue, play modes, lyrics, desktop lyrics, background and
/// downloads — the whole `media_core_audio` surface in one page.
class MusicDemoPage extends StatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  State<MusicDemoPage> createState() => _MusicDemoPageState();
}

final class _MusicDemoPageState extends State<MusicDemoPage> {
  static const String _defaultUrls =
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3\n'
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3';

  final DemoLog _log = DemoLog();
  final TextEditingController _urls = TextEditingController(text: _defaultUrls);

  late final PlayerKernel _kernel;
  late final DemoMusicSource _source;
  late final MusicSourceRegistry _registry;
  late final AudioPlaybackController _player;
  late final LyricTimeline _timeline;
  late final DesktopLyricController _desktopLyrics;
  late final AudioPermissionService _permissions;
  late final MusicDownloadQueue _downloads;

  MusicBackgroundBinding? _background;
  StreamSubscription<AudioPlaybackState>? _stateSub;
  StreamSubscription<MusicDownloadTask>? _downloadSub;
  StreamSubscription<LyricPosition>? _lyricSub;

  AudioPlaybackState _state = AudioPlaybackState.idle;

  /// Every published snapshot, including the position ticks.
  ///
  /// The scrubber reads this instead of [_state] so a playing track repaints
  /// one row rather than the page: [_state] only moves when something other
  /// than the position moved.
  final ValueNotifier<AudioPlaybackState> _live = ValueNotifier<AudioPlaybackState>(AudioPlaybackState.idle);

  LyricPosition _lyric = LyricPosition.none;

  /// Download progress arrives about five times a second per task, so the
  /// status line owns a notifier instead of rebuilding the page.
  final ValueNotifier<String> _downloadStatus = ValueNotifier<String>('—');
  DesktopLyricStyle _style = const DesktopLyricStyle();

  @override
  void initState() {
    super.initState();

    _kernel = PlayerKernel()..registerBackend(const MediaKitAdapterFactory().registration());
    _source = DemoMusicSource();
    _registry = MusicSourceRegistry(<MusicSource>[_source]);
    _permissions = AudioPermissionService();
    _downloads = MusicDownloadQueue();

    // The demo is the "keep listening with the screen off" shape, so the music
    // player opts out of the kernel's background pause. The button below does not
    // decide that: it shows or hides the system media surface, which is a
    // different thing and used to be labelled as if it were the same one.
    _player = AudioPlaybackController(
      _kernel,
      registry: _registry,
      playerConfig: const PlayerConfig(pauseWhenBackgrounded: false),
    );
    _timeline = LyricTimeline();
    _desktopLyrics = DesktopLyricController(_player, permissions: _permissions);

    _stateSub = _player.stateStream.listen((state) {
      _live.value = state;

      // The same position that drives the player drives the lyric cursor.
      _timeline.update(state.position);

      // `position` is the only field that moves every tick, so the page is
      // rebuilt for everything else and left alone for that.
      if (state.copyWith(position: _state.position) == _state) {
        return;
      }

      setState(() => _state = state);
    });

    _lyricSub = _timeline.changes.listen((position) => setState(() => _lyric = position));

    _downloadSub = _downloads.updates.listen((task) {
      final progress = task.progress;

      _downloadStatus.value =
          '${task.status.name}'
          '${progress == null ? '' : '  ${(progress * 100).toStringAsFixed(1)}%'}'
          '${task.error == null ? '' : '  ${task.error}'}';
    });
  }

  @override
  void dispose() {
    // dispose() is synchronous: these async teardowns are fire-and-forget.
    unawaited(_stateSub?.cancel());
    unawaited(_lyricSub?.cancel());
    unawaited(_downloadSub?.cancel());

    _live.dispose();
    _downloadStatus.dispose();

    unawaited(_background?.dispose());
    unawaited(_desktopLyrics.dispose());
    unawaited(_player.dispose());
    unawaited(_downloads.dispose());
    unawaited(_timeline.dispose());
    unawaited(_kernel.dispose());
    _urls.dispose();
    _log.dispose();

    super.dispose();
  }

  Future<void> _loadQueue() async {
    _source.urls = _urls.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    // Through the source, the way an app builds a queue from a search result.
    final page = await _source.search('');

    _log.add('source returned ${page.items.length} track(s)');

    await _player.setQueue(page.items);

    await _reloadLyrics();
  }

  Future<void> _reloadLyrics() async {
    final document = await _player.loadCurrentLyric();

    _timeline.setDocument(document);

    _log.add('lyric loaded: ${document.length} line(s), translation merged');
  }

  Future<void> _showDesktopLyrics() async {
    final shown = await _desktopLyrics.show();

    _log.add(shown ? 'desktop lyric window shown' : 'desktop lyric unavailable or refused');
  }

  Future<void> _toggleBackground() async {
    if (_background != null) {
      await _background!.dispose();

      setState(() => _background = null);

      _log.add('media surface detached — the surface is released with it');

      return;
    }

    try {
      // Enabled by main() at startup; this call is idempotent and returns the
      // same driver, which the binding then uses.
      // The app-wide driver, not a second one: the platform has a single media
      // notification, so `AudioService.init` runs once per process — a driver
      // created here would fight the one main() enabled at startup.
      final audio = MediaSessionBootstrap.current ?? await MediaSessionBootstrap.enable();

      final binding = MusicBackgroundBinding(_player, audio)..attach();

      // The label reads this field, so the attach has to repaint the page.
      setState(() => _background = binding);

      _log.add(
        'media surface attached (notification / lock screen / SMTC / MPRIS) — '
        '后台是否暂停由 PlayerConfig/KernelOptions 决定，不在这个开关上',
      );
    } on Object catch (error) {
      _log.add('background binding failed: $error');
    }
  }

  Future<void> _downloadCurrent() async {
    final track = _state.track;

    if (track == null) {
      return;
    }

    final source = await _registry.resolveTrackSource(track);
    final directory = Directory.systemTemp.createTempSync('media_core_demo');

    _log.add('downloading to ${directory.path}');

    _downloads.downloadTrack(track: track, source: source, directory: directory.path);
  }

  @override
  Widget build(BuildContext context) {
    final track = _state.track;

    return DemoPageScaffold(
      title: '音乐 / Music',
      subtitle: '音源 → 队列 → 播放模式 → 歌词 → 桌面歌词 → 后台播放 → 下载，全部逻辑都在 media_core_audio。',
      log: _log,
      actions: [
        FilledButton.icon(onPressed: _loadQueue, icon: const Icon(Icons.queue_music), label: const Text('加载队列')),
        OutlinedButton(onPressed: _player.previous, child: const Text('上一首')),
        OutlinedButton(onPressed: _player.toggle, child: Text(_state.playing ? '暂停' : '播放')),
        OutlinedButton(onPressed: () => _player.next(), child: const Text('下一首')),
        OutlinedButton(onPressed: _reloadLyrics, child: const Text('重新加载歌词')),
        OutlinedButton(onPressed: _showDesktopLyrics, child: const Text('桌面歌词')),
        OutlinedButton(
          onPressed: () {
            // The label reads the controller, so the tap has to repaint the
            // page: it used to ride along on the position tick.
            setState(() => _desktopLyrics.setLocked(locked: !_desktopLyrics.locked));
          },
          child: Text(_desktopLyrics.locked ? '解锁桌面歌词' : '锁定桌面歌词'),
        ),
        OutlinedButton(onPressed: _toggleBackground, child: Text(_background == null ? '显示系统媒体面' : '隐藏系统媒体面')),
        OutlinedButton(onPressed: _downloadCurrent, child: const Text('下载当前曲目')),
        OutlinedButton(
          onPressed: () async {
            final results = await _permissions.requestAll(const <AudioPermission>[
              AudioPermission.notifications,
              AudioPermission.mediaLibrary,
            ]);

            _log.add('permissions: $results');
          },
          child: const Text('申请通知/媒体库权限'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NowPlaying(state: _state),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final mode in PlayMode.values)
                ChoiceChip(
                  label: Text(_modeLabel(mode)),
                  selected: _state.mode == mode,
                  onSelected: (_) => _player.setPlayMode(mode),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: _live,
            builder: (context, _) {
              final live = _live.value;

              return Row(
                children: [
                  Text(_format(live.position)),
                  Expanded(
                    child: Slider(
                      value: live.position.inMilliseconds
                          .clamp(0, live.duration.inMilliseconds == 0 ? 1 : live.duration.inMilliseconds)
                          .toDouble(),
                      max: live.duration.inMilliseconds == 0 ? 1 : live.duration.inMilliseconds.toDouble(),
                      onChanged: (value) => _player.seek(Duration(milliseconds: value.round())),
                    ),
                  ),
                  Text(_format(live.duration)),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          _LyricPanel(position: _lyric, hasLyrics: _timeline.hasLyrics),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: _downloadStatus,
            builder: (context, _) =>
                Text('下载状态 / download: ${_downloadStatus.value}', style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urls,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: '音源地址，每行一首 / one audio URL per line',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          if (track != null) Text('当前曲目 / current: ${track.displayName}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          DropdownButton<double>(
            value: _style.fontSize,
            items: const <DropdownMenuItem<double>>[
              DropdownMenuItem(value: 28, child: Text('桌面歌词字号 28')),
              DropdownMenuItem(value: 40, child: Text('桌面歌词字号 40')),
              DropdownMenuItem(value: 56, child: Text('桌面歌词字号 56')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }

              // The dropdown shows this field, so the pick has to repaint.
              setState(() => _style = _style.copyWith(fontSize: value));
              // Applying to the overlay window is detached; awaiting it here would
              // only stall the slider's onChanged callback.
              unawaited(_desktopLyrics.setStyle(_style));
            },
          ),
        ],
      ),
    );
  }

  String _modeLabel(PlayMode mode) {
    return switch (mode) {
      PlayMode.list => '顺序',
      PlayMode.listLoop => '列表循环',
      PlayMode.singleLoop => '单曲循环',
      PlayMode.random => '随机',
    };
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }
}

/// Current-track header.
class _NowPlaying extends StatelessWidget {
  const new({required this.state});

  final AudioPlaybackState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.music_note),
        title: Text(state.track?.displayName ?? '未播放 / idle'),
        subtitle: Text(
          '${state.playing ? 'playing' : 'paused'}'
          '   队列 / queue: ${state.index + 1}/${state.queueLength}'
          '   ${state.loading ? 'loading  ' : ''}'
          '${state.error ?? ''}',
        ),
        trailing: state.quality == null ? null : Chip(label: Text(state.quality!.label)),
      ),
    );
  }
}

/// Current lyric line, its translation and the next line.
class _LyricPanel extends StatelessWidget {
  const new({required this.position, required this.hasLyrics});

  final LyricPosition position;
  final bool hasLyrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = position.line;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('歌词 / lyric', style: theme.textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(!hasLyrics ? '没有歌词 / no lyrics' : (line?.text ?? '…'), style: theme.textTheme.titleMedium),
          if (line?.translation != null) Text(line!.translation!, style: theme.textTheme.bodySmall),
          if (hasLyrics) LinearProgressIndicator(value: position.lineProgress, minHeight: 3),
        ],
      ),
    );
  }
}
