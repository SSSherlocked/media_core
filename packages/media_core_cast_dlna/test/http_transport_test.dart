import 'package:flutter_test/flutter_test.dart';

import 'package:media_core_cast_dlna/media_core_cast_dlna.dart';

void main() {
  group('HttpDescriptionFetcher', () {
    test('refuses a location that is not http or https', () {
      // The LOCATION comes out of an SSDP datagram, so it is input from
      // whatever answered on the LAN. Fetching anything else would let a
      // rogue device point this process at a local or embedded resource.
      final fetcher = HttpDescriptionFetcher();

      expect(() => fetcher('file:///etc/passwd'), throwsA(isA<FormatException>()));
      expect(() => fetcher('data:text/xml,<root/>'), throwsA(isA<FormatException>()));
    });
  });
}
