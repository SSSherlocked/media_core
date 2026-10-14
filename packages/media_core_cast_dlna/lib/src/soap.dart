import 'dart:convert' show utf8;

import 'package:xml/xml.dart';

/// A UPnP service description used when building a SOAP action.
class SoapServiceRef {
  /// Creates a service reference.
  const SoapServiceRef({required this.type, required this.controlUrl});

  /// The full `urn:schemas-upnp-org:service:<name>:<version>` URN.
  final String type;

  /// Resolved absolute control URL.
  final String controlUrl;

  /// `AVTransport` / `RenderingControl` extracted from the URN.
  String get name {
    final match = RegExp(':service:([^:]+)').firstMatch(type);
    return match?.group(1) ?? type;
  }
}

/// A rendered SOAP request: body bytes plus the HTTP headers a UPnP
/// control POST must carry.
class SoapRequest {
  /// Creates a request.
  const SoapRequest({required this.action, required this.body, required this.headers});

  /// The SOAP action header value (quoted, per UPnP).
  final String action;

  /// The envelope XML.
  final String body;

  /// HTTP headers: SOAPAction, Content-Type, Content-Length.
  final Map<String, String> headers;
}

/// Builds the SOAP envelopes DLNA casting needs.
///
/// UPnP control is one POST per action with a document-typed body;
/// there is no session and no ordering guarantee across actions, so
/// the encoder is pure and stateless. Argument names match the service
/// SCCDs exactly — the device matches them literally, so a wrong
/// casing (or an `InstanceId` that should have been `InstanceID`) is a
/// 402/500 fault on every real device, not a portable slip.
abstract final class Soap {
  /// `SetAVTransportURI`: load media on the device.
  static SoapRequest setUri({
    required SoapServiceRef service,
    required String didl,
    required String url,
    int instanceId = 0,
  }) {
    return _request(
      service: service,
      action: 'SetAVTransportURI',
      arguments: <String, String>{'InstanceID': '$instanceId', 'CurrentURI': url, 'CurrentURIMetaData': didl},
    );
  }

  /// `Play` with the default `1` speed.
  static SoapRequest play({required SoapServiceRef service, int instanceId = 0}) {
    return _request(
      service: service,
      action: 'Play',
      arguments: <String, String>{'InstanceID': '$instanceId', 'Speed': '1'},
    );
  }

  /// `Pause`.
  static SoapRequest pause({required SoapServiceRef service, int instanceId = 0}) {
    return _request(service: service, action: 'Pause', arguments: <String, String>{'InstanceID': '$instanceId'});
  }

  /// `Stop`.
  static SoapRequest stop({required SoapServiceRef service, int instanceId = 0}) {
    return _request(service: service, action: 'Stop', arguments: <String, String>{'InstanceID': '$instanceId'});
  }

  /// `Seek` to an absolute REL_TIME target.
  static SoapRequest seek({required SoapServiceRef service, required Duration target, int instanceId = 0}) {
    return _request(
      service: service,
      action: 'Seek',
      arguments: <String, String>{'InstanceID': '$instanceId', 'Unit': 'REL_TIME', 'Target': formatClock(target)},
    );
  }

  /// `GetPositionInfo` — position + duration + transport state in one
  /// round trip, which is why polling uses this and not
  /// GetTransportInfo separately.
  static SoapRequest getPositionInfo({required SoapServiceRef service, int instanceId = 0}) {
    return _request(
      service: service,
      action: 'GetPositionInfo',
      arguments: <String, String>{'InstanceID': '$instanceId'},
    );
  }

  /// `GetTransportInfo`.
  static SoapRequest getTransportInfo({required SoapServiceRef service, int instanceId = 0}) {
    return _request(
      service: service,
      action: 'GetTransportInfo',
      arguments: <String, String>{'InstanceID': '$instanceId'},
    );
  }

  /// `GetVolume` on RenderingControl.
  static SoapRequest getVolume({required SoapServiceRef service, String channel = 'Master', int instanceId = 0}) {
    return _request(
      service: service,
      action: 'GetVolume',
      arguments: <String, String>{'InstanceID': '$instanceId', 'Channel': channel},
    );
  }

  /// `SetVolume` on RenderingControl.
  static SoapRequest setVolume({
    required SoapServiceRef service,
    required int desiredVolume,
    String channel = 'Master',
    int instanceId = 0,
  }) {
    return _request(
      service: service,
      action: 'SetVolume',
      arguments: <String, String>{'InstanceID': '$instanceId', 'Channel': channel, 'DesiredVolume': '$desiredVolume'},
    );
  }

  /// `H:MM:SS.mmm` as DLNA clock strings expect.
  static String formatClock(Duration value) {
    final hours = value.inHours.toString().padLeft(2, '0');
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  /// Parses `H:MM:SS` (with optional fraction). Null when malformed —
  /// devices do sometimes return `NOT_TRANSPRENT` or empty strings in
  /// position fields, and a caller that assumed a parse would treat
  /// its own parse crash as the device's fault.
  static Duration? parseClock(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final parts = value.split(':');
    if (parts.length != 3) {
      return null;
    }
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = double.tryParse(parts[2]);
    if (hours == null || minutes == null || seconds == null) {
      return null;
    }
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds.floor(),
      milliseconds: ((seconds - seconds.floor()) * 1000).round(),
    );
  }

  /// A UPnP fault (`<s:Fault>`) decoded from an action response.
  static SoapFault? parseFault(String body) {
    try {
      final document = XmlDocument.parse(body);
      final fault = _descendant(document.rootElement, 'Fault');
      if (fault == null) {
        return null;
      }
      final detail = _descendant(fault, 'detail');
      final upnp = detail == null ? null : _firstChildElement(detail);
      return SoapFault(
        faultCode: _descendant(fault, 'faultCode')?.innerText.trim(),
        faultString: _descendant(fault, 'faultString')?.innerText.trim(),
        errorCode: upnp == null ? null : _descendant(upnp, 'errorCode')?.innerText.trim(),
        errorDescription: upnp == null ? null : _descendant(upnp, 'errorDescription')?.innerText.trim(),
      );
    } on XmlException {
      return null;
    }
  }

  /// Reads a single output argument from a response body.
  ///
  /// The XML namespace prefix differs across firmwares (`s:`, `SOAP-ENV:`,
  /// none) while the *local* names do not, so lookups match on local
  /// name; matching by qualified name is the classic way a UPnP client
  /// works on half the devices it ships for.
  static String? argument(String body, String name) {
    try {
      final document = XmlDocument.parse(body);
      final found = _descendant(document.rootElement, name);
      return found?.innerText.trim();
    } on XmlException {
      return null;
    }
  }

  static SoapRequest _request({
    required SoapServiceRef service,
    required String action,
    required Map<String, String> arguments,
  }) {
    final envelope = StringBuffer()
      ..write('<?xml version="1.0" encoding="utf-8"?>')
      ..write('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ')
      ..write('s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">')
      ..write('<s:Body>')
      ..write('<u:$action xmlns:u="${_escape(service.type)}">');

    arguments.forEach((key, value) {
      envelope.write('<$key>${_escape(value)}</$key>');
    });

    envelope
      ..write('</u:$action>')
      ..write('</s:Body></s:Envelope>');

    final body = envelope.toString();
    final quoted = '"${service.type}#$action"';

    return SoapRequest(
      action: quoted,
      body: body,
      headers: <String, String>{
        'SOAPAction': quoted,
        'Content-Type': 'text/xml; charset="utf-8"',
        // The transport writes the body as UTF-8, so the declared length
        // has to be the byte count: a CJK track title inside the DIDL
        // makes `body.length` (UTF-16 code units) too small and the
        // renderer reads a truncated envelope.
        'Content-Length': '${utf8.encode(body).length}',
      },
    );
  }

  static String _escape(String value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  static XmlElement? _descendant(XmlElement root, String localName) {
    for (final element in root.descendantElements) {
      if (element.localName == localName) {
        return element;
      }
    }
    return null;
  }

  static XmlElement? _firstChildElement(XmlElement parent) {
    for (final child in parent.children.whereType<XmlElement>()) {
      return child;
    }
    return null;
  }
}

/// A decoded UPnP SOAP fault.
class SoapFault implements Exception {
  /// Creates a fault.
  const SoapFault({this.faultCode, this.faultString, this.errorCode, this.errorDescription});

  /// Outer SOAP fault code.
  final String? faultCode;

  /// Outer SOAP fault string.
  final String? faultString;

  /// UPnP control error code (`502 = invalid action`, etc.).
  final String? errorCode;

  /// UPnP control error description.
  final String? errorDescription;

  @override
  String toString() => 'SoapFault($errorCode ${errorDescription ?? faultString ?? faultCode ?? ''})';
}
