import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_ingest/media_core_ingest.dart';

void main() {
  test('the newest segments are fetched once, before the player asks', () async {
    final HttpServer upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final List<String> requested = <String>[];
    upstream.listen((HttpRequest request) async {
      requested.add(request.uri.path);
      final String body = request.uri.path == '/live.m3u8'
          ? '#EXTM3U\n'
                '#EXTINF:2.0,\nseg1.ts\n'
                '#EXTINF:2.0,\nseg2.ts\n'
                '#EXTINF:2.0,\nseg3.ts\n'
                '#EXT-X-TWITCH-PREFETCH:seg4.ts\n'
          : 'segment ${request.uri.path}';
      request.response.write(body);
      await request.response.close();
    });
    final LoopbackIngestRelay relay = await LoopbackIngestRelay.start(
      source: Uri.parse('http://127.0.0.1:${upstream.port}/live.m3u8'),
      prefetchSegments: 2,
    );
    final HttpClient player = HttpClient();
    addTearDown(() async {
      player.close(force: true);
      await relay.close();
      await upstream.close(force: true);
    });

    Future<String> get(Uri uri) async {
      final HttpClientResponse response = await (await player.getUrl(uri)).close();
      return utf8.decode(await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b)));
    }

    final String playlist = await get(relay.inputUri);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // seg2, seg3 (the newest two) and the announced seg4, not seg1.
    expect(requested.toSet(), <String>{'/live.m3u8', '/seg2.ts', '/seg3.ts', '/seg4.ts'});

    final String seg3 = const LineSplitter().convert(playlist).where((line) => line.contains('127.0.0.1')).last;
    expect(await get(Uri.parse(seg3)), 'segment /seg3.ts');
    // Served from memory: upstream was not asked again.
    expect(requested.where((path) => path == '/seg3.ts'), hasLength(1));
  });
}
