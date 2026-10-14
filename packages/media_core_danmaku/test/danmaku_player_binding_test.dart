import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_danmaku/media_core_danmaku.dart';
import 'package:rxdart/rxdart.dart';

/// Records what the binding asked the engine to do.
final class _RecordingEngine implements BarrageEngineApi {
  final calls = <String>[];
  final seeks = <Duration>[];
  double rate = 1;

  @override
  void pause() => calls.add('pause');

  @override
  void resume() => calls.add('resume');

  @override
  void clear() => calls.add('clear');

  @override
  void seekTo(Duration position) => seeks.add(position);

  @override
  void loadTimeline(List<BarrageItem> items) => calls.add('loadTimeline');

  @override
  double get playbackRate => rate;

  @override
  set playbackRate(double value) {
    rate = value;
    calls.add('rate=$value');
  }

  @override
  void pushMessage(BarrageItem item) => calls.add('push');

  @override
  int retractWhere(bool Function(BarrageItem item) predicate) => 0;

  @override
  void updateConfig(BarrageConfig config) {}

  @override
  bool triggerItemAt(double x, double y, {required bool longPress}) => false;

  @override
  BarrageItem? pauseItemAt(double x, double y) => null;

  @override
  void resumeAllPaused() {}

  @override
  int get pausedCount => 0;

  @override
  int get activeCacheSize => 0;

  @override
  int get activeCount => 0;

  @override
  int get rasterCacheBytes => 0;

  @override
  int get activePoolSize => 0;

  @override
  int get pendingMessageCount => 0;

  @override
  bool get rasterizationActive => false;
}

PlayerTransportState _state(PlaybackCommand command, {Duration position = Duration.zero, double rate = 1.0}) {
  return PlayerTransportState(
    command: command,
    position: position,
    duration: const Duration(minutes: 10),
    volume: 1,
    rate: rate,
    initialized: true,
    updatedAt: null,
  );
}

PlayerSource _source(String id) {
  return ProgressiveMediaSource(
    track: MediaTrack(uri: Uri.parse('https://example.com/$id.mp4'), kind: MediaTrackType.video),
  ).toPlayerSource();
}

void main() {
  group('DanmakuPlayerBinding', () {
    late _RecordingEngine engine;
    late BarrageController controller;
    late BehaviorSubject<PlayerTransportState> playback;
    late DanmakuPlayerBinding binding;

    setUp(() {
      engine = _RecordingEngine();
      controller = BarrageController()..attach(engine);
      playback = BehaviorSubject<PlayerTransportState>();
      binding = DanmakuPlayerBinding(controller: controller, playback: playback)..attach();
    });

    tearDown(() async {
      await binding.dispose();
      await playback.close();
    });

    test('play and pause move the engine with the player', () async {
      playback.add(_state(const PlaybackCommand.play()));
      await Future<void>.delayed(Duration.zero);
      playback.add(_state(const PlaybackCommand.pause()));
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls, ['resume', 'pause']);
    });

    test('a stop pauses rather than clearing', () async {
      // Clearing is the source change's job; a stop on the same source must
      // not throw away the comments of a video the user may resume.
      playback.add(_state(const PlaybackCommand.stop()));
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls, ['pause']);
    });

    test('buffering does not pause the comment clock', () async {
      playback.add(_state(const PlaybackCommand.buffering(value: true)));
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls, isEmpty);
    });

    test('a seek moves the timeline to the same position', () async {
      playback.add(_state(const PlaybackCommand.seek(Duration(seconds: 90)), position: const Duration(seconds: 90)));
      await Future<void>.delayed(Duration.zero);

      expect(engine.seeks, [const Duration(seconds: 90)]);
    });

    test('seek sync can be turned off', () async {
      await binding.detach();
      final detached = DanmakuPlayerBinding(controller: controller, playback: playback, syncSeek: false)..attach();
      addTearDown(detached.dispose);

      playback.add(_state(const PlaybackCommand.seek(Duration(seconds: 5))));
      await Future<void>.delayed(Duration.zero);

      expect(engine.seeks, isEmpty);
    });

    test('the playback rate is mirrored', () async {
      playback.add(_state(const PlaybackCommand.rate(2), rate: 2));
      await Future<void>.delayed(Duration.zero);

      expect(controller.playbackRate, 2.0);
    });

    test('a source change wipes the screen and resets the rate', () async {
      final sources = BehaviorSubject<PlayerSource?>();
      final bound = DanmakuPlayerBinding(controller: controller, playback: playback, sourceChanges: sources)..attach();
      addTearDown(bound.dispose);
      addTearDown(sources.close);

      playback.add(_state(const PlaybackCommand.rate(1.5), rate: 1.5));
      await Future<void>.delayed(Duration.zero);

      sources.add(_source('next'));
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls, contains('clear'));
      expect(controller.playbackRate, 1.0);
    });

    test('a hidden surface stays paused even when the player plays', () async {
      await binding.detach();
      final visible = BehaviorSubject<bool>.seeded(true);
      final bound = DanmakuPlayerBinding(controller: controller, playback: playback, visible: visible)..attach();
      addTearDown(bound.dispose);
      addTearDown(visible.close);

      visible.add(false);
      await Future<void>.delayed(Duration.zero);
      engine.calls.clear();

      playback.add(_state(const PlaybackCommand.play()));
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls, isEmpty, reason: 'nothing to show, nothing to pay for');

      visible.add(true);
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls, ['resume']);
    });

    test('detach stops the binding without touching the engine', () async {
      await binding.detach();
      engine.calls.clear();

      playback.add(_state(const PlaybackCommand.play()));
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls, isEmpty);
      // The controller is the host's to dispose, not the binding's.
      expect(controller.engine, isNotNull);
    });

    test('attach is idempotent', () async {
      binding
        ..attach()
        ..attach();

      playback.add(_state(const PlaybackCommand.play()));
      await Future<void>.delayed(Duration.zero);

      expect(engine.calls, ['resume']);
    });
  });
}
