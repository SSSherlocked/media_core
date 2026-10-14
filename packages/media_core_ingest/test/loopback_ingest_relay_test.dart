import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_ingest/media_core_ingest.dart';

/// A provider that only knows how to be reached by absolute URL, exactly like
/// the ones whose manifests list bare child names.
final class _FakeUpstream {
  _FakeUpstream._(this._server);

  static Future<_FakeUpstream> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstream = _FakeUpstream._(server);
    server.listen(upstream._handle, onError: (Object _) {});
    return upstream;
  }

  final HttpServer _server;
  final List<String> requestedPaths = <String>[];
  final List<String?> referers = <String?>[];

  Uri get base => Uri(scheme: 'http', host: InternetAddress.loopbackIPv4.address, port: _server.port);
  Uri get master => base.replace(path: '/tc.livehls/v1/streams/1/hls/1.0/master.m3u8');
  Uri get media => base.replace(path: '/tc.livehls/v1/streams/1/hls/1.0/media.m3u8');

  Future<void> _handle(HttpRequest request) async {
    requestedPaths.add(request.uri.path);
    referers.add(request.headers.value('referer'));
    final body = switch (request.uri.path) {
      '/tc.livehls/v1/streams/1/hls/1.0/master.m3u8' =>
        '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720\n'
            'media.m3u8\n',
      '/tc.livehls/v1/streams/1/hls/1.0/media.m3u8' =>
        '#EXTM3U\n'
            '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
            '#EXTINF:2.0,\n'
            'media.95.mp4\n'
            '#EXTINF:2.0,\n'
            '/tc.livehls/v1/streams/1/hls/1.0/media.96.mp4\n'
            '#EXT-X-ENDLIST\n',
      _ => String.fromCharCodes(List<int>.filled(2048, 0x5a)),
    };
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = request.uri.path.endsWith('.m3u8')
        ? ContentType('application', 'vnd.apple.mpegurl')
        : ContentType('video', 'mp4');
    request.response.write(body);
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

Future<String> _get(Uri url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    expect(response.statusCode, HttpStatus.ok);
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

void main() {
  late _FakeUpstream upstream;

  setUp(() async => upstream = await _FakeUpstream.start());
  tearDown(() async {
    await upstream.close();
  });

  test('a relative child becomes an absolute loopback URL', () async {
    final relay = await LoopbackIngestRelay.start(
      source: upstream.media,
      headers: const <String, String>{'Referer': 'https://twitcasting.tv/'},
    );
    addTearDown(relay.close);

    final manifest = await _get(relay.inputUri);

    expect(manifest, contains('http://127.0.0.1:${relay.inputUri.port}/'));
    expect(manifest, isNot(contains('\nmedia.95.mp4\n')));
    expect(manifest, isNot(contains('/tc.livehls/v1/streams/1/hls/1.0/media.96.mp4')));
    // The key is an attribute URI, not a child line.
    expect(manifest, contains('URI="http://127.0.0.1:${relay.inputUri.port}/'));
  });

  test('children are proxied upstream with the caller headers', () async {
    final relay = await LoopbackIngestRelay.start(
      source: upstream.media,
      headers: const <String, String>{'Referer': 'https://twitcasting.tv/'},
    );
    addTearDown(relay.close);

    final manifest = await _get(relay.inputUri);
    final segment = RegExp(r'http://127\.0\.0\.1:\d+/[a-z0-9]+/r[0-9a-z]+\.mp4').firstMatch(manifest);
    expect(segment, isNotNull, reason: 'the rewritten manifest must expose a loopback segment URL');

    final body = await _get(Uri.parse(segment!.group(0)!));

    expect(body.length, 2048);
    expect(upstream.requestedPaths, contains('/tc.livehls/v1/streams/1/hls/1.0/media.95.mp4'));
    expect(upstream.referers, everyElement('https://twitcasting.tv/'));
  });

  test('a nested playlist is rewritten as well', () async {
    final relay = await LoopbackIngestRelay.start(source: upstream.master);
    addTearDown(relay.close);

    final master = await _get(relay.inputUri);
    final child = RegExp(r'http://127\.0\.0\.1:\d+/[a-z0-9]+/r[0-9a-z]+\.m3u8').firstMatch(master);
    expect(child, isNotNull);

    final media = await _get(Uri.parse(child!.group(0)!));

    expect(media, contains('#EXT-X-KEY'));
    expect(media, isNot(contains('\nmedia.95.mp4\n')));
    expect(relay.childCount, greaterThanOrEqualTo(2));
  });

  test('an unknown path is not served', () async {
    final relay = await LoopbackIngestRelay.start(source: upstream.media);
    addTearDown(relay.close);

    final client = HttpClient();
    try {
      final response = await (await client.getUrl(relay.inputUri.replace(path: '/wrong/root.m3u8'))).close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  });
}
