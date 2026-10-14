import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';

void main() {
  group('RecordingSource title', () {
    test('a title is part of the value', () {
      const titled = RecordingSource.network('https://e.com/live.flv', id: 'room-42', title: '主播8891');
      const untitled = RecordingSource.network('https://e.com/live.flv', id: 'room-42');

      expect(titled, isNot(untitled), reason: 'the title is what a recording is named after; it cannot be equal noise');
      expect(titled.hashCode, isNot(untitled.hashCode));
      expect(titled.title, '主播8891');
    });

    test('every factory carries it', () {
      expect(const RecordingSource.file('/a/b.ts', title: 'clip').title, 'clip');
      expect(const RecordingSource.network('https://e.com/a', title: 'live').title, 'live');
      expect(const RecordingSource.stream('s1', title: 'stream').title, 'stream');
      expect(const RecordingSource.custom('x://y', title: 'other').title, 'other');
    });

    test('hasTitle is about content, not presence', () {
      expect(const RecordingSource.network('https://e.com/a', title: '   ').hasTitle, isFalse);
      expect(const RecordingSource.network('https://e.com/a', title: '').hasTitle, isFalse);
      expect(const RecordingSource.network('https://e.com/a').hasTitle, isFalse);
      expect(const RecordingSource.network('https://e.com/a', title: ' 主播 ').hasTitle, isTrue);
    });

    test('a title is a label, not an identity', () {
      const left = RecordingSource.network('https://e.com/a.flv', id: 'room-1', title: '同一个名字');
      const right = RecordingSource.network('https://e.com/b.flv', id: 'room-2', title: '同一个名字');

      expect(
        left,
        isNot(right),
        reason: 'two rooms with the same displayed name are still two sources; id and value decide identity',
      );
    });
  });
}
