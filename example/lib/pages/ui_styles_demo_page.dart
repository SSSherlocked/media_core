import 'dart:async';
import 'dart:io';

import 'package:example/pages/player_demo_page.dart' show kSampleSources;
import 'package:example/ui/demo_log.dart';
import 'package:example/ui/demo_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';
import 'package:media_core_ui/media_core_ui.dart';

/// One player, six design languages, switched live.
///
/// The control sets in `media_core_ui` share a single control layer, so
/// switching languages mid-playback is exactly what it looks like: the state,
/// the position and the visibility policy stay, the bars change. This page is
/// how a host decides which language it wants, and the quickest way to check
/// that a themed override lands where it should.
///
/// It also demonstrates the two newer surfaces that belong to the same picture:
/// the pinch/double-tap zoom (with the controller readable and resettable) and
/// the screenshot capture (with the saved path in the log, which is the only
/// way to tell "captured" from "wrote a file somewhere").
class UiStylesDemoPage extends StatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  State<UiStylesDemoPage> createState() => _UiStylesDemoPageState();
}

final class _UiStylesDemoPageState extends State<UiStylesDemoPage> {
  final DemoLog _log = DemoLog();
  final TextEditingController _url = TextEditingController(text: kSampleSources.first.url);
  final VideoZoomController _zoom = VideoZoomController();
  final ScreenshotWriter _writer = const ScreenshotWriter();

  late final PlayerKernel _kernel;
  PlayerHandle? _handle;

  /// Null means "whatever the platform expects"; the picker sets a language.
  PlayerControlsStyle? _style;

  StreamSubscription<PlayerTransportState>? _playbackSub;
  StreamSubscription<PlayerScreenshot>? _screenshotSub;

  @override
  void initState() {
    super.initState();

    _kernel = PlayerKernel();
    _kernel.registerBackend(const MediaKitAdapterFactory().registration());

    _log.add('backend registered: ${_kernel.registry.ids.join(', ')}');
    _log.add('style: platform default (${PlayerControlsStyle.resolve().name})');
  }

  @override
  void dispose() {
    // dispose() is synchronous: these async teardowns are fire-and-forget.
    unawaited(_playbackSub?.cancel());
    unawaited(_screenshotSub?.cancel());

    _zoom.dispose();
    unawaited(_handle?.dispose());
    unawaited(_kernel.dispose());
    _url.dispose();
    _log.dispose();

    super.dispose();
  }

  Future<void> _open() async {
    final previous = _handle;

    if (previous != null) {
      await _playbackSub?.cancel();
      await _screenshotSub?.cancel();
      await previous.dispose();
    }

    final source = PlayerSource(
      id: SourceId.generate(),
      uri: Uri.parse(_url.text.trim()),
      title: _url.text.trim().split('/').last,
    );

    final handle = await _kernel.create(source: source, config: const PlayerConfig(autoPlay: true));

    if (!mounted) {
      await handle.dispose();

      return;
    }

    setState(() => _handle = handle);

    _zoom.reset();

    var readyOnce = false;

    _playbackSub = handle.stateChanges.listen((state) {
      // The facts table reads readiness, not position — and this stream ticks
      // about four times a second while playing, so a bare `setState` here
      // rebuilt the page (video view, styles, log) for the whole session.
      // One refresh when the duration first lands is all the table asks for.
      if (readyOnce || !state.hasDuration) {
        return;
      }

      readyOnce = true;

      if (mounted) {
        setState(() {});
      }
    });

    // Every capture, including the ones a host triggers elsewhere, arrives here.
    _screenshotSub = handle.screenshots.listen((screenshot) {
      _log.add(
        'screenshot: ${screenshot.format.name} ${screenshot.width}x${screenshot.height} '
        '${screenshot.sizeInKilobytes.toStringAsFixed(1)} kB via ${screenshot.source.name}',
      );
    });

    _log.add('opened ${source.uri} (backend ${handle.backendId})');

    if (handle.canCaptureScreenshot) {
      _log.add('capture route available: ${handle.adapter.capabilities.supportsScreenshot ? 'engine' : 'surface'}');
    }
  }

  Future<void> _saveScreenshot() async {
    final handle = _handle;

    if (handle == null) {
      return;
    }

    final screenshot = await handle.captureScreenshot();

    if (screenshot == null) {
      _log.add('capture returned nothing (no route produced a frame)');

      return;
    }

    try {
      final directory = await Directory.systemTemp.createTemp('media_core_ui_shot');
      final path = await _writer.save(screenshot, directory: directory.path);

      _log.add('saved ${screenshot.format.fileExtension.toUpperCase()} → $path');
    } on Object catch (_) {
      // Web has no file system; the bytes are the deliverable there. The catch
      // is Object rather than UnsupportedError because the analyzer rejects
      // catching Error subclasses, and Directory.systemTemp throws one here.
      _log.add('no file system here; keeping ${screenshot.sizeInBytes} bytes in memory');
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle;
    final style = _style;
    final effective = style ?? PlayerControlsStyle.resolve();

    return DemoPageScaffold(
      title: '播放器界面风格 / PlayerIdentity UI styles',
      subtitle:
          '六套设计语言共用一层控制逻辑：切换风格时播放状态、进度与显隐策略都不重置。'
          ' · Six design languages over one control layer; switching keeps state, position and visibility policy.',
      log: _log,
      actions: <Widget>[
        FilledButton.icon(onPressed: _open, icon: const Icon(Icons.play_circle_outline), label: const Text('打开并播放')),
        OutlinedButton.icon(
          onPressed: handle == null ? null : _saveScreenshot,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('截图并保存'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            _zoom.reset();
            _log.add('zoom reset');
          },
          icon: const Icon(Icons.zoom_out_map),
          label: const Text('复位缩放'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The video the styles are drawn on top of.
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: handle == null
                  ? const Center(
                      child: Text('打开一个地址后出现画面', style: TextStyle(color: Colors.white70)),
                    )
                  : MediaCorePlayerView(
                      handle: handle,
                      // Null lets the platform decide; the chips below force one.
                      style: _style,
                      zoom: _zoom,
                      actions: KernelPlayerControlActions(kernel: _kernel, playerId: handle.id),
                      onTapVideo: () => _log.add('tap on the picture'),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text('设计语言 / Design language', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const Text('跟随平台 / Platform'),
                selected: style == null,
                onSelected: (_) {
                  setState(() => _style = null);
                  _log.add('style → platform default (${PlayerControlsStyle.resolve().name})');
                },
              ),
              for (final candidate in PlayerControlsStyle.values)
                ChoiceChip(
                  label: Text('${candidate.name}${candidate.isTouch ? ' · touch' : ' · pointer'}'),
                  selected: style == candidate,
                  onSelected: (_) {
                    setState(() => _style = candidate);
                    _log.add(
                      'style → ${candidate.name}'
                      '${candidate.showsVolumeSlider ? ' (volume slider)' : ' (hardware volume)'}'
                      '${candidate.revealsOnHover ? ', hover reveal' : ''}',
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Facts(style: effective, theme: PlayerControlsTheme.of(effective), zoom: _zoom, handle: handle),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: const InputDecoration(labelText: '视频地址 / URL', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final sample in kSampleSources)
                ActionChip(label: Text(sample.label), onPressed: () => setState(() => _url.text = sample.url)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '手势 / Gestures: 双指捏合缩放、双击缩放（触摸语言）、拖动平移；桌面语言双击进全屏，空格 / ←→ / m / f 为键盘快捷键。 · Pinch and double-tap zoom, drag to pan on touch languages; '
            'pointer languages use a double click for fullscreen and the keyboard map (space, arrows, m, f).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// What the current language and player are doing, in numbers.
///
/// A small table, because the interesting part of a control set is invisible:
/// which conventions it declares (volume slider, hover reveal, double-tap
/// action), which glyph/button skin it drew, and where the zoom and the
/// capture route stand right now.
final class _Facts extends StatelessWidget {
  const new({required this.style, required this.theme, required this.zoom, required this.handle});

  final PlayerControlsStyle style;
  final PlayerControlsTheme theme;
  final VideoZoomController zoom;
  final PlayerHandle? handle;

  @override
  Widget build(BuildContext context) {
    final handle = this.handle;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _row('design language', '${style.name} (${style.isTouch ? 'touch-first' : 'pointer-first'})'),
            _row('volume', style.showsVolumeSlider ? 'slider in the bar' : 'hardware keys'),
            _row('controls reveal', style.revealsOnHover ? 'on hover' : 'on tap, idle auto-hide'),
            _row('double tap', PlayerDoubleTapAction.forStyle(style).name),
            _row('button skin', theme.buttonSkin.name),
            _row('progress', '${theme.progressThumbShape.name} thumb on a ${theme.progressTrackShape.name} track'),
            _row('blur', theme.blur == null ? 'none' : theme.blur!.toStringAsFixed(0)),
            ListenableBuilder(
              listenable: zoom,
              builder: (context, _) {
                return _row('zoom', '${zoom.scale.toStringAsFixed(2)}x  ${zoom.isZoomed ? '(zoomed)' : '(natural)'}');
              },
            ),
            _row(
              'capture',
              handle == null
                  ? 'no player'
                  : handle.canCaptureScreenshot
                  ? 'available (${handle.adapter.capabilities.supportsScreenshot ? 'engine' : 'surface'})'
                  : 'unavailable',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: <Widget>[
          SizedBox(width: 150, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
