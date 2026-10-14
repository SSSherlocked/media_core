import 'package:example/ui/demo_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemoLog collapses a repeating event', () {
    test('consecutive identical lines become one counted line', () {
      final log = DemoLog()
        ..add('adapter: PlayerPositionChanged')
        ..add('adapter: PlayerPositionChanged')
        ..add('adapter: PlayerPositionChanged');

      expect(log.lines, hasLength(1));
      expect(log.lines.single, endsWith('adapter: PlayerPositionChanged  ×3'));
    });

    test('a different line breaks the run', () {
      final log = DemoLog()
        ..add('adapter: PlayerPositionChanged')
        ..add('operation: open → done')
        ..add('adapter: PlayerPositionChanged');

      expect(log.lines, hasLength(3));
      expect(log.lines.first, contains('PlayerPositionChanged'));
      expect(log.lines.first, isNot(contains('×')));
      expect(log.lines[1], contains('open'));
    });

    test('a ticker flood cannot push the records out of the window', () {
      final log = DemoLog(maxLines: 50)..add('operation: open → done');

      for (var i = 0; i < 500; i++) {
        log.add('adapter: PlayerPositionChanged');
      }

      // Before the collapse these 500 lines evicted everything the panel is
      // there to show.
      expect(log.lines, hasLength(2));
      expect(log.lines.last, contains('operation: open → done'));
      expect(log.lines.first, endsWith('adapter: PlayerPositionChanged  ×500'));
    });

    test('distinct lines still age out at maxLines', () {
      final log = DemoLog(maxLines: 3);

      for (var i = 0; i < 10; i++) {
        log.add('event $i');
      }

      expect(log.lines, hasLength(3));
      expect(log.lines.first, contains('event 9'));
    });

    test('clear empties it and notifies', () {
      final log = DemoLog();
      var notifications = 0;

      log
        ..addListener(() => notifications++)
        ..add('a')
        ..clear();

      expect(log.isEmpty, isTrue);
      expect(notifications, 2);
    });
  });
}
