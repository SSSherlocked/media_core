import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_core_cast_dlna/src/ssdp_message.dart';
import 'package:media_core_cast_dlna/src/ssdp_source.dart';

/// A raw SSDP datagram: decoded text plus the address it came from.
class SsdpDatagram {
  /// Creates a datagram.
  const SsdpDatagram({required this.text, required this.from});

  /// UTF-8 decoded payload.
  final String text;

  /// The sending socket address, used for nothing today but kept
  /// because debugging a device that answers from the wrong interface
  /// is otherwise impossible.
  final InternetAddress from;
}

/// Creates the socket a [SsdpDiscovery] runs on.
///
/// Injected so tests can drive discovery from a scripted stream
/// instead of joining a multicast group a CI machine does not have.
typedef SsdpSocketFactory = Future<RawDatagramSocket> Function();

/// SSDP discovery: send M-SEARCH, listen for alive/byebye, expire
/// announcements on their own cache lifetime.
///
/// UPnP's freshness rule is that an announcement lives for the
/// `CACHE-CONTROL: max-age` it carried, renewed by the next NOTIFY or
/// search response; a device that simply stops answering is gone even
/// though nothing ever said BYEBYE (the Wi-Fi did not notify you).
/// Expiry is therefore tracked per device and enforced here, so a
/// picker cannot offer a TV that has been asleep for ten minutes.
class SsdpDiscovery implements SsdpSource {
  /// Creates discovery, optionally with a custom [socketFactory] and
  /// [searchInterval] for re-announcing.
  SsdpDiscovery({SsdpSocketFactory? socketFactory, this.searchInterval = const Duration(seconds: 12)})
    : _socketFactory = socketFactory ?? _defaultSocket;

  static Future<RawDatagramSocket> _defaultSocket() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

    try {
      socket.joinMulticast(InternetAddress(SsdpProtocol.multicastAddress));
    } on SocketException {
      // A host without a multicast-capable interface (some CI
      // containers, VPN-only machines) still gets search responses
      // unicast back to it; joining failed, the socket still works.
    }
    return socket;
  }

  final SsdpSocketFactory _socketFactory;

  /// How often to re-send M-SEARCH.
  final Duration searchInterval;

  RawDatagramSocket? _socket;
  Timer? _searchTimer;
  final Map<String, Timer> _expiry = <String, Timer>{};
  final StreamController<SsdpDatagram> _incoming = StreamController<SsdpDatagram>.broadcast();
  final StreamController<SsdpMessage> _messages = StreamController<SsdpMessage>.broadcast();

  bool _started = false;
  bool _closed = false;

  /// Every datagram received, before parsing. Diagnostic surface.
  Stream<SsdpDatagram> get rawDatagrams => _incoming.stream;

  /// Parsed SSDP messages.
  @override
  Stream<SsdpMessage> get messages => _messages.stream;

  /// Starts listening, sends the first search and repeats it.
  @override
  Future<void> start({String searchTarget = SsdpProtocol.mediaRendererTarget}) async {
    if (_closed || _started) {
      return;
    }
    _started = true;

    final socket = await _socketFactory();
    _socket = socket;

    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final datagram = socket.receive();
        if (datagram == null) {
          return;
        }
        final text = utf8.decode(datagram.data, allowMalformed: true);
        _incoming.add(SsdpDatagram(text: text, from: datagram.address));
        final message = SsdpMessage.tryParse(text);
        if (message != null) {
          _track(message);
          _messages.add(message);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _incoming.addError(error, stackTrace);
      },
    );

    await search(searchTarget);
    _searchTimer = Timer.periodic(searchInterval, (_) => unawaited(search(searchTarget)));
  }

  /// Sends one M-SEARCH to the multicast group.
  Future<void> search([String searchTarget = SsdpProtocol.mediaRendererTarget]) async {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    socket.send(
      Uint8List.fromList(SsdpProtocol.buildSearch(searchTarget)),
      InternetAddress(SsdpProtocol.multicastAddress),
      SsdpProtocol.port,
    );
  }

  void _track(SsdpMessage message) {
    final id = message.deviceId;
    if (id == null) {
      return;
    }
    if (message.isByebye) {
      _expiry.remove(id)?.cancel();
      return;
    }
    final lifetime = message.cacheLifetime;
    _expiry.remove(id)?.cancel();
    _expiry[id] = Timer(lifetime, () {
      // The announcement aged out with no renewal: report it as gone
      // on the message stream so a backend does not need a second
      // timer of its own.
      _messages.add(SsdpMessage(method: 'EXPIRED', headers: <String, String>{'usn': id}));
    });
  }

  /// Stops listening and releases the socket.
  @override
  Future<void> stop() async {
    _searchTimer?.cancel();
    _searchTimer = null;
    for (final timer in _expiry.values) {
      timer.cancel();
    }
    _expiry.clear();
    _socket?.close();
    _socket = null;
    _started = false;
    _closed = true;
    await _incoming.close();
    await _messages.close();
  }
}
