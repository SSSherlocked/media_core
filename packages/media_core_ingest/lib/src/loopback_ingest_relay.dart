import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:media_core_ingest/src/hls_session_cookies.dart';

/// Rewrites an HLS manifest tree so every child is an absolute loopback URL.
///
/// The player then resolves nothing itself: it is handed
/// `http://127.0.0.1:<port>/<secret>/root.m3u8` and every playlist, segment, key
/// and map it reads from there is already absolute. That removes a whole class
/// of provider quirks - bare `media.95.mp4` children, absolute-path children,
/// per-child tokens, cookies handed out with the manifest - without teaching the
/// player or its FFmpeg about any of them.
///
/// The relay is deliberately small and per-source: one upstream origin, one
/// secret, one manifest tree. It keeps upstream TLS verification (Dart's trust
/// path) and answers a Range request by proxying it, so seeking into a finished
/// stream still works.
final class LoopbackIngestRelay {
  LoopbackIngestRelay._({
    required HttpServer server,
    required HttpClient client,
    required Uri upstream,
    required Map<String, String> headers,
    required String secret,
    required Duration manifestTimeout,
    required Duration childIdleTimeout,
    required int maximumManifestBytes,
    required Uri Function(Uri)? childUriPolicy,
    required bool sessionCookies,
  }) : _server = server,
       _client = client,
       _headers = headers,
       _secret = secret,
       _manifestTimeout = manifestTimeout,
       _childIdleTimeout = childIdleTimeout,
       _maximumManifestBytes = maximumManifestBytes,
       _childUriPolicy = childUriPolicy,
       _cookies = sessionCookies ? HlsSessionCookies() : null {
    _children['root.m3u8'] = _Child(uri: upstream, manifest: true);
  }

  /// Starts a relay for [source]. The returned relay owns the port until
  /// [close]; callers hand [inputUri] to the player.
  ///
  /// [rootManifest] is a body the caller already fetched (for example while
  /// classifying the manifest). Supplying it means the upstream manifest is read
  /// once instead of twice; it is served rewritten on the first request.
  ///
  /// [childUriPolicy] is applied to every *upstream* child request, which is how
  /// a provider that expects its manifest token on children keeps it (the player
  /// only ever sees loopback URLs). [sessionCookies] keeps the provider's
  /// `Set-Cookie` values for the origin and replays them on children.
  ///
  /// [childIdleTimeout] bounds how long a proxied child may go without sending
  /// another byte, and how long the relay may wait for its response headers.
  ///
  /// [findProxy] is the upstream proxy directive for every request this relay
  /// makes itself. Without it the relay goes direct even when the host player is
  /// proxied, so a provider that is only reachable through a proxy would read the
  /// manifest for the caller and then fail on its own fetches.
  static Future<LoopbackIngestRelay> start({
    required Uri source,
    Map<String, String> headers = const <String, String>{},
    String? rootManifest,
    Uri Function(Uri)? childUriPolicy,
    bool sessionCookies = false,
    String Function(Uri url)? findProxy,
    Duration manifestTimeout = const Duration(seconds: 15),
    Duration childIdleTimeout = const Duration(seconds: 10),
    int maximumManifestBytes = 8 * 1024 * 1024,
  }) async {
    if (!const <String>{'http', 'https'}.contains(source.scheme.toLowerCase()) || source.host.isEmpty) {
      throw ArgumentError.value(source, 'source', 'Loopback ingest needs an http(s) source');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient()..connectionTimeout = manifestTimeout;
    if (findProxy != null) client.findProxy = findProxy;
    final relay = LoopbackIngestRelay._(
      server: server,
      client: client,
      upstream: source,
      headers: Map<String, String>.unmodifiable(headers),
      secret: _newSecret(),
      manifestTimeout: manifestTimeout,
      childIdleTimeout: childIdleTimeout,
      maximumManifestBytes: maximumManifestBytes,
      childUriPolicy: childUriPolicy,
      sessionCookies: sessionCookies,
    );
    server.listen(relay._handle, onError: (Object _) {}, cancelOnError: false);
    if (rootManifest != null) {
      relay._servedBodies['root.m3u8'] = rootManifest;
    }
    return relay;
  }

  static final Random _random = Random.secure();
  static final RegExp _uriAttribute = RegExp('URI="([^"]+)"', caseSensitive: false);
  static final RegExp _manifestPath = RegExp(r'(\.m3u8|/(master_)?playlist)$', caseSensitive: false);

  final HttpServer _server;
  final HttpClient _client;
  final Map<String, String> _headers;
  final String _secret;
  final Duration _manifestTimeout;
  final Duration _childIdleTimeout;
  final int _maximumManifestBytes;
  final Uri Function(Uri)? _childUriPolicy;
  final HlsSessionCookies? _cookies;

  final Map<String, _Child> _children = <String, _Child>{};

  /// Upstream URL -> the child name serving it, so a repeated URI is registered
  /// once and the playlist stays small.
  final Map<String, String> _byUpstream = <String, String>{};

  /// Bodies the caller already fetched, keyed by child name: they are served
  /// rewritten on the first request instead of being fetched again.
  final Map<String, String> _servedBodies = <String, String>{};
  int _nextId = 0;
  bool _closed = false;

  /// The URL the player opens.
  Uri get inputUri =>
      Uri(scheme: 'http', host: InternetAddress.loopbackIPv4.address, port: _server.port, path: '/$_secret/root.m3u8');

  /// Number of distinct children handed out so far (diagnostics/tests).
  int get childCount => _children.length - 1;

  /// Whether [close] has run; a closed relay is no longer a usable input.
  bool get isClosed => _closed;

  static String _newSecret() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(24, (_) => alphabet[_random.nextInt(alphabet.length)]).join();
  }

  Future<void> _handle(HttpRequest request) async {
    final prefix = '/$_secret/';
    final path = request.uri.path;
    if (_closed || !path.startsWith(prefix)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final name = path.substring(prefix.length);
    final child = _children[name];
    if (child == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      if (child.manifest) {
        await _serveManifest(request, name, child.uri);
      } else {
        await _proxyChild(request, child.uri);
      }
    } on Object catch (_) {
      // A failed child is the player's error to report: closing the response
      // with a status keeps it from waiting forever.
      await _fail(request, HttpStatus.badGateway);
    }
  }

  Future<void> _serveManifest(HttpRequest request, String name, Uri manifest) async {
    final preloaded = _servedBodies.remove(name);
    final String body;
    if (preloaded != null) {
      body = preloaded;
    } else {
      final upstream = await _open('GET', manifest);
      if (upstream.statusCode != HttpStatus.ok) {
        await upstream.drain<void>();
        await _fail(request, upstream.statusCode);
        return;
      }
      body = await _readManifest(upstream);
    }
    if (_closed) return;
    final rewritten = _rewrite(body, manifest);
    final response = request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('application', 'vnd.apple.mpegurl')
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..write(rewritten);
    await response.close();
  }

  Future<String> _readManifest(HttpClientResponse upstream) async {
    final builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in upstream.timeout(_manifestTimeout)) {
      builder.add(chunk);
      if (builder.length > _maximumManifestBytes) {
        throw const FormatException('Ingest manifest exceeds the relay budget');
      }
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  /// Rewrites every URI in [body] to an absolute loopback URL.
  ///
  /// Attribute URIs (`#EXT-X-KEY:URI="..."`, `#EXT-X-MAP:URI="..."`) and plain
  /// child lines are both resolved against [manifest], which is the part a
  /// native resolver gets wrong when it no longer knows the manifest URL.
  String _rewrite(String body, Uri manifest) {
    final hadTrailingNewline = body.endsWith('\n');
    final output = <String>[];
    for (final rawLine in const LineSplitter().convert(body)) {
      final line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        output.add('');
      } else if (trimmed.startsWith('#')) {
        output.add(
          line.replaceAllMapped(_uriAttribute, (match) {
            final local = _localUrl(manifest, match.group(1)!);
            return local == null ? match.group(0)! : 'URI="$local"';
          }),
        );
      } else {
        output.add(_localUrl(manifest, trimmed) ?? line);
      }
    }
    final value = output.join('\n');
    return hadTrailingNewline ? '$value\n' : value;
  }

  /// Registers [raw] (resolved against [manifest]) and returns its loopback URL.
  String? _localUrl(Uri manifest, String raw) {
    final resolved = Uri.tryParse(raw) == null ? null : manifest.resolve(raw);
    if (resolved == null ||
        !const <String>{'http', 'https'}.contains(resolved.scheme.toLowerCase()) ||
        resolved.host.isEmpty ||
        resolved.userInfo.isNotEmpty) {
      return null;
    }
    final isManifest = _manifestPath.hasMatch(resolved.path);
    final key = resolved.toString();
    var name = _byUpstream[key];
    if (name == null) {
      final id = 'r${(_nextId++).toRadixString(36)}';
      name = '$id${isManifest ? '.m3u8' : _extensionOf(resolved)}';
      _children[name] = _Child(uri: resolved, manifest: isManifest);
      _byUpstream[key] = name;
    }
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: _server.port,
      path: '/$_secret/$name',
    ).toString();
  }

  static String _extensionOf(Uri uri) {
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = last.lastIndexOf('.');
    if (dot <= 0 || dot == last.length - 1) return '';
    return last.substring(dot).toLowerCase();
  }

  Future<void> _proxyChild(HttpRequest request, Uri upstream) async {
    // The child idle timeout is a gap between bytes, not a total budget: a live
    // segment can be large and a large one is not a stalled one. What must not
    // happen is the relay waiting forever on an upstream that accepted the
    // request and then said nothing — the player has no clock for that case, so
    // the sweep reads it as a stream that opened and never played, and the
    // provider gets blamed for a fetch this relay never finished. The deadline
    // also has to sit inside the sweep's verification window, or the verdict
    // arrives before the reason does.
    final response = await _open(
      request.method,
      upstream,
      range: request.headers.value(HttpHeaders.rangeHeader),
    ).timeout(_childIdleTimeout);
    if (_closed) {
      await response.drain<void>();
      return;
    }
    // A proxy must not hold the player's bytes in userspace: with the default
    // buffering, a small child (an init segment, a low-bitrate slice) sits in
    // this process until the buffer fills or the response closes, so every
    // range request pays an extra round of latency for no reason.
    final target = request.response
      ..bufferOutput = false
      ..statusCode = response.statusCode
      ..headers.contentType = response.headers.contentType;
    for (final header in const <String>[
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.etagHeader,
      HttpHeaders.lastModifiedHeader,
    ]) {
      final value = response.headers.value(header);
      if (value != null) target.headers.set(header, value);
    }
    await target.addStream(response.timeout(_childIdleTimeout));
    await target.close();
  }

  Future<HttpClientResponse> _open(String method, Uri uri, {String? range}) async {
    // The policy and the cookie jar describe the *upstream* contract, so they
    // apply to the request we make, never to the loopback URL the player sees.
    final upstream = _childUriPolicy?.call(uri) ?? uri;
    final request = await _client.openUrl(method, upstream);
    _headers.forEach(request.headers.set);
    if (range != null && range.isNotEmpty) {
      request.headers.set(HttpHeaders.rangeHeader, range);
    }
    final cookie = _cookies?.headerFor(upstream);
    if (cookie != null) {
      request.headers.set(HttpHeaders.cookieHeader, cookie);
    }
    final response = await request.close();
    final setCookie = response.headers[HttpHeaders.setCookieHeader];
    if (setCookie != null) {
      _cookies?.receive(upstream, setCookie);
    }
    return response;
  }

  Future<void> _fail(HttpRequest request, int status) async {
    final target = request.response;
    try {
      // A status can only be chosen while the headers are still unsent; a body
      // that already started cannot take one back.
      target.statusCode = status;
    } on Object catch (_) {
      // Mid-body failure: the answer is a clean end, not a status.
    }
    try {
      // Closing is what the player waits for. Skipping it (the old shape: the
      // status assignment above threw, so the close was never reached) tore the
      // connection down with the headers and the already-forwarded bytes still
      // in the output buffer, and the reader saw "the relay is dead" instead of
      // "this segment ended early" - which it reports as a stream failure and
      // retries as one.
      await target.close();
    } on Object catch (_) {
      // The player closed the connection first; nothing left to answer.
    }
  }

  /// Stops the relay: port, in-flight upstream sockets and the child registry.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _children.clear();
    _byUpstream.clear();
    _client.close(force: true);
    await _server.close(force: true);
  }
}

final class _Child {
  const _Child({required this.uri, required this.manifest});

  final Uri uri;
  final bool manifest;
}
