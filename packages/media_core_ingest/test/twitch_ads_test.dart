import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_ingest/media_core_ingest.dart';

String _segment(int n, {bool ad = false, String time = ''}) =>
    '${time.isEmpty ? '' : '#EXT-X-PROGRAM-DATE-TIME:$time\n'}#EXTINF:2.000,${ad ? 'Amazon|123' : 'live'}\nhttps://seg/$n.ts\n';

void main() {
  test('a playlist without ads comes back unchanged', () {
    final String body = '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:10\n${_segment(10)}${_segment(11)}';
    final TwitchAdFilterResult result = withoutTwitchAds(body);
    expect(result.body, body);
    expect(result.dropped, 0);
  });

  test('after a break: the live run after the last ad, with its own sequence', () {
    final String body =
        '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:10\n${_segment(10)}${_segment(11, ad: true)}${_segment(12, ad: true)}${_segment(13)}${_segment(14)}${_segment(15)}';
    final TwitchAdFilterResult result = withoutTwitchAds(body);
    expect(result.adOngoing, isFalse);
    expect(result.dropped, 3);
    expect(result.marker, 'title "Amazon|123"');
    expect(result.body, contains('#EXT-X-MEDIA-SEQUENCE:13'));
    expect(result.body, isNot(contains('seg/11')));
    expect(result.body, contains('seg/15'));
  });

  test('a break holds until the live run after it is three segments long', () {
    final String body =
        '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:10\n${_segment(10)}${_segment(11, ad: true)}${_segment(12, ad: true)}${_segment(13)}${_segment(14)}'
        '#EXT-X-TWITCH-PREFETCH:https://seg/15.ts\n';
    final TwitchAdFilterResult result = withoutTwitchAds(body);
    // Served now, 13 and 14 would leave the player at the live edge with
    // nothing buffered: the run before the break is served instead.
    expect(result.adOngoing, isTrue);
    expect(result.body, contains('#EXT-X-MEDIA-SEQUENCE:10'));
    expect(result.body, contains('seg/10'));
    expect(result.body, isNot(contains('seg/13')));
    expect(result.body, isNot(contains('PREFETCH')));
  });

  test('during a break: the live run before it, and no prefetch', () {
    final String body =
        '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:10\n${_segment(10)}${_segment(11)}${_segment(12, ad: true)}'
        '#EXT-X-TWITCH-PREFETCH:https://seg/13.ts\n';
    final TwitchAdFilterResult result = withoutTwitchAds(body);
    expect(result.adOngoing, isTrue);
    expect(result.body, contains('#EXT-X-MEDIA-SEQUENCE:10'));
    expect(result.body, contains('seg/11'));
    expect(result.body, isNot(contains('seg/12')));
    expect(result.body, isNot(contains('PREFETCH')));
  });

  test('an all-ad playlist leaves nothing; dateranges mark ads by time', () {
    final String body =
        '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:5\n'
        '#EXT-X-DATERANGE:ID="stitched-ad-1",CLASS="twitch-stitched-ad",START-DATE="2026-10-17T10:00:00.000Z",DURATION=30.0\n'
        '${_segment(5, time: '2026-10-17T10:00:02.000Z')}${_segment(6, time: '2026-10-17T10:00:04.000Z')}';
    final TwitchAdFilterResult result = withoutTwitchAds(body);
    expect(result.body, isNull);
    expect(result.dropped, 2);
    expect(result.adOngoing, isTrue);
    expect(result.marker, 'daterange stitched-ad-1 (bounded)');
  });

  test('a planned duration ends an ad range', () {
    final String body =
        '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:5\n'
        '#EXT-X-DATERANGE:ID="stitched-ad-2",CLASS="twitch-stitched-ad",START-DATE="2026-10-17T10:00:00.000Z",PLANNED-DURATION=4.0\n'
        '${_segment(5, time: '2026-10-17T10:00:00.000Z')}${_segment(6, time: '2026-10-17T10:00:02.000Z')}'
        '${_segment(7, time: '2026-10-17T10:00:04.000Z')}${_segment(8, time: '2026-10-17T10:00:06.000Z')}'
        '${_segment(9, time: '2026-10-17T10:00:08.000Z')}';
    final TwitchAdFilterResult result = withoutTwitchAds(body);
    // Without the planned duration the range would cover 7, 8 and 9 too.
    expect(result.dropped, 2);
    expect(result.adOngoing, isFalse);
    expect(result.body, contains('#EXT-X-MEDIA-SEQUENCE:7'));
  });
}
