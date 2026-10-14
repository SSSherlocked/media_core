import 'dart:async';

import 'package:example/demos/fakes/fake_pool_player.dart';
import 'package:example/language.dart';
import 'package:example/ui/demo_log.dart';
import 'package:example/ui/demo_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_danmaku/media_core_danmaku.dart';
import 'package:media_core_multiview/media_core_multiview.dart';

/// A monitoring wall, driven by fake players.
///
/// Real walls are expensive to try: every cell is a decoder, and the interesting
/// behaviour only shows up with a handful of live streams running. The wall's
/// logic, though, sits entirely on top of [PoolPlayerHost] — so this page runs
/// the real controller over fake players, and everything worth understanding
/// (focus, audio exclusivity, the decode budget, the stall watchdog, per-cell
/// danmaku) is observable on a laptop with no network.
class MultiviewDemoPage extends StatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  State<MultiviewDemoPage> createState() => _MultiviewDemoPageState();
}

final class _MultiviewDemoPageState extends State<MultiviewDemoPage> {
  final DemoLog _log = DemoLog();

  late final FakePoolPlayerHost _host;
  late final MultiviewController _wall;
  StreamSubscription<MultiviewSnapshot>? _sub;

  MultiviewSnapshot? _snapshot;
  int _danmakuFeed = 0;

  /// Rooms the wall pretends to watch.
  static const List<String> _rooms = <String>[
    'gate-north',
    'gate-south',
    'parking-a',
    'parking-b',
    'loading-dock',
    'lobby',
    'roof',
    'server-room',
    'corridor-3',
  ];

  @override
  void initState() {
    super.initState();

    _host = FakePoolPlayerHost(openDelay: const Duration(milliseconds: 40));
    _wall = MultiviewController(
      players: _host,
      config: MultiviewConfig.defaults.copyWith(
        layout: MultiviewLayout.quad,
        maxCells: 4,
        // The watchdog would declare a frozen cell stalled after 15s; the demo
        // keeps the default and lets the developer trigger a stall on purpose.
        patrolInterval: const Duration(seconds: 5),
      ),
    );

    _snapshot = _wall.snapshot;
    _sub = _wall.onChanged.listen((snapshot) {
      if (!mounted) {
        return;
      }
      setState(() => _snapshot = snapshot);
    });

    _log
      ..add('wall created: 4 cells, audio mode exclusive, budget policy keepFocusedOnly')
      ..add('players are fake: no decoder, no network — the wall logic is the real one');
  }

  @override
  void dispose() {
    // dispose() is synchronous: these async teardowns are fire-and-forget.
    unawaited(_sub?.cancel());
    unawaited(_wall.dispose());
    unawaited(_host.disposeAll());
    _log.dispose();

    super.dispose();
  }

  MultiviewCellSource _sourceFor(int index) {
    final room = _rooms[index % _rooms.length];
    return MultiviewCellSource(
      roomId: room,
      title: room,
      qualityLabel: index == _wall.focusedIndex ? '1080p' : '480p',
      source: PlayerSource(
        id: SourceId('room-$index'),
        uri: Uri.parse('https://example.com/live/$room.m3u8'),
        type: SourceType.remote,
        mediaType: SourceMediaType.video,
      ),
    );
  }

  Future<void> _fill() async {
    await _wall.assignAll(<MultiviewCellSource>[
      for (var index = 0; index < _wall.config.layout.capacity; index++) _sourceFor(index),
    ]);

    _log.add(
      'assigned ${_wall.cells.where((cell) => !cell.isEmpty).length} cell(s); '
      'quality policy gives the focused cell the best rendition',
    );
  }

  Future<void> _setLayout(MultiviewLayout layout) async {
    await _wall.updateConfig(_wall.config.copyWith(layout: layout, maxCells: layout.capacity));
    _log.add('layout → ${layout.name} (${layout.capacity} cells)');
    await _fill();
  }

  Future<void> _focus(int index) async {
    await _wall.setVideoFocus(index);
    await _wall.setAudioFocus(index);
    _log.add(
      'focus → cell $index (${_wall.cells[index].source?.roomId}): '
      'video focus decides the large cell and the danmaku, audio focus decides who is audible',
    );
  }

  Future<void> _reportPressure(ResourcePressure pressure) async {
    await _wall.reportPressure(pressure);
    _log.add(
      'pressure ${pressure.label} → '
      '${_wall.snapshot.budgetExceeded ? 'over budget: policy keeps only the focused cell playing' : 'within budget'}',
    );
  }

  Future<void> _stallCell(int index) async {
    final handle = _host.handles.isEmpty ? null : _host.handles.elementAtOrNull(index);
    handle?.stall();
    _log.add(
      'cell $index player frozen — the watchdog declares a stall after '
      '${_wall.config.cellStallTimeout.inSeconds}s and restarts it '
      '(up to ${_wall.config.cellMaxRestarts} times)',
    );
  }

  Future<void> _togglePatrol() async {
    if (_wall.config.patrolEnabled) {
      _wall.stopPatrol();
      _log.add('patrol stopped');
      return;
    }

    _wall.startPatrol();
    _log.add(
      'patrol started: focus rotates every ${_wall.config.patrolInterval.inSeconds}s, '
      'skipping offline cells',
    );
  }

  /// Feeds the focused cell's danmaku queue, which is where a wall routes them.
  void _feedDanmaku() {
    final session = _wall.ensureDanmakuFor(_wall.focusedIndex);
    _log.add('focused cell danmaku session: queue=${session.length}, active=${session.isActive}');

    // A wall's overlay is only active when its surface is visible; binding it is
    // the host's job, and this is what that looks like.
    session.bindVisibility(Stream<bool>.value(true));

    for (var index = 0; index < 5; index++) {
      session.enqueue(
        DanmakuMessage(
          type: DanmakuMessageType.chat,
          userName: 'demo-viewer',
          text: 'danmaku #${++_danmakuFeed} on ${_wall.cells[_wall.focusedIndex].source?.roomId}',
          messageId: 'demo-$index',
          sentAt: DateTime.now(),
        ),
        surfaceWidth: 320,
        now: DateTime.now(),
      );
    }

    final account = MediaCoreMemory.report().forModule(MemoryModule.multiview);
    _log.add(
      'wall memory account: ${account?.items ?? 0} cell(s), ${account?.bytes ?? 0} bytes declared '
      '— "${account?.note}"',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isZh = DemoLanguageScope.of(context) == DemoLanguage.zh;
    final snapshot = _snapshot;
    final layout = _wall.config.layout;

    return DemoPageScaffold(
      title: isZh ? '多画面同看 / Multiview' : 'Multiview',
      subtitle: isZh ? '监控式视频墙：格子健康度、唯一音频归属、解码预算、卡顿重启、巡更轮巡、逐格弹幕。播放器是假的，墙的逻辑是真的。' : 'A monitoring wall: per-cell health, one audible cell, a decode budget, stall restarts, patrol and per-cell danmaku. The players are fake; the wall is not.',
      log: _log,
      logHeight: 140,
      actions: <Widget>[
        FilledButton.icon(
          onPressed: _fill,
          icon: const Icon(Icons.grid_view),
          label: Text(isZh ? '填充画面' : 'Fill cells'),
        ),
        OutlinedButton(onPressed: () => _setLayout(MultiviewLayout.quad), child: const Text('2×2')),
        OutlinedButton(onPressed: () => _setLayout(MultiviewLayout.nine), child: const Text('3×3')),
        OutlinedButton(
          onPressed: _togglePatrol,
          child: Text(_wall.config.patrolEnabled ? (isZh ? '停止巡更' : 'Stop patrol') : (isZh ? '开始巡更' : 'Start patrol')),
        ),
        OutlinedButton(
          onPressed: () => _reportPressure(ResourcePressure.critical),
          child: Text(isZh ? '设备压力 critical' : 'Pressure: critical'),
        ),
        OutlinedButton(
          onPressed: () => _reportPressure(ResourcePressure.none),
          child: Text(isZh ? '压力解除' : 'Pressure: none'),
        ),
        OutlinedButton(
          onPressed: () => _stallCell(_wall.focusedIndex),
          child: Text(isZh ? '冻结聚焦格' : 'Freeze focused cell'),
        ),
        OutlinedButton(onPressed: _feedDanmaku, child: Text(isZh ? '喂弹幕给聚焦格' : 'Feed danmaku')),
        OutlinedButton(
          onPressed: () async {
            await _wall.clearAll();
            _log.add(
              'wall cleared: every player went back to the host '
              '(${_host.summary()})',
            );
          },
          child: Text(isZh ? '清空' : 'Clear'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Chip(label: Text('${layout.name} · ${_wall.cells.length} cells')),
              const SizedBox(width: 8),
              Chip(
                label: Text('focused #${_wall.focusedIndex}'),
                backgroundColor: Colors.indigo.withValues(alpha: 0.15),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text('audio ${snapshot?.audioIndex ?? '—'} (${_wall.config.audioMode.name})'),
                backgroundColor: Colors.teal.withValues(alpha: 0.15),
              ),
              const SizedBox(width: 8),
              if (snapshot != null && snapshot.budgetExceeded)
                const Chip(label: Text('over budget'), backgroundColor: Color(0x22FF0000)),
            ],
          ),
          const SizedBox(height: 12),
          _Grid(wall: _wall, onTap: _focus),
          const SizedBox(height: 12),
          Text(
            isZh
                ? '点格子切换焦点。唯一音频归属意味着同一时刻只有一个格子出声，其余按 backgroundVolume 处理；卡顿恢复有独立预算，一个坏掉的格子不会拖垮整面墙。'
                : 'Tap a cell to focus it. One audible cell at a time; the rest follow backgroundVolume. '
                      'Stall recovery has its own per-cell budget, so one dead stream does not take the wall down.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            isZh ? '播放器账本：${_host.summary()}' : 'PlayerIdentity ledger: ${_host.summary()}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// The wall itself, laid out from the controller's own layout.
class _Grid extends StatelessWidget {
  const new({required this.wall, required this.onTap});

  final MultiviewController wall;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    final cells = wall.cells;
    final columns = wall.config.layout.columns;

    if (cells.isEmpty) {
      return const SizedBox.shrink();
    }

    // The focus layout is not a grid; a plain wrap keeps the demo honest about
    // what it is rendering without re-implementing the host's own layout code.
    if (columns == 1 && cells.length > 1) {
      return Column(
        children: <Widget>[
          for (final cell in cells)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CellTile(cell: cell, onTap: onTap, tall: cell.index == wall.focusedIndex),
            ),
        ],
      );
    }

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 16 / 10,
      children: <Widget>[for (final cell in cells) _CellTile(cell: cell, onTap: onTap)],
    );
  }
}

/// One cell: what it plays, how healthy it is, and what it owns.
class _CellTile extends StatelessWidget {
  const new({required this.cell, required this.onTap, this.tall = false});

  final MultiviewCell cell;
  final void Function(int index) onTap;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final color = switch (cell.status) {
      MultiviewCellStatus.playing => Colors.green,
      MultiviewCellStatus.starting => Colors.blue,
      MultiviewCellStatus.recovering => Colors.orange,
      MultiviewCellStatus.failed => Colors.red,
      MultiviewCellStatus.offline => Colors.grey,
      MultiviewCellStatus.empty => Colors.black26,
      MultiviewCellStatus.paused => Colors.pink,
    };

    return GestureDetector(
      onTap: () => onTap(cell.index),
      child: Container(
        height: tall ? 160 : null,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: cell.hasVideoFocus ? Colors.indigoAccent : Colors.white24,
            width: cell.hasVideoFocus ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '#${cell.index}',
                  style: const TextStyle(fontFamily: 'monospace', color: Colors.white70, fontSize: 11),
                ),
                const Spacer(),
                if (cell.hasAudioFocus) const Icon(Icons.volume_up, size: 14, color: Colors.tealAccent),
                if (cell.hasVideoFocus) const Icon(Icons.crop_free, size: 14, color: Colors.indigoAccent),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              cell.source?.roomId ?? '—',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(cell.status.name, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                const Spacer(),
                if (cell.qualityLabel != null)
                  Text(cell.qualityLabel!, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                if (cell.restarts > 0)
                  Text(' ↻${cell.restarts}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 10)),
              ],
            ),
            if (cell.failure != null)
              Text(
                cell.failure!.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.redAccent, fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }
}
