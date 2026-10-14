import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/playback/buffer_range.dart';
import 'package:media_core/playback/playback_command.dart';
import 'package:media_core/playback/player_transport_state.dart';

void main() {
  group('PlayerTransportState buffered ranges', () {
    test('a buffered command produces a different state', () {
      const state = PlayerTransportState.initial();

      final next = state.reduce(
        const PlaybackCommandBuffered([BufferRange(start: Duration.zero, end: Duration(seconds: 10))]),
      );

      // The controller only emits when the reduced state differs from the
      // current one, so a `buffer` that is absent from props makes every
      // range report look like a no-op: the event never reaches listeners
      // and PlayerHandle.buffer stays empty on a backend that does report.
      expect(next, isNot(state));
      expect(next.buffer.ranges, hasLength(1));
      expect(next.buffer.bufferedEndAt(Duration.zero), const Duration(seconds: 10));
    });

    test('re-reporting the same ranges keeps the reported end', () {
      const ranges = [BufferRange(start: Duration.zero, end: Duration(seconds: 5))];

      final once = const PlayerTransportState.initial().reduce(const PlaybackCommandBuffered(ranges));
      final twice = once.reduce(const PlaybackCommandBuffered(ranges));

      expect(twice.buffer.ranges, once.buffer.ranges);
      expect(twice.buffer.bufferedEndAt(Duration.zero), const Duration(seconds: 5));
    });

    test('ranges arriving out of order are canonicalized on reduce', () {
      final state = const PlayerTransportState.initial().reduce(
        const PlaybackCommandBuffered([
          BufferRange(start: Duration(seconds: 10), end: Duration(seconds: 20)),
          BufferRange(start: Duration.zero, end: Duration(seconds: 5)),
        ]),
      );

      expect(state.buffer.ranges.first.start, Duration.zero);
      expect(state.buffer.bufferedEndAt(Duration.zero), const Duration(seconds: 5));
    });
  });
}
