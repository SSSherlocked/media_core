import 'dart:convert';

/// What [withoutTwitchAds] did to one media playlist.
final class TwitchAdFilterResult {
  const TwitchAdFilterResult(this.body, {required this.dropped, required this.adOngoing});

  /// The playlist without its ad segments; null when nothing of the live
  /// stream is left in it (the whole window is an ad).
  final String? body;

  /// How many ad segments were taken out.
  final int dropped;

  /// Whether the playlist ends in an ad: the break is still running.
  final bool adOngoing;
}

/// Takes Twitch's stitched-in ad segments out of a live media playlist.
///
/// Twitch puts its ads into the stream itself: during a break the playlist
/// lists ad segments in place of the broadcast. They are marked, as
/// Streamlink reads them: an `#EXT-X-DATERANGE` with
/// `CLASS="twitch-stitched-ad"` (or an `ID` starting `stitched-ad-`) covers
/// them by `#EXT-X-PROGRAM-DATE-TIME`, and their `#EXTINF` title names the
/// ad server (`Amazon`) instead of `live`.
///
/// A player reads a live playlist by sequence number, so only a contiguous
/// run of live segments can be served: the run after the last ad, or, while
/// the break is still running, the run before it. `#EXT-X-MEDIA-SEQUENCE`
/// becomes the first kept segment's own number, so the player neither plays
/// a segment twice nor skips one it has not seen. Twitch's announced next
/// segments (`#EXT-X-TWITCH-PREFETCH`) are dropped during a break: they are
/// ads too.
///
/// A playlist without ad markers comes back unchanged.
TwitchAdFilterResult withoutTwitchAds(String body) {
  final List<String> lines = const LineSplitter().convert(body);
  final List<_AdRange> adRanges = lines
      .where((line) => line.startsWith(_dateRange))
      .map(_AdRange.parse)
      .whereType<_AdRange>()
      .toList(growable: false);

  final List<String> header = <String>[];
  final List<_Segment> segments = <_Segment>[];
  List<String> pending = <String>[];
  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('#')) {
      if (segments.isEmpty && !_segmentTag(trimmed)) {
        if (pending.isEmpty) {
          header.add(line);
          continue;
        }
      }
      pending.add(line);
      continue;
    }
    segments.add(_Segment(pending, line));
    pending = <String>[];
  }
  final List<String> footer = pending;
  if (segments.isEmpty) {
    return TwitchAdFilterResult(body, dropped: 0, adOngoing: false);
  }

  final int firstSequence = header.map(_mediaSequence).whereType<int>().firstOrNull ?? 0;
  final List<bool> ads = <bool>[for (final _Segment segment in segments) segment.isAd(adRanges)];
  final int adCount = ads.where((ad) => ad).length;
  if (adCount == 0) return TwitchAdFilterResult(body, dropped: 0, adOngoing: false);

  final bool adOngoing = ads.last;
  int start;
  int end; // exclusive
  if (adOngoing) {
    end = ads.length;
    while (end > 0 && ads[end - 1]) {
      end--;
    }
    start = end;
    while (start > 0 && !ads[start - 1]) {
      start--;
    }
  } else {
    end = ads.length;
    start = ads.lastIndexOf(true) + 1;
  }
  if (start >= end) {
    return TwitchAdFilterResult(null, dropped: adCount, adOngoing: adOngoing);
  }

  final List<String> output = <String>[
    for (final String line in header)
      _mediaSequence(line) == null ? line : '$_mediaSequenceTag${firstSequence + start}',
    for (final _Segment segment in segments.sublist(start, end)) ...<String>[...segment.tags, segment.uri],
    for (final String line in footer)
      if (!(adOngoing && line.startsWith(_twitchPrefetch))) line,
  ];
  return TwitchAdFilterResult(
    '${output.join('\n')}\n',
    dropped: segments.length - (end - start),
    adOngoing: adOngoing,
  );
}

const String _dateRange = '#EXT-X-DATERANGE:';
const String _mediaSequenceTag = '#EXT-X-MEDIA-SEQUENCE:';
const String _twitchPrefetch = '#EXT-X-TWITCH-PREFETCH:';

/// Tags that open a segment rather than describe the playlist.
bool _segmentTag(String line) =>
    line.startsWith('#EXTINF') ||
    line.startsWith('#EXT-X-PROGRAM-DATE-TIME') ||
    line.startsWith('#EXT-X-DISCONTINUITY') ||
    line.startsWith('#EXT-X-BYTERANGE') ||
    line.startsWith(_dateRange);

int? _mediaSequence(String line) =>
    line.startsWith(_mediaSequenceTag) ? int.tryParse(line.substring(_mediaSequenceTag.length).trim()) : null;

final class _Segment {
  _Segment(this.tags, this.uri);

  final List<String> tags;
  final String uri;

  bool isAd(List<_AdRange> adRanges) {
    for (final String tag in tags) {
      if (tag.startsWith('#EXTINF')) {
        final int comma = tag.indexOf(',');
        final String title = comma < 0 ? '' : tag.substring(comma + 1).trim().toLowerCase();
        if (title.contains('amazon') || title.contains('stitched')) return true;
      }
      if (tag.startsWith('#EXT-X-PROGRAM-DATE-TIME:')) {
        final DateTime? date = DateTime.tryParse(tag.substring('#EXT-X-PROGRAM-DATE-TIME:'.length).trim());
        if (date != null && adRanges.any((range) => range.covers(date))) return true;
      }
    }
    return false;
  }
}

final class _AdRange {
  const _AdRange(this.start, this.end);

  final DateTime start;
  final DateTime? end;

  static final RegExp _attribute = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');

  static _AdRange? parse(String line) {
    final Map<String, String> attributes = <String, String>{
      for (final RegExpMatch match in _attribute.allMatches(line.substring(_dateRange.length)))
        match.group(1)!: match.group(2)!.replaceAll('"', ''),
    };
    final bool ad =
        attributes['CLASS'] == 'twitch-stitched-ad' || (attributes['ID']?.startsWith('stitched-ad-') ?? false);
    if (!ad) return null;
    final DateTime? start = DateTime.tryParse(attributes['START-DATE'] ?? '');
    if (start == null) return null;
    final DateTime? endDate = DateTime.tryParse(attributes['END-DATE'] ?? '');
    final double? duration = double.tryParse(attributes['DURATION'] ?? '');
    final DateTime? end =
        endDate ?? (duration == null ? null : start.add(Duration(milliseconds: (duration * 1000).round())));
    return _AdRange(start, end);
  }

  /// An open-ended range (no duration yet) covers everything after it.
  bool covers(DateTime date) => !date.isBefore(start) && (end == null || date.isBefore(end!));
}
