import 'dart:convert';

/// One SSDP announcement or search response.
///
/// SSDP messages are HTTP-shaped header blocks over UDP; [SsdpMessage]
/// is that block after parsing — enough to know *which* device sent it
/// (USN), where its description lives (LOCATION) and whether it is
/// still alive (CACHE-CONTROL) or gone (BYEBYE).
final class SsdpMessage {
  /// Creates a parsed message.
  const SsdpMessage({required this.method, required this.headers});

  /// The line that opened the message: the request method
  /// (`M-SEARCH`, `NOTIFY`) or `RESPONSE` for a 200 answer to a
  /// search.
  final String method;

  /// Header names lower-cased, values trimmed.
  final Map<String, String> headers;

  /// Parses an SSDP datagram payload.
  ///
  /// Returns null when the datagram is not an SSDP message at all —
  /// a truncated packet, another protocol sharing the port, or a
  /// garbage line. Discovery must keep running over one bad packet,
  /// so null (skip) rather than an exception is the contract.
  static SsdpMessage? tryParse(String payload) {
    // SSDP is defined over CRLF, but tolerating a bare LF line break
    // costs nothing and keeps a stack that answers with LF-only line
    // endings from being invisible; a leading blank line (buffered
    // reads do this) must not hide the request line either.
    final lines = payload.split(RegExp(r'\r?\n'));
    if (lines.every((line) => line.trim().isEmpty)) {
      return null;
    }

    final requestLine = lines.firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    if (requestLine.isEmpty) {
      return null;
    }

    final String method;
    if (requestLine.startsWith('NOTIFY')) {
      method = 'NOTIFY';
    } else if (requestLine.startsWith('M-SEARCH')) {
      method = 'M-SEARCH';
    } else if (requestLine.startsWith('HTTP/1.')) {
      method = 'RESPONSE';
    } else {
      return null;
    }

    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      headers[line.substring(0, colon).trim().toLowerCase()] = line.substring(colon + 1).trim();
    }

    if (headers.isEmpty) {
      return null;
    }

    return SsdpMessage(method: method, headers: headers);
  }

  /// Whether this is the departure announcement of a device.
  bool get isByebye =>
      method == 'NOTIFY' &&
      (headers['nts']?.toUpperCase() == 'SSDP:BYEBYE' || (headers['nt'] ?? '').contains('ssdp:byebye'));

  /// Whether this is an arrival or renewal alive announcement.
  bool get isAlive => method == 'NOTIFY' && !isByebye && (headers['nt'] ?? '').isNotEmpty;

  /// Whether this answers an M-SEARCH.
  bool get isSearchResponse => method == 'RESPONSE';

  /// The device/service notification type.
  String? get notificationType => headers['nt'] ?? headers['st'];

  /// The unique service name — carries the device UDN.
  String? get usn => headers['usn'];

  /// Where to fetch the device description document.
  String? get location => headers['location'];

  /// Seconds until this announcement must be considered stale.
  ///
  /// Defaults to 30 when absent or malformed, matching the spec's
  /// guidance for NOTIFY alive without an explicit max-age and
  /// erring short: a stale-but-listed device the user can select and
  /// then fail to cast to is worse than one that briefly disappears.
  Duration get cacheLifetime {
    final raw = headers['cache-control'] ?? '';
    final match = RegExp(r'max-age\s*=\s*(\d+)').firstMatch(raw);
    final seconds = match == null ? null : int.tryParse(match.group(1)!);
    return Duration(seconds: seconds ?? 30);
  }

  /// The stable device identity extracted from the USN, up to the
  /// first `::` (the upnp device root).
  String? get deviceId {
    final value = usn;
    if (value == null) {
      return null;
    }
    final root = value.split('::').first;
    return root.startsWith('uuid:') ? root : null;
  }

  @override
  String toString() => 'SsdpMessage($method, usn: $usn)';
}

/// Builds and reads the bytes on the wire.
abstract final class SsdpProtocol {
  /// The SSDP multicast group and port.
  static const String multicastAddress = '239.255.255.250';

  /// The SSDP port.
  static const int port = 1900;

  /// The search target that finds DLNA renderers.
  static const String mediaRendererTarget = 'urn:schemas-upnp-org:device:MediaRenderer:1';

  /// Builds an M-SEARCH request for [searchTarget].
  ///
  /// MAN is required (`ssdp:discover`); MX bounds how long the
  /// responders may stagger their replies, which on a busy network is
  /// what keeps a thousand responses from colliding on one socket
  /// read loop.
  static List<int> buildSearch([String searchTarget = mediaRendererTarget]) {
    final request = [
      'M-SEARCH * HTTP/1.1',
      'HOST: $multicastAddress:$port',
      'MAN: "ssdp:discover"',
      'MX: 3',
      'ST: $searchTarget',
      '',
      '',
    ].join('\r\n');
    return utf8.encode(request);
  }
}
