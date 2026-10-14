import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/network/http_header_sanitizer.dart';

void main() {
  group('HttpHeaderSanitizer.sanitize', () {
    test('lower-cases names and trims values, which cannot change meaning', () {
      final sanitized = HttpHeaderSanitizer.sanitize(<String, String>{
        'Referer': '  https://example.com/  ',
        'X-Token': 'abc',
      });

      expect(sanitized.keys, containsAll(<String>['referer', 'x-token']));
      expect(sanitized['referer'], 'https://example.com/');
    });

    test('nothing to send is an empty map, not an error', () {
      expect(HttpHeaderSanitizer.sanitize(null), isEmpty);
      expect(HttpHeaderSanitizer.sanitize(const <String, String>{}), isEmpty);
    });

    test('a name that is not a token is refused', () {
      for (final name in <String>['X-Bad\r\nInjected', 'Host:evil.example', 'X Space', '']) {
        expect(
          () => HttpHeaderSanitizer.sanitize(<String, String>{name: 'value'}),
          throwsA(isA<HttpHeaderError>()),
          reason: '"$name" would forge another header line or send nothing',
        );
      }
    });

    test('a value carrying CR, LF or NUL is refused rather than rewritten', () {
      for (final value in <String>['a\r\nX-Evil: 1', 'a\nb', 'a\u0000b']) {
        expect(() => HttpHeaderSanitizer.sanitize(<String, String>{'Cookie': value}), throwsA(isA<HttpHeaderError>()));
      }
    });

    test('an empty value is refused', () {
      // A caller passing '' almost always meant "I have no credential", and
      // sending an empty Authorization is indistinguishable from that mistake
      // three requests later when the CDN answers 403.
      expect(
        () => HttpHeaderSanitizer.sanitize(<String, String>{'Authorization': ''}),
        throwsA(isA<HttpHeaderError>().having((e) => e.headerName, 'headerName', 'Authorization')),
      );
    });

    test('the error names the header as the caller spelled it', () {
      expect(
        () => HttpHeaderSanitizer.sanitize(<String, String>{'X-Bad\nName': 'v'}),
        throwsA(
          isA<HttpHeaderError>()
              .having((e) => e.headerName, 'headerName', 'X-Bad\nName')
              .having((e) => e.toString(), 'toString', contains('cannot be sent')),
        ),
      );
    });

    test('one bad header fails the whole set', () {
      // A partial send is the silent failure this rule exists to prevent: the
      // request goes out missing exactly the header that authorizes it.
      expect(
        () => HttpHeaderSanitizer.sanitize(<String, String>{'X-Ok': 'value', 'X-Bad\r\nInjected': 'value'}),
        throwsA(isA<HttpHeaderError>()),
      );
    });
  });

  group('HttpHeaderSanitizer.ffmpegBlock', () {
    test('terminates every line, including the last', () {
      final block = HttpHeaderSanitizer.ffmpegBlock(<String, String>{'referer': 'https://example.com/'});

      expect(block, 'referer: https://example.com/\r\n');
    });

    test('nothing to send is an empty string, so -headers is omitted', () {
      expect(HttpHeaderSanitizer.ffmpegBlock(const <String, String>{}), isEmpty);
    });
  });

  group('HttpHeaderSanitizer.mpvFields', () {
    test('builds one Name: value line per header', () {
      expect(HttpHeaderSanitizer.mpvFields(<String, String>{'referer': 'https://e.example/'}), <String>[
        'referer: https://e.example/',
      ]);
      expect(HttpHeaderSanitizer.mpvFields(const <String, String>{}), isEmpty);
    });
  });
}
