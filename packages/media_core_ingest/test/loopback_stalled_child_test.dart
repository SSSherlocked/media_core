import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_ingest/media_core_ingest.dart';

/// An origin that answers the manifest and then stops talking about the child.
///
/// This is the shape a proxy tunnel makes when it accepts the CONNECT and never
/// tunnels. Before the relay carried a deadline of its own, such a child left
/// the player with nothing to react to: no bytes, no error, no status — so the
/// sweep reported the *stream* as frozen ("opened but never played") while the
/// fetch this relay never finished was the actual failure.
final class _StallingUpstream {
  _StallingUpstream._(this._server, this._answersHeaders);

  static Future<_StallingUpstream> start({required bool answersHeaders}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _StallingUpstream._(server, answersHeaders);
    server.listen(fake._handle, onError: (Object _) {});
    return fake;
  }

  final HttpServer _server;
  final bool _answersHeaders;

  Uri get media =>
      Uri(scheme: 'http', host: InternetAddress.loopbackIPv4.address, port: _server.port, path: '/tree/media.m3u8');

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path == '/tree/media.m3u8') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
      request.response.write('#EXTM3U\n#EXTINF:2.0,\nseg.mp4\n#EXT-X-ENDLIST\n');
      await request.response.close();
      return;
    }
    if (!_answersHeaders) {
      // Accept the request and never answer it.
      return;
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('video', 'mp4');
    request.response.contentLength = 4096;
    request.response.add(List<int>.filled(1024, 0x5a));
    await request.response.flush();
    // The remaining 3072 bytes never arrive.
  }

  Future<void> close() => _server.close(force: true);
}

/// What a loopback child request ended with: a status (0 when the connection was
/// torn down before one could be read), the bytes that did arrive, and whether
/// it ended early.
Future<({int status, int bytes, bool endedEarly})> _fetchChild(Uri url) async {
  final client = HttpClient();
  var bytes = 0;
  try {
    final response = await (await client.getUrl(url)).close();
    final status = response.statusCode;
    try {
      await for (final List<int> chunk in response) {
        bytes += chunk.length;
      }
    } on Object catch (_) {
      return (status: status, bytes: bytes, endedEarly: true);
    }
    return (status: status, bytes: bytes, endedEarly: false);
  } on HttpException {
    return (status: 0, bytes: bytes, endedEarly: true);
  } on SocketException {
    return (status: 0, bytes: bytes, endedEarly: true);
  } finally {
    client.close(force: true);
  }
}

Future<String> _readManifest(Uri url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

final _childUrl = RegExp(r'http://127\.0\.0\.1:\d+/[a-z0-9]+/r[0-9a-z]+\.mp4');

void main() {
  group('a stalled child is answered on the relay clock', () {
    test('an upstream that never returns headers is refused', () async {
      final stalled = await _StallingUpstream.start(answersHeaders: false);
      addTearDown(stalled.close);
      final relay = await LoopbackIngestRelay.start(
        source: stalled.media,
        childIdleTimeout: const Duration(milliseconds: 300),
      );
      addTearDown(relay.close);

      final child = _childUrl.firstMatch(await _readManifest(relay.inputUri));
      expect(child, isNotNull, reason: 'the rewritten manifest must list a child');

      final started = DateTime.now();
      final result = await _fetchChild(Uri.parse(child!.group(0)!));
      final elapsed = DateTime.now().difference(started);

      // Nothing had reached the player yet, so a status is still available.
      expect(result.status, HttpStatus.badGateway);
      expect(result.endedEarly, isFalse);
      expect(
        elapsed,
        lessThan(const Duration(seconds: 3)),
        reason:
            'a response the relay never finishes leaves the player waiting '
            'for the sweep to notice instead of on a deadline anyone can read',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('an upstream that stops mid-body is cut off', () async {
      final stalled = await _StallingUpstream.start(answersHeaders: true);
      addTearDown(stalled.close);
      final relay = await LoopbackIngestRelay.start(
        source: stalled.media,
        childIdleTimeout: const Duration(milliseconds: 300),
      );
      addTearDown(relay.close);

      final child = _childUrl.firstMatch(await _readManifest(relay.inputUri));
      expect(child, isNotNull);

      final started = DateTime.now();
      final result = await _fetchChild(Uri.parse(child!.group(0)!));
      final elapsed = DateTime.now().difference(started);

      // The response had already started, so no status can take it back: what
      // the player has to get is an *end* — a read it can act on, not a
      // connection held open for bytes that are never coming.
      // ignore: avoid_print
      print('MIDBODY RESULT: status=${result.status} bytes=${result.bytes} early=${result.endedEarly}');
      expect(result.endedEarly, isTrue);
      expect(result.bytes, lessThan(4096));
      expect(elapsed, lessThan(const Duration(seconds: 3)), reason: 'a stalled body must be cut on the relay clock');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
