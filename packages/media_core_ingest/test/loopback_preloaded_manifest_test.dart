import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_ingest/media_core_ingest.dart';

void main() {
  test('a preloaded manifest is served rewritten without a second fetch', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var upstreamManifestRequests = 0;
    upstream.listen((request) async {
      upstreamManifestRequests++;
      request.response.statusCode = HttpStatus.ok;
      request.response.write('#EXTM3U\n#EXTINF:2.0,\nmedia.95.mp4\n#EXT-X-ENDLIST\n');
      await request.response.close();
    });
    addTearDown(() => upstream.close(force: true));

    final source = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: upstream.port,
      path: '/live/media.m3u8',
    );
    final relay = await LoopbackIngestRelay.start(
      source: source,
      rootManifest: '#EXTM3U\n#EXTINF:2.0,\nmedia.95.mp4\n#EXT-X-ENDLIST\n',
    );
    addTearDown(relay.close);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(relay.inputUri)).close();
    final body = await response.transform(utf8.decoder).join();

    expect(body, contains('http://127.0.0.1:${relay.inputUri.port}/'));
    expect(body, isNot(contains('\nmedia.95.mp4\n')));
    expect(upstreamManifestRequests, 0, reason: 'the preloaded body replaces the upstream read');
  });
}
