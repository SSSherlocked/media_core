import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One UPnP control response.
class SoapResponse {
  /// Creates a response.
  const SoapResponse({required this.statusCode, required this.body});

  /// HTTP status.
  final int statusCode;

  /// Response body text.
  final String body;
}

/// Posts SOAP envelopes to a control URL.
///
/// Injectable so the SOAP codec, the argument parsing and the fault
/// handling are unit-testable without a TV on the network: a test
/// hands it a closure that returns canned envelopes, and production
/// uses the [HttpSoapTransport] default.
typedef SoapPoster = Future<SoapResponse> Function(String url, String action, Map<String, String> headers, String body);

/// [SoapPoster] over `dart:io HttpClient`.
class HttpSoapTransport {
  /// Creates a transport with its own [client].
  HttpSoapTransport({HttpClient? client, Duration timeout = const Duration(seconds: 8)})
    : _client = client ?? HttpClient()
        ..connectionTimeout = timeout,
      _timeout = timeout;

  final HttpClient _client;
  final Duration _timeout;

  /// Sends one control request.
  Future<SoapResponse> call(String url, String action, Map<String, String> headers, String body) async {
    final request = await _client.postUrl(Uri.parse(url)).timeout(_timeout);
    headers.forEach((name, value) => request.headers.set(name, value));
    request.add(utf8.encode(body));

    final response = await request.close().timeout(_timeout);
    final text = await readBoundedBody(response);
    return SoapResponse(statusCode: response.statusCode, body: text);
  }

  /// Closes pooled sockets.
  void close() => _client.close(force: true);
}

/// Fetches a device description document.
typedef DescriptionFetcher = Future<String> Function(String url);

/// [DescriptionFetcher] over `dart:io HttpClient`.
class HttpDescriptionFetcher {
  /// Creates the fetcher.
  HttpDescriptionFetcher({HttpClient? client, Duration timeout = const Duration(seconds: 8)})
    : _client = client ?? HttpClient(),
      _timeout = timeout;

  final HttpClient _client;
  final Duration _timeout;

  /// GETs [url] as text.
  ///
  /// The URL comes out of an SSDP packet, so it is input from whatever
  /// device answered on the LAN: only `http`/`https` is fetched, a
  /// non-2xx status is a failure rather than a document, and the body is
  /// size-bounded. A renderer that answers a description request with an
  /// endless stream would otherwise grow this process's heap until it
  /// dies, and a 404 HTML page would otherwise be handed to the XML
  /// parser as if it were a device description.
  Future<String> call(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw FormatException(
        'device description location must be http or https, '
        'got "${uri.scheme}"',
        url,
      );
    }

    final request = await _client.getUrl(uri).timeout(_timeout);
    final response = await request.close().timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw FormatException('device description at $url answered ${response.statusCode}', url);
    }

    return await readBoundedBody(response);
  }

  /// Closes pooled sockets.
  void close() => _client.close(force: true);
}

/// Largest response body this package will read, in bytes.
///
/// A device description is a few kilobytes and a SOAP reply is smaller;
/// the bound exists so a broken or hostile renderer cannot exhaust the
/// heap by never finishing its answer.
const int maxCastResponseBodyBytes = 1 << 20;

/// Reads [response] as UTF-8 text, refusing to read past
/// [maxCastResponseBodyBytes].
///
/// Throws [FormatException] when the bound is exceeded — the caller is
/// parsing a document, and a truncated one is not a document.
Future<String> readBoundedBody(HttpClientResponse response) async {
  final builder = BytesBuilder(copy: false);

  await for (final chunk in response) {
    builder.add(chunk);
    if (builder.length > maxCastResponseBodyBytes) {
      await response.drain<void>();
      throw const FormatException('response body exceeded the cast response size limit');
    }
  }

  return utf8.decode(builder.toBytes(), allowMalformed: true);
}
