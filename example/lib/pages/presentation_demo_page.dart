import 'dart:async';
import 'dart:math';

import 'package:example/ui/demo_log.dart';
import 'package:example/ui/demo_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_danmaku/media_core_danmaku.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';
import 'package:media_core_presentation/media_core_presentation.dart';

/// Presentation (fullscreen / PiP / floating) and the danmaku overlay.
///
/// Both are *capabilities* around the player rather than part of it: the kernel
/// forwards presentation requests to an attached driver, and danmaku is a
/// session fed by a transport. The demo wires a synthetic transport, which is
/// what a site integration replaces with a real one.
class PresentationDemoPage extends StatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  State<PresentationDemoPage> createState() => _PresentationDemoPageState();
}

final class _PresentationDemoPageState extends State<PresentationDemoPage> {
  final DemoLog _log = DemoLog();
  final TextEditingController _url = TextEditingController(
    text: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
  );

  late final PlayerKernel _kernel;
  final MediaCorePresentation _presentation = MediaCorePresentation();
  final DanmakuOverlaySession _danmaku = DanmakuOverlaySession();

  PlayerHandle? _handle;
  Timer? _fakeDanmaku;
  int _sequence = 0;

  @override
  void initState() {
    super.initState();

    _kernel = PlayerKernel()..registerBackend(const MediaKitAdapterFactory().registration());

    // The kernel forwards fullscreen/PiP/floating requests to this driver.
    _kernel.presentationDriver = _presentation;
    _presentation.observeKernel(_kernel);

    // The overlay only accepts messages while its surface is visible.
    _danmaku.bindVisibility(Stream<bool>.value(true));
  }

  @override
  void dispose() {
    _fakeDanmaku?.cancel();

    // dispose() is synchronous: these async teardowns are fire-and-forget.
    unawaited(_presentation.dispose());
    unawaited(_danmaku.dispose());
    unawaited(_kernel.dispose());
    _url.dispose();
    _log.dispose();

    super.dispose();
  }

  Future<void> _open() async {
    final source = PlayerSource(
      id: SourceId('presentation_${_url.text.hashCode}'),
      uri: Uri.parse(_url.text.trim()),
      type: SourceType.remote,
      protocol: SourceProtocol.fromScheme(Uri.parse(_url.text.trim()).scheme),
      mediaType: SourceMediaType.video,
    );

    _handle = await _kernel.create(source: source);

    _log.add('opened on ${_handle!.backendId}');

    if (mounted) {
      setState(() {});
    }
  }

  void _toggleFakeDanmaku() {
    if (_fakeDanmaku != null) {
      _fakeDanmaku!.cancel();
      _fakeDanmaku = null;

      _log.add('danmaku feed stopped');

      return;
    }

    const users = <String>['小明', 'alice', '路人甲', 'bob', '粉丝'];
    const texts = <String>['666', '好听', '前方高能', 'nice', '这个不错', '哈哈哈哈哈'];

    final random = Random();

    // A synthetic transport: real sites implement DanmakuTransport instead.
    _fakeDanmaku = Timer.periodic(const Duration(milliseconds: 700), (_) {
      final message = DanmakuMessage(
        type: DanmakuMessageType.chat,
        userName: users[random.nextInt(users.length)],
        text: texts[random.nextInt(texts.length)],
      );

      _danmaku.enqueue(message);

      setState(() => _sequence++);
    });

    _log.add('danmaku feed started (synthetic transport)');
  }

  Future<void> _applyPresentation(String label, Future<void> Function(PlayerId id) request) async {
    final handle = _handle;

    if (handle == null) {
      _log.add('$label: open a video first');

      return;
    }

    try {
      await request(handle.id);
      _log.add('$label requested');
    } on Object catch (error) {
      // "No presentation driver attached" is the honest answer on platforms
      // without one, and it is worth showing rather than hiding.
      _log.add('$label failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle;
    final now = DateTime.now();
    final live = _danmaku.items.where((item) => item.isLiveAt(now)).toList(growable: false);

    return DemoPageScaffold(
      title: '展示与弹幕 / Presentation & danmaku',
      subtitle: 'kernel.attachPresentation(driver) 转发全屏/PiP/悬浮窗请求；弹幕是"会话 + transport"，示例用假 transport 喂消息。',
      log: _log,
      actions: [
        FilledButton.icon(onPressed: _open, icon: const Icon(Icons.play_arrow), label: const Text('打开视频')),
        OutlinedButton(onPressed: () => _applyPresentation('全屏', _kernel.enterFullscreen), child: const Text('全屏')),
        OutlinedButton(onPressed: () => _applyPresentation('退出全屏', _kernel.exitFullscreen), child: const Text('退出全屏')),
        OutlinedButton(onPressed: () => _applyPresentation('PiP', _kernel.enterPip), child: const Text('画中画')),
        OutlinedButton(onPressed: () => _applyPresentation('悬浮窗', _kernel.enterFloating), child: const Text('悬浮窗')),
        OutlinedButton(onPressed: _toggleFakeDanmaku, child: Text(_fakeDanmaku == null ? '开始弹幕' : '停止弹幕')),
        OutlinedButton(
          onPressed: () {
            _danmaku.clear();
            setState(() => _sequence++);
          },
          child: const Text('清空弹幕'),
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
                      child: Text('未打开视频', style: TextStyle(color: Colors.white70)),
                    )
                  : MediaPlayerView(handle: handle),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: const InputDecoration(labelText: '视频地址 / URL', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 12),
          Text(
            '桌面悬浮窗支持 / floating window: ${_presentation.supportsPresentationWindow}\n'
            '悬停控件 / hover overlays: ${_presentation.overlayHoverMode}\n'
            '方向 / orientation: ${_presentation.orientation.name}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            '弹幕 / danmaku（活动 ${live.length} 条，enabled=${_danmaku.isEnabled}）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          // A real overlay renders and animates these; the demo shows the
          // session's state, which is what the package owns.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in live.take(24))
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${item.message.userName}: ${item.message.text}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
