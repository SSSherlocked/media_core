import 'package:example/demos/module_demo.dart';
import 'package:media_core_audio/media_core_audio.dart';

/// Lyric parsing and timeline matching.
///
/// The lyric layer is pure logic, which makes it the one part of a music player
/// that can be demonstrated and debugged with no device, no network and no
/// playback — so the demo walks a whole file, not a single line.
class LyricDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'lrc';

  @override
  ModuleCategory get category => ModuleCategory.capability;

  @override
  String get nameZh => '歌词解析与时间轴';

  @override
  String get nameEn => 'Lyrics parsing & timeline';

  @override
  String get purposeZh =>
      'LrcParser 解析真实 LRC（一行多时间戳、offset、翻译合并、逐字 <mm:ss.xx>），LyricDocument 用二分查找回答"这一刻唱到哪"，LyricTimeline 只在行变化时发事件。';

  @override
  String get purposeEn =>
      'LrcParser handles real LRC (repeated timestamps, offset, merged translation, <mm:ss.xx> word timing); LyricDocument binary-searches "which line is now"; LyricTimeline emits only on line changes.';

  @override
  List<String> get pointsZh => const <String>[
    'LrcParser.parse(text, translation:) — 翻译按时间戳合并',
    'LyricDocument.positionAt(position) — 行 / 行内进度 / 逐字',
    'LyricTimeline.update(position) — 只在行或字变化时发事件',
    '无时间戳的纯文本降级为非同步歌词，而不是丢弃',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'LrcParser.parse(text, translation:) — translation merged by timestamp',
    'LyricDocument.positionAt(position) — line / line progress / word',
    'LyricTimeline.update(position) — emits only when line or word changes',
    'Untimed plain text degrades to an unsynchronized document, never dropped',
  ];

  @override
  String get snippet => '''
const parser = LrcParser();
final document = parser.parse(text, translation: translationText);

final documentLine = document.positionAt(const Duration(seconds: 9));
// → index / line / lineProgress / wordIndex

final timeline = LyricTimeline();
timeline.setDocument(document);
timeline.changes.listen((position) => print(position.line?.text));
timeline.update(const Duration(seconds: 9));
''';

  @override
  Future<String> run() async {
    const text = '''
[ti:示例 / demo]
[offset:0]
[00:00.50]第一句
[00:04.00][00:20.00]重复的一句
[00:08.50]<00:08.50>逐<00:09.20>字<00:09.90>演<00:10.60>示
''';

    const translation = '''
[00:00.50]first line
[00:04.00]repeated line
[00:08.50]word by word
''';

    final buffer = StringBuffer();
    final document = const LrcParser().parse(text, translation: translation);

    buffer
      ..writeln('parsed: ${document.length} line(s), synchronized=${document.isSynchronized}')
      ..writeln('metadata: ${document.metadata}')
      ..writeln();

    for (final line in document.lines) {
      buffer.writeln(
        '  ${line.start.inMilliseconds.toString().padLeft(6)}ms  ${line.text}'
        '${line.translation == null ? '' : '   ⟵ ${line.translation}'}'
        '${line.hasWordTiming ? '   (${line.words.length} words)' : ''}',
      );
    }

    buffer
      ..writeln()
      ..writeln('timeline walk:');

    final timeline = LyricTimeline()..setDocument(document);

    final emitted = <String>[];

    timeline.changes.listen((position) => emitted.add('${position.index}:${position.line?.text ?? ''}'));

    for (var millis = 0; millis <= 22000; millis += 1000) {
      timeline.update(Duration(milliseconds: millis));
    }

    buffer
      ..writeln('  line changes emitted: ${emitted.length}')
      ..writeln('  $emitted')
      ..writeln()
      ..writeln('note: 22 samples produced ${emitted.length} events — the timeline does not')
      ..writeln('      re-emit the same line, which is what keeps a desktop overlay cheap.');

    await timeline.dispose();

    return buffer.toString();
  }
}
