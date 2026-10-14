import 'dart:async';
import 'dart:io' as io;

import 'package:media_core/media_core.dart';

import 'package:media_core_download/src/download_config.dart';

/// One ranged request.
final class DownloadRequest {
  /// Creates a request for [url] covering the byte range from [startByte].
  const DownloadRequest({
    required this.url,
    required this.startByte,
    this.endByte,
    this.headers = const <String, String>{},
    this.userAgent,
    this.timeout = const Duration(seconds: 20),
    this.maxRedirects = 2,
  });

  /// The resource to fetch.
  final String url;

  /// First byte to fetch.
  final int startByte;

  /// Last byte to fetch, inclusive; `null` means "to the end".
  final int? endByte;

  /// Caller headers merged into the request.
  final Map<String, String> headers;

  /// User agent to send, falling back to the transport's config when null.
  final String? userAgent;

  /// Connect/read timeout for this request.
  final Duration timeout;

  /// Redirects to follow before treating the transfer as failed.
  final int maxRedirects;

  /// Whether this request is a plain full-file fetch.
  bool get isFullFile => startByte == 0 && endByte == null;

  /// `Range` header value, or `null` for a full fetch.
  String? get rangeHeader => isFullFile ? null : 'bytes=$startByte-${endByte ?? ''}';
}

/// A server's answer.
final class DownloadResponse {
  /// Creates a response carrying [statusCode] and the body [byteStream].
  const DownloadResponse({
    required this.statusCode,
    required this.byteStream,
    this.contentLength = -1,
    this.totalBytes = -1,
    this.acceptsRanges = false,
  });

  /// HTTP status code the server answered with.
  final int statusCode;

  /// Body bytes, already positioned at the requested offset.
  final Stream<List<int>> byteStream;

  /// Length of *this* response, or `-1` when not sent.
  final int contentLength;

  /// Length of the whole file, or `-1` when the server did not say.
  ///
  /// Taken from `Content-Range` for a partial response and from
  /// `Content-Length` for a full one; the distinction matters because a ranged
  /// response's own length is not the file's size.
  final int totalBytes;

  /// Whether the server advertised byte-range support.
  final bool acceptsRanges;

  /// Whether the server answered a ranged request with a partial body.
  bool get isPartial => statusCode == 206;

  /// The file's size as reported by this response, or `null` when unknown.
  int? get resolvedTotalBytes {
    if (totalBytes > 0) {
      return totalBytes;
    }
    return !isPartial && contentLength > 0 ? contentLength : null;
  }

  @override
  String toString() {
    final total = resolvedTotalBytes;
    return 'DownloadResponse($statusCode, ${total == null ? 'unknown size' : '$total B'}, ranges: $acceptsRanges)';
  }
}

/// Fetches bytes over the network.
///
/// The seam exists so the queue's policy — concurrency, retry, resume
/// verification, progress — is testable without a server, and so a host can
/// route downloads through its own client (a proxy, a platform downloader, a
/// test double).
abstract interface class DownloadTransport {
  /// Fetches [request].
  ///
  /// Implementations must throw on a non-success status rather than return it,
  /// so retry policy has one failure shape to reason about.
  Future<DownloadResponse> fetch(DownloadRequest request);

  /// Releases any pooled connection resources.
  Future<void> dispose();
}

/// Thrown when a server answers with a status the transfer cannot use.
final class DownloadHttpException implements Exception {
  /// Creates an error for [statusCode] returned for [url].
  const DownloadHttpException(this.statusCode, this.url);

  /// The status the server returned.
  final int statusCode;

  /// The URL that produced it.
  final String url;

  @override
  String toString() => 'DownloadHttpException($statusCode for $url)';
}

/// [DownloadTransport] backed by `dart:io`'s HTTP client.
///
/// Deliberately dependency-free: a download is a GET, a range header and a byte
/// stream, and pulling an HTTP package in for that would put the queue's
/// timeout and redirect behaviour at the mercy of another library.
final class HttpDownloadTransport implements DownloadTransport {
  /// Creates a transport over an optional [client], applying [config] defaults.
  HttpDownloadTransport({io.HttpClient? client, this.config = DownloadConfig.defaults})
    : _client = client ?? io.HttpClient();

  io.HttpClient _client;

  /// The configuration applied to subsequent requests.
  DownloadConfig config;

  @override
  Future<DownloadResponse> fetch(DownloadRequest request) async {
    final uri = Uri.parse(request.url);
    var redirects = 0;
    var current = uri;

    while (true) {
      final httpRequest = await _client.getUrl(current).timeout(request.timeout);
      httpRequest.followRedirects = false;
      httpRequest.headers.set(io.HttpHeaders.userAgentHeader, request.userAgent ?? config.userAgent);
      applyHeaders(httpRequest, request.headers);
      final rangeHeader = request.rangeHeader;
      if (rangeHeader != null) {
        httpRequest.headers.set(io.HttpHeaders.rangeHeader, rangeHeader);
      }

      final response = await httpRequest.close().timeout(request.timeout);

      if (response.isRedirect) {
        if (redirects >= request.maxRedirects) {
          throw DownloadHttpException(response.statusCode, current.toString());
        }
        redirects++;
        final location = response.headers.value(io.HttpHeaders.locationHeader);
        if (location == null || location.isEmpty) {
          throw DownloadHttpException(response.statusCode, current.toString());
        }
        current = current.resolve(location);
        await response.drain<void>();
        continue;
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.drain<void>();
        throw DownloadHttpException(response.statusCode, current.toString());
      }

      final contentRange = response.headers.value(io.HttpHeaders.contentRangeHeader);
      final contentLength = response.contentLength;
      final fullBody = response.statusCode == 200 && contentLength > 0;

      return DownloadResponse(
        statusCode: response.statusCode,
        byteStream: response,
        contentLength: contentLength,
        totalBytes: totalFromContentRange(contentRange) ?? (fullBody ? contentLength : -1),
        acceptsRanges: response.headers.value(io.HttpHeaders.acceptRangesHeader) != null,
      );
    }
  }

  @override
  Future<void> dispose() async {
    _client.close(force: true);
    _client = io.HttpClient();
  }

  /// Applies caller headers to a ranged request.
  ///
  /// Validation is the framework's single rule — see [HttpHeaderSanitizer].
  /// A header that cannot be sent exactly as given throws rather than being
  /// dropped, because the one that disappears is usually the credential and
  /// what follows is an unexplained 403.
  static void applyHeaders(io.HttpClientRequest request, Map<String, String> headers) {
    HttpHeaderSanitizer.sanitize(headers).forEach((name, value) {
      request.headers.set(name, value);
    });
  }

  /// Parses the total from `Content-Range: bytes start-end/total`.
  ///
  /// Returns null when the header is absent or does not carry a total (`*`).
  static int? totalFromContentRange(String? contentRange) {
    if (contentRange == null) {
      return null;
    }
    final slash = contentRange.lastIndexOf('/');
    if (slash < 0) {
      return null;
    }
    final total = int.tryParse(contentRange.substring(slash + 1).trim());
    return total != null && total > 0 ? total : null;
  }
}
