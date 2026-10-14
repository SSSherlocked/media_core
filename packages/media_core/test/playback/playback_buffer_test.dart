import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/playback/buffer_range.dart';
import 'package:media_core/playback/playback_buffer.dart';

const _headTo10 = BufferRange(start: Duration.zero, end: Duration(seconds: 10));
const _from15To20 = BufferRange(start: Duration(seconds: 15), end: Duration(seconds: 20));

BufferRange _range(int startSeconds, int endSeconds) => BufferRange(
  start: Duration(seconds: startSeconds),
  end: Duration(seconds: endSeconds),
);

void main() {
  group('BufferRange', () {
    test('covers is end-exclusive', () {
      final range = _range(10, 20);

      expect(range.covers(const Duration(seconds: 10)), isTrue);
      expect(range.covers(const Duration(seconds: 20)), isFalse);
      expect(range.duration, const Duration(seconds: 10));
    });

    test('inverted ranges are empty', () {
      expect(_range(20, 10).isEmpty, isTrue);
      expect(_range(10, 10).isEmpty, isTrue);
      expect(_range(10, 10).covers(const Duration(seconds: 10)), isFalse);
    });

    test('adjacent ranges touch and unite across the seam', () {
      final a = _range(0, 10);
      final b = _range(10, 20);
      final gapped = _range(30, 40);

      expect(a.touches(b), isTrue);
      expect(a.touches(gapped), isFalse);
      expect(a.unite(b), _range(0, 20));
    });
  });

  group('PlaybackBuffer.normalize', () {
    test('merges overlapping and adjacent stretches and drops empties', () {
      final buffer = PlaybackBuffer(
        ranges: [_range(20, 30), _range(0, 10), _range(10, 20), _range(25, 26), _range(5, 5)],
      );

      final canonical = buffer.normalize();

      expect(canonical.ranges, const [BufferRange(start: Duration.zero, end: Duration(seconds: 30))]);
    });

    test('keeps real gaps as separate stretches', () {
      final buffer = PlaybackBuffer(ranges: [_range(0, 10), _range(15, 20)]);

      expect(buffer.normalize().ranges, const [_headTo10, _from15To20]);
    });

    test('an all-empty buffer normalizes to empty', () {
      expect(
        const PlaybackBuffer(
          ranges: [BufferRange(start: Duration(seconds: 3), end: Duration(seconds: 3))],
        ).normalize().ranges,
        isEmpty,
      );
    });
  });

  group('PlaybackBuffer reach', () {
    test('bufferedEndAt walks contiguous stretches from the position', () {
      final buffer = PlaybackBuffer(ranges: [_range(0, 10), _range(10, 20), _range(30, 40)]);

      expect(buffer.bufferedEndAt(Duration.zero), const Duration(seconds: 20));
      expect(buffer.bufferedEndAt(const Duration(seconds: 5)), const Duration(seconds: 20));
    });

    test('a gap stops the walk', () {
      final buffer = PlaybackBuffer(ranges: [_range(0, 10), _range(30, 40)]);

      expect(buffer.bufferedEndAt(Duration.zero), const Duration(seconds: 10));
    });

    test('nothing buffered at the position answers the position itself', () {
      final buffer = PlaybackBuffer(ranges: [_range(100, 200)]);

      expect(buffer.bufferedEndAt(const Duration(seconds: 5)), const Duration(seconds: 5));
    });

    test('covers checks any reported stretch', () {
      final buffer = PlaybackBuffer(ranges: [_range(0, 10), _range(15, 20)]);

      expect(buffer.covers(const Duration(seconds: 17)), isTrue);
      expect(buffer.covers(const Duration(seconds: 12)), isFalse);
    });

    test('bufferedDuration totals without double counting overlaps', () {
      final buffer = PlaybackBuffer(ranges: [_range(0, 10), _range(5, 15)]);

      expect(buffer.bufferedDuration, const Duration(seconds: 15));
    });
  });
}
