import 'package:media_core_audio/src/lyric/lyric_line.dart';

/// A parsed lyric, ready for timed display.
///
/// The document is immutable and holds no cursor: "which line is current" is a
/// pure function of a playback position ([indexAt] / [positionAt]), so a
/// timeline, a desktop-lyric window and a notification can each ask the same
/// question without sharing state.
final class LyricDocument {
  /// Creates a document from already-sorted [lines].
  const LyricDocument({required this.lines, this.metadata = const <String, String>{}, this.isSynchronized = true});

  /// Creates a document from plain text with no timing.
  ///
  /// Unsynchronized lyrics (plain `.txt`, a lyric endpoint without timestamps)
  /// are still worth showing; they are simply never highlighted, which is
  /// exactly what [isSynchronized] tells the UI layer.
  factory LyricDocument.unsynchronized(String text) {
    final lines = text
        .split('\n')
        .map((line) => LyricLine(start: Duration.zero, text: line.trimRight()))
        .toList(growable: false);

    return LyricDocument(lines: lines, isSynchronized: false);
  }

  /// A document with nothing to show.
  static const LyricDocument empty = LyricDocument(lines: <LyricLine>[]);

  /// Lines, ordered by start time.
  final List<LyricLine> lines;

  /// LRC metadata tags (`ti`, `ar`, `al`, `by`, `offset`, …).
  final Map<String, String> metadata;

  /// Whether the lines carry timing.
  final bool isSynchronized;

  /// Whether there is nothing to display.
  bool get isEmpty => lines.isEmpty || lines.every((line) => line.isEmpty && line.text.trim().isEmpty);

  /// Number of lines.
  int get length => lines.length;

  /// Reads a metadata tag.
  String? meta(String key) => metadata[key];

  /// Index of the line active at [position], or `-1` before the first line.
  ///
  /// Binary search: lyric files reach a few hundred lines and the position is
  /// polled several times a second, so this has to stay O(log n) — a linear
  /// scan per tick was the classic hot spot in lyric renderers.
  int indexAt(Duration position) {
    if (lines.isEmpty) {
      return -1;
    }

    if (position < lines.first.start) {
      return -1;
    }

    var low = 0;
    var high = lines.length - 1;

    while (low <= high) {
      final middle = (low + high) >> 1;
      final start = lines[middle].start;

      if (start <= position) {
        final next = middle + 1 < lines.length ? lines[middle + 1].start : null;

        if (next == null || next > position) {
          return middle;
        }

        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }

    return -1;
  }

  /// The line active at [position], if any.
  LyricLine? lineAt(Duration position) {
    final index = indexAt(position);

    return index < 0 ? null : lines[index];
  }

  /// A full reading of [position]: active line, line progress and, when the
  /// line carries word timing, the active word and its progress.
  LyricPosition positionAt(Duration position) {
    final index = indexAt(position);

    if (index < 0) {
      return LyricPosition.none;
    }

    final line = lines[index];
    final end = line.end ?? (index + 1 < lines.length ? lines[index + 1].start : null);

    final lineProgress = _progress(line.start, end, position);

    if (!line.hasWordTiming) {
      return LyricPosition(index: index, line: line, lineProgress: lineProgress);
    }

    var wordIndex = -1;

    for (var i = 0; i < line.words.length; i++) {
      if (line.words[i].start <= position) {
        wordIndex = i;
      } else {
        break;
      }
    }

    if (wordIndex < 0) {
      return LyricPosition(index: index, line: line, lineProgress: lineProgress);
    }

    final wordStart = line.words[wordIndex].start;
    final wordEnd = wordIndex + 1 < line.words.length ? line.words[wordIndex + 1].start : end;

    return LyricPosition(
      index: index,
      line: line,
      lineProgress: lineProgress,
      wordIndex: wordIndex,
      wordProgress: _progress(wordStart, wordEnd, position),
    );
  }

  /// The line following [index], if any.
  LyricLine? lineAfter(int index) => index + 1 < lines.length ? lines[index + 1] : null;

  double _progress(Duration start, Duration? end, Duration position) {
    if (end == null || end <= start) {
      // A line with no knowable end (the last one, or an authored one that
      // never finishes) reads as fully elapsed rather than stuck at 0.
      return 1;
    }

    final span = (end - start).inMilliseconds;
    final elapsed = (position - start).inMilliseconds;

    return (elapsed / span).clamp(0.0, 1.0);
  }

  @override
  String toString() => 'LyricDocument(${lines.length} lines, synchronized: $isSynchronized)';
}
