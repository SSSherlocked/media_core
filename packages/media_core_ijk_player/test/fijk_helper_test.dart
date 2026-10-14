import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/media_core.dart' show HttpHeaderError;

import 'package:media_core_ijk_player/src/fijk_helper.dart';

void main() {
  group('FijkHelper.sourceHeaderOptions', () {
    test('lifts user-agent out and joins the rest as CRLF lines', () {
      final options = FijkHelper.sourceHeaderOptions(<String, String>{
        'User-Agent': 'test-agent',
        'Referer': 'https://www.bilibili.com/',
      });

      expect(options['user_agent'], 'test-agent');
      // ijkplayer's own format: no space after the colon, names lower-cased
      // because that is how it matches them.
      expect(options['headers'], 'referer:https://www.bilibili.com/\r\n');
      expect(options['headers'], isNot(contains('user-agent')));
    });

    test('a header name carrying a newline or colon is refused', () {
      // ijkplayer writes the whole map into one native option string, so an
      // unchecked name would forge additional header lines in the request the
      // CDN sees. Refusing is the framework's rule, not this adapter's.
      expect(
        () => FijkHelper.sourceHeaderOptions(<String, String>{'X-Bad\r\nInjected: yes': 'value'}),
        throwsA(isA<HttpHeaderError>()),
      );
      expect(
        () => FijkHelper.sourceHeaderOptions(<String, String>{'Host:evil.example.com': 'value'}),
        throwsA(isA<HttpHeaderError>()),
      );
    });

    test('a value carrying a newline is refused rather than rewritten', () {
      // Replacing the newline with a space would send a cookie the site never
      // issued, and the request would fail in a way that points nowhere.
      expect(
        () => FijkHelper.sourceHeaderOptions(<String, String>{'Cookie': 'a=1\r\nX-Injected: yes'}),
        throwsA(isA<HttpHeaderError>().having((e) => e.headerName, 'headerName', 'Cookie')),
      );
    });

    test('an empty name or value is refused', () {
      expect(() => FijkHelper.sourceHeaderOptions(<String, String>{'': 'value'}), throwsA(isA<HttpHeaderError>()));
      expect(() => FijkHelper.sourceHeaderOptions(<String, String>{'X-Empty': '   '}), throwsA(isA<HttpHeaderError>()));
    });

    test('an empty map produces an empty option and no user agent', () {
      final options = FijkHelper.sourceHeaderOptions(const <String, String>{});

      expect(options['headers'], isEmpty);
      expect(options.containsKey('user_agent'), isFalse);
    });
  });
}
