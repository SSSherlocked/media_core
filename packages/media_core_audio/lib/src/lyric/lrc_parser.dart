import 'package:media_core_audio/src/lyric/lyric_document.dart';
import 'package:media_core_audio/src/lyric/lyric_line.dart';

/// Parses LRC into a [LyricDocument].
///
/// Handles what real music APIs actually hand out, because a parser that only
/// understands `[mm:ss.xx]text` loses lyric data in the field:
///
/// - several timestamps on one line (`[00:12.00][01:20.00]chorus`), which is
///   how repeated choruses are authored;
/// - `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, and `.`/`:` as the fraction
///   separator;
/// - metadata tags (`ti`, `ar`, `al`, `by`, `offset`, …) kept in
///   [LyricDocument.metadata] instead of being mistaken for lyric text;
/// - a separate translation track merged by timestamp, plus an optional
///   romanization track;
/// - enhanced LRC word timing written as `<mm:ss.xx>word`, used by karaoke
///   renderers and desktop lyrics;
/// - plain text with no timing at all, which becomes an unsynchronized
///   document rather than an empty one.
///
/// Timestamps are sorted and stable: the sort is applied to a list built in
/// file order, and Dart's `List.sort` is not stable — so entries carry their
/// original position and the comparator falls back to it. Without that, a
/// translation or a duet line sharing a timestamp could end up above the line
/// it belongs to.
final class LrcParser {
  /// Creates a parser.
  const LrcParser({this.wordByWord = true});

  /// Whether `<mm:ss.xx>` word tags are parsed.
  ///
  /// Turning this off keeps the tags out of the text but also drops the
  /// karaoke timing; it exists for sources that reuse `<…>` for something
  /// else.
  final bool wordByWord;

  static final RegExp _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _wordTag = RegExp(r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>');
  static final RegExp _metaTag = RegExp(r'^\[([a-zA-Z_]+):(.*)\]$');

  /// Parses [text], optionally merging [translation] and [romanization].
  LyricDocument parse(String text, {String? translation, String? romanization}) {
    if (text.trim().isEmpty) {
      return LyricDocument.empty;
    }

    // Text without a single timestamp is a plain-text lyric, not a broken LRC:
    // showing it unsynchronized is better than showing nothing.
    if (!_timeTag.hasMatch(text)) {
      return LyricDocument.unsynchronized(text);
    }

    final metadata = <String, String>{};
    final entries = <_RawLine>[];

    _collect(text, entries, metadata);

    final translationIndex = _indexTranslations(translation);
    final romanizationIndex = _indexTranslations(romanization);
    final offset = _parseOffset(metadata['offset']);

    entries.sort((a, b) {
      final byTime = a.start.compareTo(b.start);

      return byTime != 0 ? byTime : a.order.compareTo(b.order);
    });

    final lines = <LyricLine>[];

    for (final entry in entries) {
      final rawStart = entry.start.inMilliseconds;
      final shifted = entry.start - offset;

      lines.add(
        LyricLine(
          start: shifted < Duration.zero ? Duration.zero : shifted,
          text: entry.text,
          words: entry.words,
          // Translation keys are the file's own timestamps: the offset shifts
          // the display clock, not the identity of a line.
          translation: translationIndex[rawStart],
          romanization: romanizationIndex[rawStart],
        ),
      );
    }

    return LyricDocument(
      lines: List<LyricLine>.unmodifiable(lines),
      metadata: Map<String, String>.unmodifiable(metadata),
    );
  }

  void _collect(String text, List<_RawLine> entries, Map<String, String> metadata) {
    var order = 0;

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trimRight();

      if (line.trim().isEmpty) {
        continue;
      }

      final matches = _timeTag.allMatches(line);

      if (matches.isEmpty) {
        final meta = _metaTag.firstMatch(line.trim());

        // `[ti:…]`-style tags are metadata; anything else without a timestamp
        // in an otherwise timed file is a credit line with no cue, which the
        // timed display has no place for.
        if (meta != null) {
          metadata[meta.group(1)!.trim().toLowerCase()] = meta.group(2)!.trim();
        }

        continue;
      }

      final content = line.substring(matches.last.end);

      final words = wordByWord ? _parseWords(content) : const <LyricWord>[];
      final plainText = words.isEmpty ? content.trim() : words.map((word) => word.text).join().trim();

      for (final match in matches) {
        entries.add(
          _RawLine(
            start: _toDuration(match.group(1)!, match.group(2)!, match.group(3)),
            text: plainText,
            words: words,
            order: order++,
          ),
        );
      }
    }
  }

  /// Extracts `<mm:ss.xx>word` runs, or an empty list when there are none.
  List<LyricWord> _parseWords(String content) {
    final matches = _wordTag.allMatches(content).toList(growable: false);

    if (matches.isEmpty) {
      return const <LyricWord>[];
    }

    final words = <LyricWord>[];

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final end = i + 1 < matches.length ? matches[i + 1].start : content.length;
      final text = content.substring(match.end, end);

      if (text.isEmpty) {
        continue;
      }

      words.add(LyricWord(start: _toDuration(match.group(1)!, match.group(2)!, match.group(3)), text: text));
    }

    return List<LyricWord>.unmodifiable(words);
  }

  /// Indexes a translation/romanization track by millisecond timestamp.
  Map<int, String> _indexTranslations(String? text) {
    if (text == null || text.trim().isEmpty) {
      return const <int, String>{};
    }

    final index = <int, String>{};

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trimRight();

      if (line.trim().isEmpty) {
        continue;
      }

      final matches = _timeTag.allMatches(line);

      if (matches.isEmpty) {
        continue;
      }

      final content = line.substring(matches.last.end).trim();

      for (final match in matches) {
        index[_toDuration(match.group(1)!, match.group(2)!, match.group(3)).inMilliseconds] = content;
      }
    }

    return index;
  }

  /// Converts `mm`/`ss`/`fraction` groups into a duration.
  ///
  /// The fraction is 1–3 digits and always means sub-second precision:
  /// `.5` is 500 ms. Files written by hand use centiseconds, but a single
  /// digit appears too, and reading `.5` as 5 ms would put the line 495 ms
  /// early.
  Duration _toDuration(String minutes, String seconds, String? fraction) {
    var milliseconds = 0;

    if (fraction != null && fraction.isNotEmpty) {
      final value = int.parse(fraction);

      milliseconds = switch (fraction.length) {
        1 => value * 100,
        2 => value * 10,
        _ => value,
      };
    }

    return Duration(minutes: int.parse(minutes), seconds: int.parse(seconds), milliseconds: milliseconds);
  }

  /// Parses the `offset` metadata tag.
  ///
  /// The tag's sign convention is famously ambiguous across players. This
  /// parser follows the one most LRC files are authored against: a positive
  /// offset makes the lyric appear *earlier*, so it is subtracted from every
  /// timestamp. Change this single method to flip the convention for a host
  /// whose files disagree.
  Duration _parseOffset(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return Duration.zero;
    }

    final value = int.tryParse(raw.trim());

    return value == null ? Duration.zero : Duration(milliseconds: value);
  }
}

/// One timestamped entry before merging and sorting.
final class _RawLine {
  const _RawLine({required this.start, required this.text, required this.order, this.words = const <LyricWord>[]});

  final Duration start;
  final String text;
  final int order;
  final List<LyricWord> words;
}
