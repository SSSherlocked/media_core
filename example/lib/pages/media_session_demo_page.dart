import 'dart:async';

import 'package:example/pages/player_demo_page.dart' show kSampleSources;
import 'package:example/ui/demo_log.dart';
import 'package:example/ui/demo_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';
import 'package:media_core_mediasession/media_core_mediasession.dart';

/// A video player with a system media surface — and no wiring on this page.
///
/// The app enabled the surfaces once in `main()`
/// (`MediaSessionBootstrap.enable()`), and every kernel created afterwards takes
/// the driver by itself, so this page plays a *video* and still appears in the
/// notification shade, on the lock screen, in Windows' SMTC overlay and in
/// GNOME's media applet: the title, the progress and the controls come from the
/// handle, and pressing them drives the same handle. The log below is that round
/// trip; the button turns the surfaces off and on again so the difference is one
/// tap away.
///
/// Android needs the `audio_service` manifest entries and, on API 33+, the
/// notification permission; the package README lists them. On a platform where
/// the surface cannot appear, the driver still publishes state, so this page
/// stays a truthful demonstration of what the host would see.
class MediaSessionDemoPage extends StatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  State<MediaSessionDemoPage> createState() => _MediaSessionDemoPageState();
}

final class _MediaSessionDemoPageState extends State<MediaSessionDemoPage> {
  final DemoLog _log = DemoLog();
  final TextEditingController _url = TextEditingController(text: kSampleSources.first.url);

  late final PlayerKernel _kernel;

  PlayerHandle? _handle;
  // Typed as void on purpose: the surface's own state types collide with
  // media_core's, and these subscriptions are only ever cancelled.
  StreamSubscription<void>? _itemSub;
  StreamSubscription<void>? _stateSub;

  bool _busy = false;

  @override
  void initState() {
    super.initState();

    // No attachAudio call: the kernel takes the process-wide driver while it is
    // being constructed, which is the whole point of this page.
    _kernel = PlayerKernel();
    _kernel.registerBackend(const MediaKitAdapterFactory().registration());

    _log
      ..add('kernel created — driver attached automatically (${MediaSessionBootstrap.current})')
      ..add(
        'the platform was told to show: play/pause · ±'
        '${const MediaSessionConfig().seekStep.inSeconds}s · stop',
      );

    _observeSurface();
  }

  @override
  void dispose() {
    // dispose() is synchronous: these async teardowns are fire-and-forget.
    unawaited(_itemSub?.cancel());
    unawaited(_stateSub?.cancel());

    unawaited(_handle?.dispose());
    unawaited(_kernel.dispose());
    _url.dispose();
    _log.dispose();

    super.dispose();
  }

  /// Logs what the platform is being told.
  ///
  /// The media item changes when a source opens; the playback state arrives with
  /// every progress tick, so it is logged on *transitions* (playing flag, control
  /// count, processing state) plus position jumps — which is also where a pressed
  /// notification button shows up: the platform sends the command, the handle
  /// acts, and the change comes back here.
  void _observeSurface() {
    final handler = MediaSessionBootstrap.current?.handler;

    if (handler == null) {
      _log.add('no handler: the surfaces are off (or the platform refused to start)');

      return;
    }

    _itemSub = handler.mediaItem.listen((item) {
      _log.add('surface ← item: ${item?.title ?? '(cleared)'}  art=${item?.artUri?.pathSegments.last ?? 'none'}');

      // The rows below read the live surface, so a change there is what asks
      // for a repaint — not the transport ticks that used to drive this page.
      if (mounted) {
        setState(() {});
      }
    });

    var lastSignature = '';
    var lastPosition = Duration.zero;

    _stateSub = handler.playbackState.listen((state) {
      final signature = '${state.playing}|${state.controls.length}|${state.processingState.name}';

      if (signature != lastSignature) {
        lastSignature = signature;

        _log.add(
          'surface ← state: ${state.playing ? 'playing' : 'paused'}, '
          '${state.controls.length} controls, ${state.processingState.name}',
        );

        lastPosition = state.updatePosition;

        if (mounted) {
          setState(() {});
        }

        return;
      }

      // A jump larger than a progress tick means the position moved — by the
      // ±10s buttons as much as by the UI.
      final delta = (state.updatePosition - lastPosition).abs();

      if (delta > const Duration(milliseconds: 1500)) {
        _log.add('surface ← seek: ${lastPosition.inSeconds}s → ${state.updatePosition.inSeconds}s');

        lastPosition = state.updatePosition;
      }
    });
  }

  Future<void> _toggleSurfaces() async {
    if (_busy) {
      return;
    }

    setState(() => _busy = true);

    try {
      if (MediaSessionBootstrap.enabled) {
        await MediaSessionBootstrap.disable();

        _log.add(
          'surfaces off: the notification clears itself, and this kernel stops publishing '
          '(it is already created, so re-enabling needs attachTo)',
        );
      } else {
        // A kernel created while the surfaces were off does not pick them up by
        // itself — `attachTo` is the path for exactly that case.
        final driver = await MediaSessionBootstrap.attachTo(_kernel);

        _log.add('surfaces on again: ${driver.active?.id.value ?? 'no active player yet'}');
      }
    } on Object catch (error) {
      _log.add('toggle failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open() async {
    final previous = _handle;

    if (previous != null) {
      await previous.dispose();
    }

    final url = _url.text.trim();
    final source = PlayerSource(id: SourceId.generate(), uri: Uri.parse(url), title: url.split('/').last);

    final handle = await _kernel.create(source: source, config: const PlayerConfig(autoPlay: true));

    if (!mounted) {
      await handle.dispose();

      return;
    }

    setState(() => _handle = handle);

    _log.add('opened ${handle.id.value} (backend ${handle.backendId}) — the surface follows it automatically');
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle;
    final driver = MediaSessionBootstrap.current;

    return DemoPageScaffold(
      title: '系统媒体面：自动挂载的通知 / 锁屏 / SMTC',
      subtitle:
          'main() 里一行 enable()，之后每个播放器都自动接上系统媒体面：视频、音乐、feed 都一样。播一会儿，再看设备的通知栏（Windows 的音量浮层、GNOME 的媒体部件也行）——按上面的按钮，下面的日志会出现对应的状态变化。'
          ' · One enable() at app start, every player after that publishes itself. Play, then press the '
          "notification's buttons and watch the transitions land in the log below.",
      log: _log,
      actions: <Widget>[
        FilledButton.icon(onPressed: _open, icon: const Icon(Icons.play_circle_outline), label: const Text('打开并播放')),
        OutlinedButton.icon(
          onPressed: _busy ? null : _toggleSurfaces,
          icon: Icon(
            MediaSessionBootstrap.enabled ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
          ),
          label: Text(MediaSessionBootstrap.enabled ? '关闭媒体面' : '重新开启媒体面'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: handle == null
                  ? const Center(
                      child: Text('打开一个地址后出现画面', style: TextStyle(color: Colors.white70)),
                    )
                  : MediaPlayerView(handle: handle),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _row('surfaces', MediaSessionBootstrap.enabled ? 'enabled (app-wide)' : 'off'),
                  _row('driver', driver?.toString() ?? 'none'),
                  _row('active player', driver?.active?.id.value ?? 'none'),
                  _row('channel', driver?.config.androidNotificationChannelId ?? '—'),
                  _row(
                    'controls',
                    driver == null
                        ? '—'
                        : driver.skipToNextHandler != null
                        ? 'previous · play/pause · next · stop'
                        : 'play/pause · ±${driver.config.seekStep.inSeconds}s · stop',
                  ),
                  _row('title shown', handle?.source?.hasTitle == true ? handle!.source!.title! : '—'),
                  _row('artwork', driver?.artUriResolver == null ? 'source metadata only' : 'resolver installed'),
                ],
              ),
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
            children: <Widget>[
              for (final sample in kSampleSources)
                ActionChip(label: Text(sample.label), onPressed: () => setState(() => _url.text = sample.url)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: <Widget>[
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
