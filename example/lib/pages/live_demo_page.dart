import 'dart:async';

import 'package:example/ui/demo_log.dart';
import 'package:example/ui/demo_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_live/media_core_live.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';

/// Live playback: several lines, one engine sweep at a time.
///
/// Demonstrates the contract that makes live different from VOD: the request
/// carries *lines* (and optionally engine escalation), and the controller owns
/// recovery — it sweeps the lines on the current engine, then the next engine,
/// and only reports a failure when everything is spent.
class LiveDemoPage extends StatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  State<LiveDemoPage> createState() => _LiveDemoPageState();
}

final class _LiveDemoPageState extends State<LiveDemoPage> {
  final DemoLog _log = DemoLog();
  final TextEditingController _urls = TextEditingController(text: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8');

  late final PlayerKernel _kernel;
  late final LivePlaybackController _controller;

  StreamSubscription<PlayerCoreState>? _stateSub;
  StreamSubscription<PlayerFailure>? _failureSub;

  PlayerCoreState _state = PlayerCoreState.idle;

  @override
  void initState() {
    super.initState();

    _kernel = PlayerKernel()..registerBackend(const MediaKitAdapterFactory().registration());
    _controller = LivePlaybackController(_kernel);

    _stateSub = _controller.onStateChanged.listen((state) {
      setState(() => _state = state);
      _log.add('state: ${state.playback.name}');
    });

    _failureSub = _controller.onError.listen((failure) {
      // Exactly one failure per exhausted sweep: this is the caller's signal
      // to show a retry affordance instead of guessing from a frozen picture.
      _log.add('FAILED after every candidate: ${failure.message}');
    });
  }

  @override
  void dispose() {
    // dispose() is synchronous: these async teardowns are fire-and-forget, the
    // framework offers no await point inside State.dispose.
    unawaited(_stateSub?.cancel());
    unawaited(_failureSub?.cancel());

    unawaited(_controller.dispose());
    unawaited(_kernel.dispose());
    _urls.dispose();
    _log.dispose();

    super.dispose();
  }

  Future<void> _play() async {
    final lines = _urls.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return;
    }

    _log.add('play with ${lines.length} line(s)');

    // A multi-line request means "make this play": the controller tries the
    // next line, then the next engine, before reporting.
    await _controller.play(LiveSourceRequest.fromUrls(lines, title: 'example live'));
  }

  @override
  Widget build(BuildContext context) {
    final handle = _controller.handle;

    return DemoPageScaffold(
      title: '直播 / Live',
      subtitle: '多线路请求：先在同引擎换线，全部失败再换引擎，都失败才抛出一次 onError。',
      log: _log,
      actions: [
        FilledButton.icon(onPressed: _play, icon: const Icon(Icons.live_tv), label: const Text('播放')),
        OutlinedButton(onPressed: () => _controller.pause(), child: const Text('暂停')),
        OutlinedButton(onPressed: () => _controller.resume(), child: const Text('继续')),
        OutlinedButton(onPressed: () => _controller.retry(), child: const Text('重试当前线路')),
        OutlinedButton(onPressed: () => _controller.close(), child: const Text('关闭')),
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
                      child: Text('未开始', style: TextStyle(color: Colors.white70)),
                    )
                  : MediaPlayerView(handle: handle),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urls,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: '线路 / lines（每行一条，含 http(s)/HLS/flv 等）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '引擎 / engine: ${_controller.backendId ?? '-'}'
            '   状态 / state: ${_state.playback.name}'
            '   线路 / line: ${_controller.sourceIndex + 1}/${_controller.sources.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
