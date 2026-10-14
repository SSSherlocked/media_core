import 'package:example/demos/module_demo.dart';
import 'package:media_core_audio/media_core_audio.dart';

/// Queue rules and play modes.
///
/// The four modes are the part of a music player that users notice immediately
/// when they are wrong (a "next" that wraps when it should stop, a shuffle that
/// repeats a track, a previous that cannot retrace), so the demo exercises them
/// explicitly instead of describing them.
class QueueDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'queue';

  @override
  ModuleCategory get category => ModuleCategory.control;

  @override
  String get nameZh => '播放队列与播放模式';

  @override
  String get nameEn => 'Queue & play modes';

  @override
  String get purposeZh => 'PlayQueue 持有顺序、游标与随机排列；PlayMode 区分顺序 / 列表循环 / 单曲循环 / 随机。随机用预生成排列，因此一轮不重复且 previous() 能真正回溯。';

  @override
  String get purposeEn =>
      'PlayQueue holds the order, the cursor and the shuffled permutation; PlayMode distinguishes list / list-loop / single-loop / random. Random precomputes a permutation, so a pass does not repeat and previous() retraces reality.';

  @override
  List<String> get pointsZh => const <String>[
    'queue.indexAfter(automatic: true) — 自动续播：单曲循环回自身，顺序播放在末尾停止',
    'queue.indexAfter(automatic: false) — 用户按下一首：不在末尾静默回绕',
    'append / insertNext(下一首播放) / removeAt / jumpTo',
    '随机模式返回的排列可枚举，便于调试"为什么放了这首"',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'queue.indexAfter(automatic: true) — auto advance: single-loop repeats, list stops at the end',
    'queue.indexAfter(automatic: false) — user pressed next: no silent wrap at the end',
    'append / insertNext (play next) / removeAt / jumpTo',
    'The shuffled permutation is enumerable, which answers "why did it play this"',
  ];

  @override
  String get snippet => '''
final queue = PlayQueue(tracks: tracks, mode: PlayMode.random);

final auto = queue.indexAfter(automatic: true);   // track ended
final user = queue.indexAfter(automatic: false);  // user pressed next

queue.insertNext(track);   // "play next"
queue.jumpTo(2);
''';

  List<MusicTrack> _tracks() {
    return <MusicTrack>[
      for (var index = 1; index <= 5; index++)
        MusicTrack(id: '$index', title: 'Track $index', artist: 'demo', sourceId: 'demo'),
    ];
  }

  @override
  Future<String> run() async {
    final buffer = StringBuffer();

    for (final mode in PlayMode.values) {
      final queue = PlayQueue(tracks: _tracks(), mode: mode);

      buffer.writeln('mode: ${mode.name}');

      // Walk the queue the way playback does: automatic advances until the
      // queue says stop.
      final visited = <String>[];
      var guard = 0;

      while (guard++ < 12) {
        final next = queue.indexAfter(automatic: true);

        if (next == null) {
          break;
        }

        visited.add(queue.tracks[next].title);
        queue.jumpTo(next);

        // A single-loop queue never leaves track 1; two entries prove it.
        if (mode == PlayMode.singleLoop && visited.length == 2) {
          break;
        }
      }

      buffer.writeln('  automatic advance: ${visited.join(' → ')}${guard >= 12 ? ' …' : ''}');

      final userQueue = PlayQueue(tracks: _tracks(), mode: mode);
      userQueue.jumpTo(userQueue.length - 1);

      final userNext = userQueue.indexAfter(automatic: false);

      buffer
        ..writeln(
          '  from the last track, a user "next" → '
          '${userNext == null ? 'stay (no silent wrap in list mode)' : userQueue.tracks[userNext].title}',
        )
        ..writeln();
    }

    final random = PlayQueue(tracks: _tracks(), mode: PlayMode.random);

    buffer
      ..writeln('random permutation: ${random.shuffleOrder}')
      ..writeln('  previous() walks this order backwards — it retraces what was played,')
      ..writeln('  which a per-step dice roll cannot do.')
      ..writeln()
      ..writeln('insertNext("下一首播放") on a 5-track queue:');

    final insertion = PlayQueue(tracks: _tracks())..jumpTo(1);
    final insertedAt = insertion.insertNext(
      const MusicTrack(id: 'next', title: 'PlayNext', artist: 'demo', sourceId: 'demo'),
    );

    buffer.writeln('  inserted at index $insertedAt → ${insertion.tracks.map((t) => t.title).join(', ')}');

    return buffer.toString();
  }
}
