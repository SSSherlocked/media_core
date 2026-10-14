import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/casting/cast_media.dart';

import 'package:media_core_cast_dlna/src/didl_lite.dart';
import 'package:media_core_cast_dlna/src/dlna_device_description.dart';
import 'package:media_core_cast_dlna/src/soap.dart';
import 'package:media_core_cast_dlna/src/ssdp_message.dart';

const _aliveTv = '''
NOTIFY * HTTP/1.1
HOST: 239.255.255.250:1900
CACHE-CONTROL: max-age=1800
LOCATION: http://192.168.1.40:9197/upnp/desc.xml
NT: urn:schemas-upnp-org:device:MediaRenderer:1
NTS: ssdp:alive
USN: uuid:TV-001::urn:schemas-upnp-org:device:MediaRenderer:1
''';

void main() {
  group('SsdpMessage', () {
    test('parses an alive announcement', () {
      final message = SsdpMessage.tryParse(_aliveTv)!;

      expect(message.method, 'NOTIFY');
      expect(message.isAlive, isTrue);
      expect(message.isByebye, isFalse);
      expect(message.deviceId, 'uuid:TV-001');
      expect(message.location, 'http://192.168.1.40:9197/upnp/desc.xml');
      expect(message.cacheLifetime, const Duration(seconds: 1800));
    });

    test('recognises byebye by NTS and by NT', () {
      expect(SsdpMessage.tryParse(_aliveTv.replaceFirst('ssdp:alive', 'ssdp:byebye'))!.isByebye, isTrue);
      final ntStyle = _aliveTv
          .replaceFirst('NTS: ssdp:alive', 'NTS: ssdp:byebye')
          .replaceFirst('NT: urn:schemas-upnp-org:device:MediaRenderer:1', 'NT: ssdp:byebye');
      expect(SsdpMessage.tryParse(ntStyle)!.isByebye, isTrue);
    });

    test('a search response is distinguished from a notification', () {
      const response = '''
HTTP/1.1 200 OK
CACHE-CONTROL: max-age=1800
ST: urn:schemas-upnp-org:device:MediaRenderer:1
USN: uuid:TV-002::urn:schemas-upnp-org:device:MediaRenderer:1
LOCATION: http://192.168.1.41:8090/desc.xml
''';

      final message = SsdpMessage.tryParse(response)!;

      expect(message.method, 'RESPONSE');
      expect(message.isSearchResponse, isTrue);
      expect(message.isAlive, isFalse);
      expect(message.deviceId, 'uuid:TV-002');
    });

    test('missing cache-control defaults to a short lifetime', () {
      final noCache = _aliveTv.replaceFirst('CACHE-CONTROL: max-age=1800\n', '');

      expect(SsdpMessage.tryParse(noCache)!.cacheLifetime, const Duration(seconds: 30));
    });

    test('garbage is skipped, not thrown', () {
      expect(SsdpMessage.tryParse(''), isNull);
      expect(SsdpMessage.tryParse('GET / HTTP/1.1\r\nHost: x\r\n'), isNull);
      expect(SsdpMessage.tryParse('NOTIFY * HTTP/1.1\r\n\r\n'), isNull);
    });

    test('buildSearch carries the required MAN and target', () {
      final bytes = SsdpProtocol.buildSearch();
      final text = String.fromCharCodes(bytes);

      expect(text, contains('M-SEARCH * HTTP/1.1'));
      expect(text, contains('MAN: "ssdp:discover"'));
      expect(text, contains('ST: ${SsdpProtocol.mediaRendererTarget}'));
    });
  });

  group('DlnaDeviceDescription.parse', () {
    const description = '''
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>Salon TV</friendlyName>
    <manufacturer>Anyka</manufacturer>
    <modelName>K7</modelName>
    <UDN>uuid:TV-001</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/upnp/ctrl/AVTransport</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>upnp/ctrl/RC</controlURL>
      </service>
    </serviceList>
  </device>
</root>
''';
    final location = Uri.parse('http://192.168.1.40:9197/upnp/desc.xml');

    test('reads identity and resolves both relative URL styles', () {
      final parsed = DlnaDeviceDescription.parse(description, location: location);

      expect(parsed.udn, 'uuid:TV-001');
      expect(parsed.friendlyName, 'Salon TV');
      expect(parsed.avTransport.controlUrl, 'http://192.168.1.40:9197/upnp/ctrl/AVTransport');
      // A bare relative control URL anchors at the host root, not at
      // the description document's path.
      expect(parsed.renderingControl!.controlUrl, 'http://192.168.1.40:9197/upnp/ctrl/RC');
    });

    test('absolute control URLs pass through untouched', () {
      final absolute = description.replaceAll('/upnp/ctrl/AVTransport', 'http://10.0.0.5:8080/av');

      final parsed = DlnaDeviceDescription.parse(absolute, location: location);

      expect(parsed.avTransport.controlUrl, 'http://10.0.0.5:8080/av');
    });

    test('a device without AVTransport is refused', () {
      final noTransport = description.replaceAll(RegExp('<service>.*?AVTransport.*?</service>', dotAll: true), '');

      expect(() => DlnaDeviceDescription.parse(noTransport, location: location), throwsA(isA<FormatException>()));
    });

    test('a missing UDN is refused', () {
      final noUdn = description.replaceAll('<UDN>uuid:TV-001</UDN>', '');

      expect(() => DlnaDeviceDescription.parse(noUdn, location: location), throwsA(isA<FormatException>()));
    });

    test('malformed XML is refused', () {
      expect(() => DlnaDeviceDescription.parse('<root><device>', location: location), throwsA(isA<FormatException>()));
    });
  });

  group('DidlLite.build', () {
    test('escapes markup in title and url', () {
      final didl = DidlLite.build(
        const CastMedia(url: 'https://cdn.example.com/a&b<b>.mp4', title: 'Tom & Jerry <The Movie>'),
      );

      expect(didl, contains('&amp;b&lt;b&gt;'));
      expect(didl, contains('Tom &amp; Jerry &lt;The Movie&gt;'));
      // No raw ampersand or angle bracket may survive inside the
      // title — that is markup injection into the device's XML.
      expect(didl, isNot(contains('<dc:title>Tom & Jerry')));
    });

    test('mime comes from the declaration, else from the extension', () {
      final declared = DidlLite.build(const CastMedia(url: 'https://x/y', title: 't', mimeType: 'video/x-matroska'));
      final guessed = DidlLite.build(const CastMedia(url: 'https://x/y.mkv', title: 't'));

      expect(declared, contains('http-get:video/x-matroska:'));
      expect(guessed, contains('http-get:video/x-matroska:'));
    });

    test('an unknown mime still emits a usable res line', () {
      final didl = DidlLite.build(const CastMedia(url: 'https://x/stream', title: 't'));

      // MIME `*` with an empty profile: legal, and devices fall back
      // to sniffing. A fabricated profile hint would be worse than no
      // hint at all.
      expect(didl, contains('protocolInfo="http-get:*:"'));
      expect(didl, contains('mimeType="*"'));
    });

    test('creator and artwork reach the document', () {
      final didl = DidlLite.build(
        CastMedia(
          url: 'https://x/a.mp3',
          title: 'Song',
          creator: 'Band',
          artworkUrl: Uri.parse('https://x/cover.jpg'),
          objectClass: 'audio.item',
        ),
      );

      expect(didl, contains('<dc:creator>Band</dc:creator>'));
      expect(didl, contains('<upnp:albumArtURI>https://x/cover.jpg</upnp:albumArtURI>'));
      expect(didl, contains('<upnp:class>audio.item</upnp:class>'));
    });
  });

  group('Soap', () {
    const service = SoapServiceRef(type: 'urn:schemas-upnp-org:service:AVTransport:1', controlUrl: 'http://tv/av');

    test('envelopes carry the exact argument names devices match literally', () {
      final play = Soap.play(service: service);

      expect(play.action, '"urn:schemas-upnp-org:service:AVTransport:1#Play"');
      expect(play.body, contains('<InstanceID>0</InstanceID>'));
      expect(play.body, contains('<Speed>1</Speed>'));
      expect(play.headers['Content-Type'], contains('text/xml'));
    });

    test('seek encodes a REL_TIME clock string', () {
      final seek = Soap.seek(service: service, target: const Duration(minutes: 65, seconds: 3));

      expect(seek.body, contains('<Unit>REL_TIME</Unit>'));
      expect(seek.body, contains('<Target>01:05:03</Target>'));
    });

    test('clock strings format and round-trip, fractions tolerated', () {
      expect(Soap.formatClock(const Duration(hours: 2, minutes: 5, seconds: 9)), '02:05:09');
      expect(Soap.parseClock('00:01:30.500'), const Duration(minutes: 1, seconds: 30, milliseconds: 500));
      expect(Soap.parseClock('01:02:03'), const Duration(hours: 1, minutes: 2, seconds: 3));
    });

    test('non-clock position fields parse to null instead of throwing', () {
      expect(Soap.parseClock('NOT_TRANSPRENT'), isNull);
      expect(Soap.parseClock(''), isNull);
      expect(Soap.parseClock(null), isNull);
    });

    test('arguments are read by local name across namespace prefixes', () {
      const response = '''
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
 <s:Body>
  <u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
   <RelTime>00:00:42.000</RelTime>
   <TrackDuration>00:00:00</TrackDuration>
  </u:GetPositionInfoResponse>
 </s:Body>
</s:Envelope>
''';

      expect(Soap.argument(response, 'RelTime'), '00:00:42.000');
      expect(Soap.parseClock(Soap.argument(response, 'TrackDuration')), Duration.zero);
    });

    test('a device fault decodes its UPnP error code', () {
      const fault = '''
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
 <s:Body><s:Fault>
  <faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring>
  <detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
   <errorCode>501</errorCode><errorDescription>Invalid Action</errorDescription>
  </UPnPError></detail>
 </s:Fault></s:Body>
</s:Envelope>
''';

      final parsed = Soap.parseFault(fault);

      expect(parsed, isNotNull);
      expect(parsed!.errorCode, '501');
      expect(parsed.errorDescription, 'Invalid Action');
    });
  });
}
