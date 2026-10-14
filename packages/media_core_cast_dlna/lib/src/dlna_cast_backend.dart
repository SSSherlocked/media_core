import 'dart:async';

import 'package:media_core/casting/cast_device.dart';
import 'package:media_core/casting/cast_media.dart';
import 'package:media_core/casting/cast_transport.dart';
import 'package:media_core/casting/media_cast_backend.dart';
import 'package:media_core_cast_dlna/src/didl_lite.dart';
import 'package:media_core_cast_dlna/src/dlna_device_description.dart';
import 'package:media_core_cast_dlna/src/http_transport.dart';
import 'package:media_core_cast_dlna/src/soap.dart';
import 'package:media_core_cast_dlna/src/ssdp_discovery.dart';
import 'package:media_core_cast_dlna/src/ssdp_message.dart';
import 'package:media_core_cast_dlna/src/ssdp_source.dart';

/// [MediaCastBackend] over DLNA/UPnP: SSDP to find, HTTP+SOAP to
/// drive.
///
/// The DLNA model in one paragraph: SSDP announces devices with a
/// `LOCATION` pointing at a description document; that document lists
/// service control URLs; every action is one SOAP POST to a control
/// URL. There is no session and no authentication — which is exactly
/// why casting a URL the TV cannot fetch (token-gated with headers
/// only the app may send) fails *at the device*, and this backend's
/// duty is to surface that as a refused command rather than pretend
/// the cast succeeded.
///
/// A description fetch is fired per first announcement; a device whose
/// document cannot be fetched or parsed is never offered. A TV that
/// advertises but does not serve HTTP cannot accept a cast either, so
/// listing it would only add a dead row to a picker.
class DlnaCastBackend implements MediaCastBackend {
  /// Creates a backend.
  ///
  /// Every collaborator is injectable so the whole class is testable
  /// without a network: a scripted [SsdpDiscovery], a
  /// [fetchDescription] that returns canned XML, and a [post] that
  /// answers SOAP envelopes from a table.
  DlnaCastBackend({SsdpSource? discovery, DescriptionFetcher? fetchDescription, SoapPoster? post})
    : _discovery = discovery ?? SsdpDiscovery() {
    // The defaults each own an HttpClient. Keeping the object rather than
    // only its `call` tear-off is what makes [dispose] able to close the
    // pooled sockets; a caller-supplied function owns its own transport and
    // is left alone.
    if (fetchDescription != null) {
      _fetchDescription = fetchDescription;
    } else {
      final fetcher = HttpDescriptionFetcher();
      _ownedFetcher = fetcher;
      _fetchDescription = fetcher.call;
    }

    if (post != null) {
      _post = post;
    } else {
      final transport = HttpSoapTransport();
      _ownedTransport = transport;
      _post = transport.call;
    }
  }

  final SsdpSource _discovery;
  late final DescriptionFetcher _fetchDescription;
  late final SoapPoster _post;

  HttpDescriptionFetcher? _ownedFetcher;
  HttpSoapTransport? _ownedTransport;

  final StreamController<CastEvent> _events = StreamController<CastEvent>.broadcast();
  final Map<String, CastDevice> _devices = <String, CastDevice>{};
  final Map<String, DlnaDeviceDescription> _descriptions = <String, DlnaDeviceDescription>{};
  final Set<String> _fetching = <String>{};

  /// SSDP usn -> description UDN, for the devices whose two ids
  /// disagree.
  ///
  /// The spec says the USN's root equals the UDN, and most devices
  /// obey; devices that pad one side (a trailing service suffix, a
  /// re-formatted uuid) otherwise break exactly one thing — a BYEBYE
  /// arriving with an id the removal does not recognise, leaving a
  /// dead TV in the picker until its cache ages out.
  final Map<String, String> _usnToUdn = <String, String>{};

  StreamSubscription<SsdpMessage>? _subscription;
  bool _started = false;
  bool _closed = false;

  @override
  String get id => 'dlna';

  @override
  Stream<CastEvent> get events => _events.stream;

  @override
  List<CastDevice> get devices => List<CastDevice>.unmodifiable(_devices.values);

  @override
  Future<void> startDiscovery() async {
    if (_closed || _started) {
      return;
    }
    _started = true;
    _subscription = _discovery.messages.listen(_onMessage);
    await _discovery.start();
  }

  @override
  Future<void> dispose() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _discovery.stop();
    _devices.clear();
    _descriptions.clear();
    _usnToUdn.clear();
    _fetching.clear();
    // Only the transports this backend created are its to close; a
    // caller-supplied function brings its own lifecycle.
    _ownedFetcher?.close();
    _ownedTransport?.close();
    await _events.close();
  }

  @override
  Future<void> setMedia(CastDevice device, CastMedia media) async {
    final service = _transportOf(device);
    await _call(device, service, Soap.setUri(service: service, didl: DidlLite.build(media), url: media.url));
  }

  @override
  Future<void> play(CastDevice device) async {
    final service = _transportOf(device);
    await _call(device, service, Soap.play(service: service));
  }

  @override
  Future<void> pause(CastDevice device) async {
    final service = _transportOf(device);
    await _call(device, service, Soap.pause(service: service));
  }

  @override
  Future<void> stop(CastDevice device) async {
    final service = _transportOf(device);
    await _call(device, service, Soap.stop(service: service));
  }

  @override
  Future<void> seek(CastDevice device, Duration position) async {
    final service = _transportOf(device);
    await _call(device, service, Soap.seek(service: service, target: position));
  }

  /// Reads position and duration in one `GetPositionInfo`.
  ///
  /// A device that has stopped answering yields
  /// [CastPosition.unknown] instead of throwing: a controller's poll
  /// loop must be able to gray its progress ring out, not crash a UI
  /// widget over a TV that just left the Wi-Fi.
  @override
  Future<CastPosition> position(CastDevice device) async {
    final service = _transportOf(device);
    final request = Soap.getPositionInfo(service: service);
    try {
      final response = await _post(service.controlUrl, request.action, request.headers, request.body);
      final body = response.body;
      final relTime = Soap.parseClock(Soap.argument(body, 'RelTime'));
      final trackDuration = Soap.parseClock(Soap.argument(body, 'TrackDuration'));
      if (relTime == null && trackDuration == null) {
        return const CastPosition.unknown();
      }
      return CastPosition(position: relTime ?? Duration.zero, duration: trackDuration ?? Duration.zero);
    } on Object {
      return const CastPosition.unknown();
    }
  }

  @override
  Future<void> setVolume(CastDevice device, int percent) async {
    final rendering = _descriptions[device.id]?.renderingControl;
    if (rendering == null) {
      throw CastException('device exposes no RenderingControl service', deviceId: device.id);
    }
    final service = SoapServiceRef(type: rendering.type, controlUrl: rendering.controlUrl);
    await _call(device, service, Soap.setVolume(service: service, desiredVolume: percent));
  }

  void _onMessage(SsdpMessage message) {
    if (_closed) {
      return;
    }
    final id = message.deviceId;
    if (id == null) {
      return;
    }

    if (message.isByebye || message.method == 'EXPIRED') {
      final canonical = _usnToUdn[id] ?? id;
      final gone = _devices.remove(canonical);
      _descriptions.remove(canonical);
      _usnToUdn.remove(id);
      if (gone != null) {
        _events.add(DeviceLost(gone.id));
      }
      return;
    }

    final location = message.location;
    if (location == null) {
      return;
    }

    final knownUnder = _usnToUdn[id] ?? id;
    if (_devices.containsKey(knownUnder) || _fetching.contains(id)) {
      // A renewal of a known device. Re-fetching every cache cycle
      // would hammer the LAN, and a device that actually changed its
      // description re-announces with a byebye first.
      return;
    }

    unawaited(_resolve(id, location));
  }

  Future<void> _resolve(String usn, String location) async {
    if (!_fetching.add(usn)) {
      return;
    }
    try {
      final xml = await _fetchDescription(location);
      final description = DlnaDeviceDescription.parse(xml, location: Uri.parse(location));
      final device = CastDevice(
        id: description.udn,
        name: description.friendlyName,
        backendId: id,
        typeName: description.avTransport.type,
        manufacturer: description.manufacturer,
        modelName: description.modelName,
        serviceEndpoints: <String, String>{
          for (final service in description.services) service.name: service.controlUrl,
        },
      );
      _devices[device.id] = device;
      _descriptions[device.id] = description;
      _usnToUdn[usn] = device.id;
      _events.add(DeviceFound(device));
    } on Object catch (error) {
      // A description that cannot be fetched or parsed is not a
      // castable device; report the fault on the event stream where a
      // host can log or ignore it, instead of throwing inside a
      // listen callback and killing the subscription.
      _events.add(CastFault(deviceId: usn, message: 'device description failed', error: error));
    } finally {
      _fetching.remove(usn);
    }
  }

  SoapServiceRef _transportOf(CastDevice device) {
    final url = device.serviceEndpoints['AVTransport'];
    if (url == null) {
      throw CastException('device has no AVTransport control URL', deviceId: device.id);
    }
    return SoapServiceRef(type: device.typeName ?? 'urn:schemas-upnp-org:service:AVTransport:1', controlUrl: url);
  }

  Future<void> _call(CastDevice device, SoapServiceRef service, SoapRequest request) async {
    if (_closed) {
      throw const CastException('backend is disposed');
    }

    final SoapResponse response;
    try {
      response = await _post(service.controlUrl, request.action, request.headers, request.body);
    } on Object catch (error) {
      throw CastException('control request failed', deviceId: device.id, cause: error);
    }

    final fault = Soap.parseFault(response.body);
    if (fault != null) {
      throw CastException('device refused ${request.action}: $fault', deviceId: device.id, cause: fault);
    }
    if (response.statusCode ~/ 100 != 2) {
      throw CastException('device answered ${response.statusCode} to ${request.action}', deviceId: device.id);
    }
  }
}
