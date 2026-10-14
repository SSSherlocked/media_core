import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_ingest/media_core_ingest.dart';

void main() {
  group('manifest child classification', () {
    test('bare names need the manifest base', () {
      final kind = classifyHlsManifest(
        '#EXTM3U\n#EXTINF:2.0,\nmedia.95.mp4\n#EXTINF:2.0,\nmedia.96.mp4\n#EXT-X-ENDLIST\n',
      );

      expect(kind.childCount, 2);
      expect(kind.relativeChildren, 2);
      expect(kind.requiresRewrite, isTrue);
      expect(kind.describe(), contains('relative=2'));
    });

    test('absolute paths need it as well', () {
      final kind = classifyHlsManifest('#EXTM3U\n#EXTINF:2.0,\n/tc.livehls/v1/streams/1/hls/1.0/media.95.mp4\n');

      expect(kind.absolutePathChildren, 1);
      expect(kind.requiresRewrite, isTrue);
    });

    test('absolute URLs do not', () {
      final kind = classifyHlsManifest(
        '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=800000\n'
        'https://cdn.example.com/live/media.m3u8\n',
      );

      expect(kind.absoluteChildren, 1);
      expect(kind.requiresRewrite, isFalse);
    });

    test('a relative key or map URI counts as a child', () {
      final kind = classifyHlsManifest(
        '#EXTM3U\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
        '#EXT-X-MAP:URI="init.mp4"\n'
        '#EXTINF:2.0,\n'
        'https://cdn.example.com/seg1.m4s\n',
      );

      expect(kind.childCount, 3);
      expect(kind.childrenNeedingBase, 2);
      expect(kind.requiresRewrite, isTrue);
    });

    test('an empty or comment-only body has nothing to rewrite', () {
      expect(classifyHlsManifest('').requiresRewrite, isFalse);
      expect(classifyHlsManifest('#EXTM3U\n#EXT-X-ENDLIST\n').childCount, 0);
    });

    test('a scheme-relative child needs the base too', () {
      final kind = classifyHlsManifest('#EXTM3U\n//cdn.example.com/seg1.ts\n');

      expect(kind.schemeRelativeChildren, 1);
      expect(kind.requiresRewrite, isTrue);
    });
  });
}
