import 'dart:async';

import 'package:example/ui/demo_log.dart';
import 'package:example/ui/demo_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_feed/media_core_feed.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';

/// Vertical feed: one shared player, pages attached by swiping.
///
/// The point of the demo is what does *not* happen: swiping to the next item
/// re-opens the same handle instead of building a player per page, so there is
/// no engine startup between items. Only the visible page mounts a video
/// widget, which is how a real feed avoids running N surfaces.
class FeedDemoPage extends StatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  State<FeedDemoPage> createState() => _FeedDemoPageState();
}

final class _FeedDemoPageState extends State<FeedDemoPage> {
  static const List<String> kDefaults = <String>[
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
  ];

  final DemoLog _log = DemoLog();
  final TextEditingController _urls = TextEditingController(text: kDefaults.join('\n'));
  final PageController _pages = PageController();

  late final PlayerKernel _kernel;
  late final FeedPlayerController _feed;

  @override
  void initState() {
    super.initState();

    _kernel = PlayerKernel()..registerBackend(const MediaKitAdapterFactory().registration());
    _feed = FeedPlayerController(_kernel);

    _feed.onIndexChanged.listen((index) => _log.add('index → $index'));
    _feed.onItemStateChanged.listen((state) => _log.add('item state: ${state.name}'));
    _feed.onItemError.listen((failure) => _log.add('item failed: ${failure.message}'));
  }

  @override
  void dispose() {
    // dispose() is synchronous, so these async teardowns run detached; the
    // framework gives no place to await them from a State.
    unawaited(_feed.dispose());
    unawaited(_kernel.dispose());
    _pages.dispose();
    _urls.dispose();
    _log.dispose();

    super.dispose();
  }

  Future<void> _load() async {
    final items = _urls.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(
          (url) => PlayerSource(
            id: SourceId('feed_${url.hashCode}'),
            uri: Uri.parse(url),
            type: SourceType.remote,
            protocol: SourceProtocol.fromScheme(Uri.parse(url).scheme),
            format: SourceFormat.fromUri(Uri.parse(url)),
            mediaType: SourceMediaType.video,
          ),
        )
        .toList(growable: false);

    if (items.isEmpty) {
      return;
    }

    _log.add('loading ${items.length} item(s)');

    await _feed.load(items);

    if (mounted) {
      setState(() {});
      _pages.jumpToPage(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = _feed.handle;
    final items = _feed.items;

    return DemoPageScaffold(
      title: '信息流 / Feed',
      subtitle: '整个 feed 共用一个播放器：滑动 = 换源，只有当前页挂载视频控件；下一条自动预热。',
      log: _log,
      actions: [
        FilledButton.icon(onPressed: _load, icon: const Icon(Icons.playlist_play), label: const Text('加载并播放')),
        OutlinedButton(onPressed: _feed.previous, child: const Text('上一条')),
        OutlinedButton(onPressed: _feed.next, child: const Text('下一条')),
        OutlinedButton(onPressed: _feed.pause, child: const Text('暂停')),
        OutlinedButton(onPressed: _feed.play, child: const Text('继续')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 420,
            child: items.isEmpty
                ? const Center(child: Text('点“加载并播放”开始'))
                : PageView.builder(
                    controller: _pages,
                    scrollDirection: Axis.vertical,
                    itemCount: items.length,
                    onPageChanged: (index) => _feed.showIndex(index),
                    itemBuilder: (context, index) {
                      final isCurrent = index == _feed.currentIndex;

                      return ColoredBox(
                        color: Colors.black,
                        child: isCurrent && handle != null
                            // The visible page owns the single video widget;
                            // the others are placeholders, exactly as a real
                            // feed does it.
                            ? MediaPlayerView(handle: handle)
                            : Center(
                                child: Text(
                                  '#${index + 1}',
                                  style: const TextStyle(color: Colors.white24, fontSize: 48),
                                ),
                              ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urls,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: '每行一条视频地址 / one URL per line',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '当前 / current: ${_feed.currentIndex + 1}/${items.length}'
            '   状态 / state: ${_feed.itemState.name}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
