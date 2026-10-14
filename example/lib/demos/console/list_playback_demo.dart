import 'package:example/demos/module_demo.dart';
import 'package:media_core/media_core.dart' show PlayerSource, SourceId;
import 'package:media_core_list_playback/media_core_list_playback.dart';

/// List playback: switching items and remembering where the viewer was.
///
/// The distinctive part is not the switch — a feed does that too — but the
/// *memory*: progress is written on the way out and read on the way in, with one
/// rule that matters most. An item abandoned inside its final seconds resumes
/// from the start, because restoring the last five seconds reads as a broken
/// player rather than as a feature. A fake player makes that rule observable in
/// a few lines, with no media and no backend.
class ListPlaybackDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'list';

  @override
  ModuleCategory get category => ModuleCategory.playbackChain;

  @override
  String get nameZh => '列表播放：进度记忆与续播规则';

  @override
  String get nameEn => 'List playback: remembered positions and the resume rule';

  @override
  String get purposeZh =>
      '列表只驱动"一个播放器"：切换时先保存当前项进度再打开下一项，返回时 seek 回记忆位置。接近看完（默认最后 15 秒内）的条目视为已看完，从头播——这是"恢复最后五秒"与"看起来像坏了"之间的分界。';

  @override
  String get purposeEn =>
      'The list drives one player: a switch saves the outgoing item\'s position first, and returning seeks back to it. An item abandoned inside the completion threshold (15 seconds by default) counts as finished and restarts, which is the line between "restored the last five seconds" and "looks broken".';

  @override
  List<String> get pointsZh => const <String>[
    'next() / previous() / jumpTo() — 都先 savePosition() 再 open()，顺序就是语义',
    'resumedFrom 出现在状态里：宿主可以提示"已从 3:20 继续"，而不是猜',
    'isNearCompletion(position, duration) — 直播（duration 为 0）永远不算看完',
    'PlaybackListItem.id 与 source 分离：同一个流出现在两条目下不共享进度',
    'store 可换成持久实现（InMemoryPlaybackProgressStore 只是默认）',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'next() / previous() / jumpTo() all savePosition() before open() — the order is the semantics',
    'resumedFrom is part of the state, so a host can say "resumed at 3:20" instead of guessing',
    'isNearCompletion(position, duration) — a live stream (zero duration) is never finished',
    'PlaybackListItem.id is separate from its source: the same stream under two ids does not share progress',
    'The store is replaceable; InMemoryPlaybackProgressStore is only the default',
  ];

  @override
  String get snippet => '''
final list = PlaybackListController(
  player: myPlayer,                       // or pool: + poolPlayerFactory:
  items: items,
  config: const PlaybackListConfig(completionThreshold: Duration(seconds: 15)),
);

await list.open(index: 2);
await list.savePosition();                // on the way out
await list.next();                        // saves, then opens index 3
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();

    /// The state stream delivers asynchronously: printing right after an awaited
    /// transition would still show the previous state.
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

    final player = _FakeListPlayer();
    final items = <PlaybackListItem>[
      for (final episode in <String>['ep1', 'ep2', 'ep3'])
        PlaybackListItem(
          id: episode,
          title: episode,
          source: PlayerSource(id: SourceId(episode), uri: Uri.parse('https://example.com/$episode.mp4')),
        ),
    ];

    final list = PlaybackListController(
      player: player,
      items: items,
      config: const PlaybackListConfig(completionThreshold: Duration(seconds: 15)),
    );

    final states = <String>[];
    final subscription = list.onStateChanged.listen((state) {
      if (state.opening) {
        return;
      }
      states.add(
        '${state.item?.id ?? '—'}'
        '${state.resumedFrom == null ? ' (from 0:00)' : ' (resumed at ${_mmss(state.resumedFrom!)})'}',
      );
    });

    try {
      buffer.writeln('three items, completion threshold 15s, one fake player:');

      await list.open();
      player.position = const Duration(minutes: 3, seconds: 20);

      await list.next();
      player.position = const Duration(minutes: 1, seconds: 5);

      await list.next();
      player.position = const Duration(minutes: 42); // abandoned near the end
      await settle();

      buffer
        ..writeln('  ${states.join(' → ')}')
        ..writeln();

      // Back to the second item: the position it was left at comes back.
      await list.previous();

      // And to the third: it was left 18s before the end, inside the 15s
      // threshold... at 42:00 of a 42:15 file, so it restarts.
      await list.next();
      await settle();

      buffer
        ..writeln('  going back and forth (each line is the state the switch landed on):')
        ..writeln('    previous() → ${states[states.length - 2]}')
        ..writeln('    next()     → ${states.last} — it was left 10s before the end,')
        ..writeln('                 inside the 15s threshold, so it starts over instead of')
        ..writeln('                 restoring ten seconds of video.')
        ..writeln();

      final nearEnd = list.isNearCompletion(
        const Duration(minutes: 42, seconds: 5),
        const Duration(minutes: 42, seconds: 15),
      );
      final live = list.isNearCompletion(const Duration(hours: 2), Duration.zero);

      buffer
        ..writeln('  the rule, stated directly:')
        ..writeln('    42:05 of 42:15 → near completion = $nearEnd (restart, do not restore 10s)')
        ..writeln('    2:00:00 of a live stream (duration 0) → near completion = $live')
        ..writeln('      a live stream has no end to be near, so it always resumes')
        ..writeln();

      // The store is what survives a process; the demo can show it directly.
      await list.savePosition();
      await list.clearProgress();
      await list.open();
      await settle();

      buffer
        ..writeln('  after clearProgress(), reopening ep1 → ${states.last}')
        ..writeln('    clearProgress() is the "clear watch history" button;')
        ..writeln('    savePosition() is what the host calls when the viewer leaves the list.')
        ..writeln()
        ..writeln('  the list never disposes the player it drives: it belongs to the host,')
        ..writeln('  and a page and a list can share one.');
    } finally {
      await subscription.cancel();
      await list.dispose();
    }

    return buffer.toString();
  }

  static String _mmss(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// A player that only remembers where it was told to be.
///
/// The list's resume logic is entirely about position and duration, so this is
/// all a fake needs to provide — and it is why the rule can be demonstrated
/// without decoding a single frame.
final class _FakeListPlayer implements PlaybackListPlayer {
  /// Where the pretend viewer is, as [PlaybackListPlayer.position].
  ///
  /// The demo sets it directly to stand in for watching; [open] and [seek] then
  /// move it the way a real player would, which is what the resume rule reads.
  @override
  Duration position = Duration.zero;

  final Duration _duration = const Duration(minutes: 42, seconds: 15);

  /// Every call the list made, in order.
  final List<String> calls = <String>[];

  @override
  Future<void> open(PlayerSource source) async {
    calls.add('open(${source.id})');
    position = Duration.zero;
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek(${_mmss(position)})');
    this.position = position;
  }

  @override
  Duration get duration => _duration;

  static String _mmss(Duration duration) =>
      '${duration.inMinutes}:'
      '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
}
