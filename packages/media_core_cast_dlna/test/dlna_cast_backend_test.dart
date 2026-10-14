import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/casting/cast_device.dart';
import 'package:media_core/casting/cast_media.dart';
import 'package:media_core/casting/cast_transport.dart';
import 'package:media_core/casting/media_cast_backend.dart';
import 'package:media_core_cast_dlna/src/dlna_cast_backend.dart';
import 'package:media_core_cast_dlna/src/http_transport.dart';
import 'package:media_core_cast_dlna/src/ssdp_message.dart';
import 'package:media_core_cast_dlna/src/ssdp_source.dart';

const _description = '''
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>Salon TV</friendlyName>
    <UDN>uuid:TV-001</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/av</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/rc</controlURL>
      </service>
    </serviceList>
  </device>
</root>
''';

SsdpMessage _alive({String usn = 'uuid:TV-001', String location = 'http://192.168.1.40/desc.xml'}) {
  return SsdpMessage(
    method: 'NOTIFY',
    headers: <String, String>{
      'nt': 'urn:schemas-upnp-org:device:MediaRenderer:1',
      'nts': 'ssdp:alive',
      'usn': usn,
      'location': location,
      'cache-control': 'max-age=1800',
    },
  );
}

SsdpMessage _byebye({String usn = 'uuid:TV-001'}) {
  return SsdpMessage(
    method: 'NOTIFY',
    headers: <String, String>{'nt': 'ssdp:byebye', 'nts': 'ssdp:byebye', 'usn': usn},
  );
}

class _ScriptedSource implements SsdpSource {
  final controller = StreamController<SsdpMessage>.broadcast();

  @override
  Stream<SsdpMessage> get messages => controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    await controller.close();
  }
}

void main() {
  late _ScriptedSource source;
  late DlnaCastBackend backend;
  late List<CastEvent> seen;
  final posts = <String>[];
  SoapResponse Function(String action, String body)? responder;

  Future<void> drain() => Future<void>.delayed(Duration.zero);

  setUp(() {
    source = _ScriptedSource();
    posts.clear();
    responder = null;
    seen = <CastEvent>[];
    backend = DlnaCastBackend(
      discovery: source,
      fetchDescription: (url) async => _description,
      post: (url, action, headers, body) async {
        posts.add(action);
        final answer = responder?.call(action, body);
        return answer ?? const SoapResponse(statusCode: 200, body: '<s:Envelope></s:Envelope>');
      },
    );
    backend.events.listen(seen.add);
  });

  tearDown(() => backend.dispose());

  group('discovery to picker', () {
    test('an announcement resolves its description and surfaces a device', () async {
      await backend.startDiscovery();
      source.controller.add(_alive());
      await drain();

      expect(backend.devices, hasLength(1));
      final device = backend.devices.single;
      expect(device.name, 'Salon TV');
      expect(device.serviceEndpoints['AVTransport'], 'http://192.168.1.40/av');
      expect(seen, contains(isA<DeviceFound>()));
    });

    test('a renewal does not re-fetch or duplicate the device', () async {
      var fetches = 0;
      backend = DlnaCastBackend(
        discovery: source,
        fetchDescription: (url) async {
          fetches++;
          return _description;
        },
        post: (url, action, headers, body) async => const SoapResponse(statusCode: 200, body: ''),
      );
      await backend.startDiscovery();

      source.controller.add(_alive());
      await drain();
      source.controller.add(_alive());
      await drain();

      expect(fetches, 1);
      expect(backend.devices, hasLength(1));
    });

    test('a byebye removes the device', () async {
      await backend.startDiscovery();
      source.controller.add(_alive());
      await drain();
      expect(backend.devices, hasLength(1));

      source.controller.add(_byebye());
      await drain();

      expect(backend.devices, isEmpty);
      expect(seen.whereType<DeviceLost>(), hasLength(1));
    });

    test('an unparseable description yields a fault, not a device', () async {
      backend = DlnaCastBackend(
        discovery: source,
        fetchDescription: (url) async => '<broken',
        post: (url, action, headers, body) async => const SoapResponse(statusCode: 200, body: ''),
      );
      final events = <CastEvent>[];
      backend.events.listen(events.add);
      await backend.startDiscovery();

      source.controller.add(_alive());
      await drain();

      expect(backend.devices, isEmpty);
      expect(events.whereType<CastFault>(), hasLength(1));
      await backend.dispose();
    });
  });

  group('transport commands', () {
    Future<CastDevice> announced() async {
      await backend.startDiscovery();
      source.controller.add(_alive());
      await drain();
      return backend.devices.single;
    }

    test('setUri posts the DIDL and play the action header', () async {
      final device = await announced();

      await backend.setMedia(device, const CastMedia(url: 'http://cdn/m.mp4', title: 'M'));
      await backend.play(device);

      expect(posts, hasLength(2));
      expect(posts.first, contains('#SetAVTransportURI'));
      expect(posts.last, contains('#Play'));
    });

    test('a device fault raises CastException', () async {
      responder = (action, body) => const SoapResponse(
        statusCode: 500,
        body: '''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>
<faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring>
<detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>701</errorCode>
<errorDescription>TransportStateError</errorDescription></UPnPError></detail>
</s:Fault></s:Body></s:Envelope>
''',
      );
      final device = await announced();

      await expectLater(
        backend.play(device),
        throwsA(isA<CastException>().having((e) => e.message, 'message', contains('701'))),
      );
    });

    test('GetPositionInfo decodes into a position', () async {
      responder = (action, body) => const SoapResponse(
        statusCode: 200,
        body: '''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
<u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
<RelTime>00:01:23.000</RelTime><TrackDuration>00:45:00</TrackDuration>
</u:GetPositionInfoResponse></s:Body></s:Envelope>
''',
      );
      final device = await announced();

      final position = await backend.position(device);

      expect(position.position, const Duration(minutes: 1, seconds: 23));
      expect(position.duration, const Duration(minutes: 45));
    });

    test('an unreachable device yields the unknown position, not a throw', () async {
      responder = (action, body) => throw Exception('socket closed');
      final device = await announced();

      final position = await backend.position(device);

      expect(position.transportState, CastTransportState.unknown);
    });

    test('volume goes to the RenderingControl endpoint', () async {
      responder = (action, body) => const SoapResponse(statusCode: 200, body: '');
      final device = await announced();

      await backend.setVolume(device, 42);

      expect(posts.single, contains('#SetVolume'));
    });

    test('a device with no AVTransport endpoint is refused', () async {
      await backend.startDiscovery();
      const orphan = CastDevice(id: 'x', name: 'x', backendId: 'dlna');

      await expectLater(backend.play(orphan), throwsA(isA<CastException>()));
    });
  });
}

class SocketErrorStub implements Exception {}
