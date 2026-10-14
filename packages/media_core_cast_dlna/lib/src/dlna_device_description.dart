import 'package:xml/xml.dart';

/// A control endpoint parsed from a UPnP device description.
final class DlnaService {
  /// Creates a service entry.
  const DlnaService({required this.type, required this.controlUrl, this.eventUrl});

  /// Full service type URN, e.g.
  /// `urn:schemas-upnp-org:service:AVTransport:1`.
  final String type;

  /// Resolved absolute URL of the control endpoint.
  final String controlUrl;

  /// Resolved absolute URL of the eventing endpoint, when present.
  final String? eventUrl;

  /// The short service name (`AVTransport`, `RenderingControl`).
  String get name {
    final match = RegExp(':service:([^:]+)').firstMatch(type);
    return match?.group(1) ?? type;
  }
}

/// The parts of a UPnP device description media_core casting needs.
///
/// A real description document is large (presentations, device lists,
/// embedded capabilities); this type carries only identity and the
/// service endpoints, because those are the only things a controller
/// can act on — everything else a renderer reports is either honored
/// by the device itself or is a UI decoration the host can read from
/// `rawXml` if it truly needs it.
final class DlnaDeviceDescription {
  /// Creates a parsed description.
  const DlnaDeviceDescription({
    required this.udn,
    required this.friendlyName,
    required this.services,
    this.manufacturer,
    this.modelName,
    this.baseUrl,
  });

  /// Parses a device description document.
  ///
  /// [location] is the URL the document was fetched from; service
  /// control URLs are either absolute or root-relative against it.
  ///
  /// Throws [FormatException] when identity or services cannot be
  /// read — a document without a UDN or an AVTransport service is not
  /// a renderer, and pretending otherwise would let the user pick a
  /// dead device.
  factory DlnaDeviceDescription.parse(String xml, {required Uri location}) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException {
      throw FormatException('device description is not valid XML', xml);
    }

    final root = document.rootElement;
    if (root.localName != 'device' && root.localName != 'root') {
      throw const FormatException('device description root is not <device>/<root>');
    }

    final device = root.localName == 'root' ? _first(root, 'device') : root;
    if (device == null) {
      throw const FormatException('device description has no <device> element');
    }

    final udn = _text(device, 'UDN');
    if (udn == null || udn.trim().isEmpty) {
      throw const FormatException('device description has no UDN');
    }

    final services = <DlnaService>[];
    final serviceList = _first(device, 'serviceList');
    if (serviceList != null) {
      for (final service in serviceList.findElements('service')) {
        final type = _text(service, 'serviceType');
        final control = _text(service, 'controlURL');
        if (type == null || control == null || control.isEmpty) {
          continue;
        }
        services.add(
          DlnaService(
            type: type,
            controlUrl: resolve(location, control),
            eventUrl: _text(service, 'eventSubURL') == null ? null : resolve(location, _text(service, 'eventSubURL')!),
          ),
        );
      }
    }

    final avTransport = services.where((s) => s.name == 'AVTransport').firstOrNull;
    if (avTransport == null) {
      throw const FormatException('device exposes no AVTransport service; it cannot be cast to');
    }

    return DlnaDeviceDescription(
      udn: udn.trim(),
      friendlyName: _text(device, 'friendlyName') ?? udn.trim(),
      manufacturer: _text(device, 'manufacturer'),
      modelName: _text(device, 'modelName'),
      baseUrl: '${location.scheme}://${location.authority}',
      services: List<DlnaService>.unmodifiable(services),
    );
  }

  /// Resolves a (possibly relative) UPnP URL against the document
  /// location.
  ///
  /// UPnP control URLs are notoriously mixed: some devices emit
  /// `/ctrl-avtransport`, some `ctrl-avtransport` with no slash, some
  /// full absolute URLs. The bare-relative form must not resolve
  /// against the location's *path* (which for
  /// `/description.xml` would yield a wrong sibling path), so it is
  /// anchored at the root.
  static String resolve(Uri location, String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final base = Uri(scheme: location.scheme, host: location.host, port: location.hasPort ? location.port : null);
    if (url.startsWith('/')) {
      return base.replace(path: url).toString();
    }
    return base.replace(path: '/$url').toString();
  }

  /// The unique device name.
  final String udn;

  /// Device-reported display name.
  final String friendlyName;

  /// Manufacturer as advertised.
  final String? manufacturer;

  /// Model as advertised.
  final String? modelName;

  /// `scheme://host:port` of the description document.
  final String? baseUrl;

  /// All advertised services.
  final List<DlnaService> services;

  /// The AVTransport endpoint every cast goes through.
  DlnaService get avTransport => services.firstWhere((s) => s.name == 'AVTransport');

  /// The volume endpoint, when the device has one.
  DlnaService? get renderingControl => services.where((s) => s.name == 'RenderingControl').firstOrNull;

  static XmlElement? _first(XmlElement parent, String name) {
    for (final element in parent.children.whereType<XmlElement>()) {
      if (element.localName == name) {
        return element;
      }
    }
    return null;
  }

  static String? _text(XmlElement parent, String name) => _first(parent, name)?.innerText.trim();
}
