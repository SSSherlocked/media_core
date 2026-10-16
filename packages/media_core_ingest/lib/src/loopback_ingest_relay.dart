import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'hls_session_cookies.dart';
import 'twitch_ads.dart';

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
    required int prefetchSegments,
    required bool dropTwitchAds,
    required void Function(TwitchAdFilterResult result)? onTwitchAds,
  }) : _server = server,
       _client = client,
       _headers = headers,
       _secret = secret,
       _manifestTimeout = manifestTimeout,
       _childIdleTimeout = childIdleTimeout,
       _maximumManifestBytes = maximumManifestBytes,
       _childUriPolicy = childUriPolicy,
       _prefetchSegments = prefetchSegments,
       _dropTwitchAds = dropTwitchAds,
       _onTwitchAds = onTwitchAds,
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
  /// [prefetchSegments] is how many of a live playlist's newest segments the
  /// relay fetches as soon as it serves the playlist, before the player asks:
  /// the player then reads them from memory instead of waiting for a request
  /// it only starts when it needs the segment. Twitch's announced next
  /// segments (`#EXT-X-TWITCH-PREFETCH`) are fetched too. 0 turns it off.
  ///
  /// [dropTwitchAds] takes Twitch's stitched-in ad segments out of every
  /// media playlist (see [withoutTwitchAds]); [onTwitchAds] hears about each
  /// playlist that had some. While a break fills the whole playlist, the
  /// last ad-free one is served again, so the player waits on the live
  /// stream instead of showing the ad.
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
    int prefetchSegments = 0,
    bool dropTwitchAds = false,
    void Function(TwitchAdFilterResult result)? onTwitchAds,
    String Function(Uri url)? findProxy,
    Duration manifestTimeout = const Duration(seconds: 15),
    Duration childIdleTimeout = const Duration(seconds: 10),
    int maximumManifestBytes = 8 * 1024 * 1024,
  }) async {
    if (!const <String>{
          'http',
          'https',
        }.contains(source.scheme.toLowerCase()) ||
        source.host.isEmpty) {
      throw ArgumentError.value(
        source,
        'source',
        'Loopback ingest needs an http(s) source',
      );
    }
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
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
      prefetchSegments: prefetchSegments,
      dropTwitchAds: dropTwitchAds,
      onTwitchAds: onTwitchAds,
    );
    server.listen(relay._handle, onError: (Object _) {}, cancelOnError: false);
    if (rootManifest != null) {
      relay._servedBodies['root.m3u8'] = rootManifest;
    }
    return relay;
  }

  static final Random _random = Random.secure();
  static final RegExp _uriAttribute = RegExp(
    r'URI="([^"]+)"',
    caseSensitive: false,
  );
  static final RegExp _manifestPath = RegExp(
    r'(\.m3u8|/(master_)?playlist)$',
    caseSensitive: false,
  );
  static const String _twitchPrefetch = '#EXT-X-TWITCH-PREFETCH:';

  /// Prefetched bodies kept at most: a few playlists' worth of segments.
  static const int _cacheLimit = 12;

  final HttpServer _server;
  final HttpClient _client;
  final Map<String, String> _headers;
  final String _secret;
  final Duration _manifestTimeout;
  final Duration _childIdleTimeout;
  final int _maximumManifestBytes;
  final Uri Function(Uri)? _childUriPolicy;
  final HlsSessionCookies? _cookies;
  final int _prefetchSegments;
  final bool _dropTwitchAds;
  final void Function(TwitchAdFilterResult result)? _onTwitchAds;

  /// Per playlist child name, the last body served without ads.
  final Map<String, String> _lastAdFree = <String, String>{};

  /// Upstream URL -> its prefetched body, oldest first.
  final Map<String, Future<_Fetched?>> _prefetched =
      <String, Future<_Fetched?>>{};

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
  Uri get inputUri => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
    path: '/$_secret/root.m3u8',
  );

  /// Number of distinct children handed out so far (diagnostics/tests).
  int get childCount => _children.length - 1;

  /// Whether [close] has run; a closed relay is no longer a usable input.
  bool get isClosed => _closed;

  static String _newSecret() {
    const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(
      24,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  Future<void> _handle(HttpRequest request) async {
    final String prefix = '/$_secret/';
    final String path = request.uri.path;
    if (_closed || !path.startsWith(prefix)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final String name = path.substring(prefix.length);
    final _Child? child = _children[name];
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
    } catch (_) {
      // A failed child is the player's error to report: closing the response
      // with a status keeps it from waiting forever.
      await _fail(request, HttpStatus.badGateway);
    }
  }

  Future<void> _serveManifest(
    HttpRequest request,
    String name,
    Uri manifest,
  ) async {
    final String? preloaded = _servedBodies.remove(name);
    final String body;
    if (preloaded != null) {
      body = preloaded;
    } else {
      final HttpClientResponse upstream = await _open('GET', manifest);
      if (upstream.statusCode != HttpStatus.ok) {
        await upstream.drain<void>();
        await _fail(request, upstream.statusCode);
        return;
      }
      body = await _readManifest(upstream);
    }
    if (_closed) return;
    final String served = _dropTwitchAds ? _adFree(name, body) : body;
    final String rewritten = _rewrite(served, manifest);
    if (_prefetchSegments > 0) _prefetchNewest(served, manifest);
    final HttpResponse response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'application',
      'vnd.apple.mpegurl',
    );
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    // With its length: a body of unknown length goes out chunked, and ffmpeg,
    // told to reconnect streamed inputs, reads the end of a chunked body as
    // a cut. It reconnected after every playlist ("Will reconnect at <size>
    // ... End of file"), waited a second each time, and the live HLS
    // playlist fell behind until segments expired under the player.
    final List<int> bytes = utf8.encode(rewritten);
    response.contentLength = bytes.length;
    response.add(bytes);
    await response.close();
  }

  Future<String> _readManifest(HttpClientResponse upstream) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
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
    final bool hadTrailingNewline = body.endsWith('\n');
    final List<String> output = <String>[];
    for (final String rawLine in const LineSplitter().convert(body)) {
      final String line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      final String trimmed = line.trim();
      if (trimmed.isEmpty) {
        output.add('');
      } else if (trimmed.startsWith('#')) {
        output.add(
          line.replaceAllMapped(_uriAttribute, (Match match) {
            final String? local = _localUrl(manifest, match.group(1)!);
            return local == null ? match.group(0)! : 'URI="$local"';
          }),
        );
      } else {
        output.add(_localUrl(manifest, trimmed) ?? line);
      }
    }
    final String value = output.join('\n');
    return hadTrailingNewline ? '$value\n' : value;
  }

  /// Registers [raw] (resolved against [manifest]) and returns its loopback URL.
  String? _localUrl(Uri manifest, String raw) {
    final Uri? resolved = Uri.tryParse(raw) == null
        ? null
        : manifest.resolve(raw);
    if (resolved == null ||
        !const <String>{
          'http',
          'https',
        }.contains(resolved.scheme.toLowerCase()) ||
        resolved.host.isEmpty ||
        resolved.userInfo.isNotEmpty) {
      return null;
    }
    final bool isManifest = _manifestPath.hasMatch(resolved.path);
    final String key = resolved.toString();
    String? name = _byUpstream[key];
    if (name == null) {
      final String id = 'r${(_nextId++).toRadixString(36)}';
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
    final String last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final int dot = last.lastIndexOf('.');
    if (dot <= 0 || dot == last.length - 1) return '';
    return last.substring(dot).toLowerCase();
  }

  Future<void> _proxyChild(HttpRequest request, Uri upstream) async {
    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    final Future<_Fetched?>? prefetched = request.method == 'GET' &&
            (range == null || range.isEmpty)
        ? _prefetched[upstream.toString()]
        : null;
    if (prefetched != null) {
      final _Fetched? fetched = await prefetched;
      if (_closed) return;
      if (fetched != null) {
        final HttpResponse target = request.response;
        target.statusCode = HttpStatus.ok;
        target.headers.contentType = fetched.contentType;
        target.contentLength = fetched.bytes.length;
        target.add(fetched.bytes);
        await target.close();
        return;
      }
      // The prefetch failed: the request goes upstream itself.
    }
    // The child idle timeout is a gap between bytes, not a total budget: a live
    // segment can be large and a large one is not a stalled one. What must not
    // happen is the relay waiting forever on an upstream that accepted the
    // request and then said nothing — the player has no clock for that case, so
    // the sweep reads it as a stream that opened and never played, and the
    // provider gets blamed for a fetch this relay never finished. The deadline
    // also has to sit inside the sweep's verification window, or the verdict
    // arrives before the reason does.
    final HttpClientResponse response = await _open(
      request.method,
      upstream,
      range: range,
    ).timeout(_childIdleTimeout);
    if (_closed) {
      await response.drain<void>();
      return;
    }
    final HttpResponse target = request.response;
    target.statusCode = response.statusCode;
    target.headers.contentType = response.headers.contentType;
    for (final String header in const <String>[
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.etagHeader,
      HttpHeaders.lastModifiedHeader,
    ]) {
      final String? value = response.headers.value(header);
      if (value != null) target.headers.set(header, value);
    }
    // The length the player is told must be the length of what it gets. The
    // upstream header is wrong for a body HttpClient decompressed (it counts
    // the compressed bytes), and a body sent without a length is read by
    // ffmpeg as cut short (see _serveManifest): such a body is read whole
    // first, then sent with its real length.
    final int length = response.contentLength;
    if (length >= 0 &&
        response.compressionState !=
            HttpClientResponseCompressionState.decompressed) {
      target.contentLength = length;
      await target.addStream(response.timeout(_childIdleTimeout));
    } else {
      final BytesBuilder body = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.timeout(_childIdleTimeout)) {
        body.add(chunk);
      }
      final List<int> bytes = body.takeBytes();
      target.contentLength = bytes.length;
      target.add(bytes);
    }
    await target.close();
  }

  /// [body] without Twitch's ad segments. A playlist that is all ad gets the
  /// last ad-free one again; with none yet (the room opened during a break),
  /// the ad plays rather than nothing at all.
  String _adFree(String name, String body) {
    final TwitchAdFilterResult result = withoutTwitchAds(body);
    if (result.dropped > 0) _onTwitchAds?.call(result);
    final String? filtered = result.body;
    if (filtered == null) return _lastAdFree[name] ?? body;
    _lastAdFree[name] = filtered;
    return filtered;
  }

  /// Starts fetching the newest [_prefetchSegments] segments of the media
  /// playlist [body] (and Twitch's announced next ones) that are not fetched
  /// yet. A master playlist lists playlists, not segments: nothing to do.
  void _prefetchNewest(String body, Uri manifest) {
    final List<Uri> segments = <Uri>[];
    final List<Uri> announced = <Uri>[];
    for (final String rawLine in const LineSplitter().convert(body)) {
      final String line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith(_twitchPrefetch)) {
        final Uri? uri = _segmentUri(
          manifest,
          line.substring(_twitchPrefetch.length).trim(),
        );
        if (uri != null) announced.add(uri);
      } else if (!line.startsWith('#')) {
        final Uri? uri = _segmentUri(manifest, line);
        if (uri != null) segments.add(uri);
      }
    }
    final int skip = segments.length > _prefetchSegments
        ? segments.length - _prefetchSegments
        : 0;
    for (final Uri uri in <Uri>[...segments.skip(skip), ...announced]) {
      final String key = uri.toString();
      if (_prefetched.containsKey(key)) continue;
      _prefetched[key] = _fetchWhole(uri);
      while (_prefetched.length > _cacheLimit) {
        _prefetched.remove(_prefetched.keys.first);
      }
    }
  }

  /// [raw] resolved against [manifest] when it is a segment (not a playlist).
  static Uri? _segmentUri(Uri manifest, String raw) {
    if (Uri.tryParse(raw) == null) return null;
    final Uri resolved = manifest.resolve(raw);
    if (!const <String>{'http', 'https'}.contains(resolved.scheme.toLowerCase()) ||
        resolved.host.isEmpty ||
        resolved.userInfo.isNotEmpty ||
        _manifestPath.hasMatch(resolved.path)) {
      return null;
    }
    return resolved;
  }

  /// One segment read whole, or null when it could not be (the player's own
  /// request then goes upstream).
  Future<_Fetched?> _fetchWhole(Uri uri) async {
    try {
      final HttpClientResponse response = await _open(
        'GET',
        uri,
      ).timeout(_childIdleTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final BytesBuilder body = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.timeout(_childIdleTimeout)) {
        if (_closed) return null;
        body.add(chunk);
      }
      return _Fetched(body.takeBytes(), response.headers.contentType);
    } catch (_) {
      return null;
    }
  }

  Future<HttpClientResponse> _open(
    String method,
    Uri uri, {
    String? range,
  }) async {
    // The policy and the cookie jar describe the *upstream* contract, so they
    // apply to the request we make, never to the loopback URL the player sees.
    final Uri upstream = _childUriPolicy?.call(uri) ?? uri;
    final HttpClientRequest request = await _client.openUrl(method, upstream);
    _headers.forEach(request.headers.set);
    if (range != null && range.isNotEmpty) {
      request.headers.set(HttpHeaders.rangeHeader, range);
    }
    final String? cookie = _cookies?.headerFor(upstream);
    if (cookie != null) {
      request.headers.set(HttpHeaders.cookieHeader, cookie);
    }
    final HttpClientResponse response = await request.close();
    final List<String>? setCookie =
        response.headers[HttpHeaders.setCookieHeader];
    if (setCookie != null) {
      _cookies?.receive(upstream, setCookie);
    }
    return response;
  }

  Future<void> _fail(HttpRequest request, int status) async {
    try {
      request.response.statusCode = status;
      await request.response.close();
    } catch (_) {
      // The player closed the connection first; nothing left to answer.
    }
  }

  /// Stops the relay: port, in-flight upstream sockets and the child registry.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _children.clear();
    _byUpstream.clear();
    _prefetched.clear();
    _lastAdFree.clear();
    _client.close(force: true);
    await _server.close(force: true);
  }
}

final class _Child {
  const _Child({required this.uri, required this.manifest});

  final Uri uri;
  final bool manifest;
}

final class _Fetched {
  const _Fetched(this.bytes, this.contentType);

  final Uint8List bytes;
  final ContentType? contentType;
}
