import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_media_kit/src/position_throttle.dart';

void main() {
  group('PositionThrottle', () {
    test('the first tick of a stream is delivered immediately', () {
      fakeAsync((async) {
        final emitted = <Duration>[];
        final throttle = PositionThrottle();
        addTearDown(throttle.dispose);

        throttle.report(const Duration(seconds: 4), emitted.add);

        expect(emitted, <Duration>[const Duration(seconds: 4)]);
      });
    });

    test('a frame-rate stream is reduced to the UI cadence, not forwarded per frame', () {
      fakeAsync((async) {
        final emitted = <Duration>[];
        final throttle = PositionThrottle();
        addTearDown(throttle.dispose);

        // 60 fps for one second: 60 engine ticks.
        throttle.report(Duration.zero, emitted.add);
        for (var frame = 1; frame < 60; frame++) {
          async.elapse(const Duration(milliseconds: 16));
          throttle.report(Duration(milliseconds: frame * 16), emitted.add);
        }
        async.elapse(const Duration(milliseconds: 300));

        expect(
          emitted.length,
          lessThanOrEqualTo(7),
          reason: 'a 250 ms gap allows ~5 emissions a second; 60 would be the unthrottled path',
        );
        expect(emitted.first, Duration.zero);
      });
    });

    test('the newest value of a gap is still delivered when the stream stops ticking', () {
      fakeAsync((async) {
        final emitted = <Duration>[];
        final throttle = PositionThrottle();
        addTearDown(throttle.dispose);

        throttle.report(const Duration(seconds: 1), emitted.add);
        // The engine reports one more frame and then goes quiet (paused/stalled).
        async.elapse(const Duration(milliseconds: 100));
        throttle.report(const Duration(milliseconds: 1100), emitted.add);
        expect(emitted, <Duration>[const Duration(seconds: 1)], reason: 'inside the gap: held back');

        async.elapse(const Duration(milliseconds: 200));

        expect(emitted, <Duration>[
          const Duration(seconds: 1),
          const Duration(milliseconds: 1100),
        ], reason: 'the owed value is flushed when the gap closes, so the bar ends where the video did');
      });
    });

    test('a seek jumps the gap instead of waiting a quarter second', () {
      fakeAsync((async) {
        final emitted = <Duration>[];
        final throttle = PositionThrottle();
        addTearDown(throttle.dispose);

        throttle.report(const Duration(seconds: 10), emitted.add);
        async.elapse(const Duration(milliseconds: 50));
        throttle.report(const Duration(seconds: 40), emitted.add); // dragged forward

        expect(emitted, <Duration>[const Duration(seconds: 10), const Duration(seconds: 40)]);
      });
    });

    test('a loop restart (backwards jump) is delivered at once too', () {
      fakeAsync((async) {
        final emitted = <Duration>[];
        final throttle = PositionThrottle();
        addTearDown(throttle.dispose);

        throttle.report(const Duration(minutes: 1), emitted.add);
        async.elapse(const Duration(milliseconds: 50));
        throttle.report(Duration.zero, emitted.add);

        expect(emitted.last, Duration.zero);
      });
    });

    test('reset drops what the gap owed and re-opens the leading edge', () {
      fakeAsync((async) {
        final emitted = <Duration>[];
        final throttle = PositionThrottle();
        addTearDown(throttle.dispose);

        throttle.report(const Duration(seconds: 9), emitted.add);
        async.elapse(const Duration(milliseconds: 100));
        throttle
          ..report(const Duration(milliseconds: 9100), emitted.add)
          ..reset(); // a new source opened
        async.elapse(const Duration(milliseconds: 300));
        expect(emitted, <Duration>[const Duration(seconds: 9)], reason: 'the stale value was discarded');

        throttle.report(const Duration(milliseconds: 300), emitted.add);
        expect(emitted.last, const Duration(milliseconds: 300), reason: 'first tick of the new source lands now');
      });
    });

    test('dispose cancels the pending flush', () {
      fakeAsync((async) {
        final emitted = <Duration>[];
        final throttle = PositionThrottle()..report(const Duration(seconds: 1), emitted.add);
        async.elapse(const Duration(milliseconds: 100));
        throttle
          ..report(const Duration(milliseconds: 1100), emitted.add)
          ..dispose();

        async.elapse(const Duration(seconds: 2));
        expect(emitted, <Duration>[const Duration(seconds: 1)]);
      });
    });
  });
}
