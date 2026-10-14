import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_ingest/media_core_ingest.dart';

/// A provider whose children need the manifest's token and a session cookie.
final class _GatedUpstream {
  _GatedUpstream._(this._server);

  static Future<_GatedUpstream> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstream = _GatedUpstream._(server);
    server.listen((request) async {
      if (request.uri.path.endsWith('media.m3u8')) {
        upstream.manifestQueries.add(request.uri.query);
        request.response.headers.set(HttpHeaders.setCookieHeader, 'sid=abc; Path=/');
        request.response.write('#EXTM3U\n#EXTINF:2.0,\n/live/seg1.ts\n#EXT-X-ENDLIST\n');
        await request.response.close();
        return;
      }
      upstream.childQueries.add(request.uri.query);
      upstream.childCookies.add(request.headers.value(HttpHeaders.cookieHeader));
      final allowed = request.uri.queryParameters['token'] == 'tok';
      request.response.statusCode = allowed ? HttpStatus.ok : HttpStatus.forbidden;
      request.response.write('segment');
      await request.response.close();
    });
    return upstream;
  }

  final HttpServer _server;
  final List<String> childQueries = <String>[];
  final List<String?> childCookies = <String?>[];
  final List<String> manifestQueries = <String>[];

  Uri get manifest => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
    path: '/live/media.m3u8',
    query: 'token=tok',
  );

  Future<void> close() => _server.close(force: true);
}

void main() {
  test('the child policy reaches upstream and the player never sees it', () async {
    final upstream = await _GatedUpstream.start();
    addTearDown(upstream.close);
    final policy = HlsSourceQueryPolicy.fromSource(upstream.manifest);

    final relay = await LoopbackIngestRelay.start(
      source: upstream.manifest,
      childUriPolicy: policy.apply,
      sessionCookies: true,
    );
    addTearDown(relay.close);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    // The player reads the manifest from loopback: no token in that URL.
    final manifest = await (await client.getUrl(relay.inputUri)).close();
    expect(manifest.statusCode, HttpStatus.ok);
    expect(relay.inputUri.query, isEmpty);
    final body = await manifest.transform(utf8.decoder).join();
    expect(body, contains('http://127.0.0.1:${relay.inputUri.port}/'));

    // The child it names is fetched from loopback and carries no token either...
    final child = RegExp(r'http://127\.0\.0\.1:\d+/[a-z0-9]+/r[0-9a-z]+\.ts').firstMatch(body);
    expect(child, isNotNull);
    final segment = await (await client.getUrl(Uri.parse(child!.group(0)!))).close();
    expect(segment.statusCode, HttpStatus.ok);
    await segment.drain<void>();

    // ...while the relay's own upstream request carried the token and the cookie.
    expect(upstream.childQueries, contains('token=tok'));
    expect(upstream.childCookies, everyElement('sid=abc'));
  });
}
