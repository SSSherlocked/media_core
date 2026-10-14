import 'dart:async';

import 'package:example/ui/demo_log.dart';
import 'package:example/ui/demo_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';

/// A video URL the example can play without any setup.
const List<({String label, String url})> kSampleSources = <({String label, String url})>[
  (label: 'MP4 (Flutter assets)', url: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4'),
  (
    label: 'MP4 (big buck bunny)',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  ),
  (label: 'HLS (mux test stream)', url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8'),
  (
    label: 'HLS (Apple bipbop)',
    url: 'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
  ),
];

/// The core demo: one player, one adapter, every lifecycle call.
///
/// Shows the wiring a host is expected to write —
/// `PlayerKernel → registerBackend → create → open → play` — plus the
/// observability the kernel offers: playback state, adapter events, operation
/// records, recovery decisions, and which backend the selector picked and why.
class PlayerDemoPage extends StatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  State<PlayerDemoPage> createState() => _PlayerDemoPageState();
}

final class _PlayerDemoPageState extends State<PlayerDemoPage> {
  final DemoLog _log = DemoLog();
  final TextEditingController _url = TextEditingController(text: kSampleSources.first.url);

  late final PlayerKernel _kernel;
  PlayerHandle? _handle;

  StreamSubscription<PlayerAdapterEvent>? _adapterSub;
  StreamSubscription<Operation>? _operationSub;
  StreamSubscription<RecoveryLadderEvent>? _recoverySub;

  bool _loop = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();

    _kernel = PlayerKernel();

    // The example ships one backend; registering more is a one-liner per
    // adapter package and the selector starts scoring them (see the log).
    _kernel.registerBackend(const MediaKitAdapterFactory().registration());
    _log.add('backend registered: ${_kernel.registry.ids.join(', ')}');
  }

  @override
  void dispose() {
    // dispose() is synchronous: these async teardowns are fire-and-forget.
    unawaited(_adapterSub?.cancel());
    unawaited(_operationSub?.cancel());
    unawaited(_recoverySub?.cancel());

    unawaited(_kernel.dispose());
    _url.dispose();
    _log.dispose();

    super.dispose();
  }

  Future<void> _openAndPlay() async {
    final url = _url.text.trim();

    if (url.isEmpty) {
      return;
    }

    await _adapterSub?.cancel();
    await _operationSub?.cancel();
    await _recoverySub?.cancel();

    // `_kernel.create` makes a new player every call — nothing is reused by
    // source id — so pressing this button twice used to leave the first
    // engine (its decoder and its texture) alive and unwatched. Unmount the
    // view before the engine behind it goes away.
    final previous = _handle;

    if (previous != null) {
      if (mounted) {
        setState(() => _handle = null);
      }

      await previous.dispose();
    }

    final source = PlayerSource(
      id: SourceId('demo_${url.hashCode}'),
      uri: Uri.parse(url),
      type: SourceType.remote,
      protocol: SourceProtocol.fromScheme(Uri.parse(url).scheme),
      format: SourceFormat.fromUri(Uri.parse(url)),
      mediaType: SourceMediaType.video,
      title: 'example',
    );

    _log.add('selector scores: ${_kernel.selector.scoreTable(source)}');

    final handle = await _kernel.create(source: source);

    _handle = handle;

    _adapterSub = handle.adapterEvents.listen((event) {
      // The typed event carries what the framework normalized out of the
      // engine; printing the runtime type is enough for a demo.
      _log.add('adapter: ${event.runtimeType}');
    });

    // Every lifecycle call the handle performs is recorded: this is the
    // "what did the player actually do, in what order" surface.
    _operationSub = handle.onOperation.listen((operation) {
      _log.add('operation: ${operation.type.value} → ${operation.state.name}');
    });

    _recoverySub = handle.recoveryEvents.listen((event) {
      _log.add('recovery: ${event.runtimeType}');
    });

    _log.add('opened ${handle.backendId} — ${Uri.parse(url).pathSegments.last}');

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _ping(String label, Future<void> Function() action) async {
    try {
      await action();
      _log.add('$label ok');
    } on Object catch (error) {
      _log.add('$label failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle;

    return DemoPageScaffold(
      title: '播放器 / PlayerIdentity',
      subtitle: 'kernel → registerBackend → create → open → play；点开日志看引擎事件、操作记录与恢复决策。',
      log: _log,
      actions: [
        FilledButton.icon(
          onPressed: _openAndPlay,
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('打开并播放'),
        ),
        OutlinedButton(onPressed: handle == null ? null : () => _ping('play', handle.play), child: const Text('播放')),
        OutlinedButton(onPressed: handle == null ? null : () => _ping('pause', handle.pause), child: const Text('暂停')),
        OutlinedButton(onPressed: handle == null ? null : () => _ping('stop', handle.stop), child: const Text('停止')),
        OutlinedButton(
          onPressed: handle == null
              ? null
              : () => _ping('mute', () async {
                  // The label reads this field, so the toggle has to repaint
                  // the page itself: it used to ride along on the position
                  // tick that rebuilt everything.
                  setState(() => _muted = !_muted);
                  await handle.setMute(muted: _muted);
                }),
          child: Text(_muted ? '取消静音' : '静音'),
        ),
        OutlinedButton(
          onPressed: handle == null
              ? null
              : () => _ping('loop', () async {
                  setState(() => _loop = !_loop);
                  await handle.setLoop(loop: _loop);
                }),
          child: Text(_loop ? '关闭循环' : '开启循环'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: handle == null
                  ? const Center(
                      child: Text('未创建播放器', style: TextStyle(color: Colors.white70)),
                    )
                  : MediaPlayerView(handle: handle),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: const InputDecoration(labelText: '视频地址 / URL', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final sample in kSampleSources)
                ActionChip(label: Text(sample.label), onPressed: () => setState(() => _url.text = sample.url)),
            ],
          ),
          const SizedBox(height: 12),
          // The transport ticks at up to 4 Hz. Rebuilding the whole page for
          // them used to rebuild the video view, the log panel and every
          // button four times a second, so the readout owns its subscription
          // and nothing above it moves.
          if (handle != null) _TransportReadout(handle: handle),
        ],
      ),
    );
  }
}

/// Position / duration / volume / rate readout for one handle.
///
/// The scrubber and the sliders are the only things a transport update moves,
/// so this is the widget that listens.
final class _TransportReadout extends StatelessWidget {
  const new({required this.handle});

  final PlayerHandle handle;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerTransportState>(
      stream: handle.playbackStream,
      initialData: handle.playbackStream.value,
      builder: (context, snapshot) {
        final playback = snapshot.data;

        if (playback == null) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The same numbers a host would bind to a scrubber.
            Row(
              children: [
                Text(_format(playback.position)),
                Expanded(
                  child: Slider(
                    value: playback.position.inMilliseconds
                        .clamp(0, playback.duration.inMilliseconds == 0 ? 1 : playback.duration.inMilliseconds)
                        .toDouble(),
                    max: playback.duration.inMilliseconds == 0 ? 1 : playback.duration.inMilliseconds.toDouble(),
                    onChanged: (value) => handle.seek(Duration(milliseconds: value.round())),
                  ),
                ),
                Text(_format(playback.duration)),
              ],
            ),
            Row(
              children: [
                const Text('音量'),
                Expanded(
                  child: Slider(value: playback.volume.clamp(0.0, 1.0), onChanged: handle.setVolume),
                ),
                const SizedBox(width: 12),
                const Text('倍速'),
                Expanded(
                  child: Slider(
                    value: playback.rate.clamp(0.25, 4.0),
                    min: 0.25,
                    max: 4,
                    divisions: 15,
                    onChanged: handle.setRate,
                  ),
                ),
              ],
            ),
            Text(
              '状态 / state: ${playback.isPlaying ? 'playing' : playback.command.runtimeType}'
              '  后端 / backend: ${handle.backendId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }
}
