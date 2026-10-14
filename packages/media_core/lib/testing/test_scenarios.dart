import 'package:media_core/adapter/player_adapter.dart';
import 'package:media_core/adapter/player_adapter_event.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/testing/fake_player_adapter.dart';
import 'package:media_core/testing/test_source_factory.dart';

/// Reusable playback scenarios executed against a [PlayerAdapter].
///
/// Scenarios assert the event sequences a compliant adapter
/// should emit. They are backend independent and can be reused
/// by concrete adapter test suites.
final class TestScenarios {
  const TestScenarios._();

  /// Opens [source], plays, pauses and stops.
  ///
  /// Verifies the event order and adapter state transitions.
  static Future<List<PlayerAdapterEvent>> playPauseStop(
    PlayerAdapter adapter, {
    PlayerSource Function()? source,
  }) async {
    final events = <PlayerAdapterEvent>[];
    final subscription = adapter.events.listen(events.add);
    final media = (source ?? TestSourceFactory.httpMp4)();

    await adapter.open(media);
    await adapter.play();
    await adapter.pause();
    await adapter.stop();

    await subscription.cancel();

    final types = events.map(_nameOf).toList(growable: false);

    if (!types.contains('opened')) {
      throw StateError('adapter did not emit opened event: $types');
    }

    if (!types.contains('playing')) {
      throw StateError('adapter did not emit playing event: $types');
    }

    if (!types.contains('paused')) {
      throw StateError('adapter did not emit paused event: $types');
    }

    if (!types.contains('stopped')) {
      throw StateError('adapter did not emit stopped event: $types');
    }

    return events;
  }

  /// Opens a fresh source and verifies volume and rate round trips.
  static Future<void> volumeAndRate(PlayerAdapter adapter, {double volume = 0.5, double rate = 1.5}) async {
    await adapter.open(TestSourceFactory.httpMp4());
    await adapter.setVolume(volume);
    await adapter.setRate(rate);

    if (adapter is FakePlayerAdapter) {
      if (adapter.volumes.last != volume) {
        throw StateError('adapter volume mismatch: ${adapter.volumes.last}');
      }

      if (adapter.rates.last != rate) {
        throw StateError('adapter rate mismatch: ${adapter.rates.last}');
      }
    }
  }

  /// Opens a fresh source, seeks, and completes.
  static Future<List<PlayerAdapterEvent>> seekAndComplete(
    PlayerAdapter adapter, {
    Duration target = const Duration(seconds: 30),
  }) async {
    final events = <PlayerAdapterEvent>[];
    final subscription = adapter.events.listen(events.add);

    await adapter.open(TestSourceFactory.httpMp4());
    await adapter.seek(target);
    await adapter.play();

    if (adapter is FakePlayerAdapter) {
      adapter
        ..updatePosition(const Duration(minutes: 3))
        ..emitCompleted();
    }

    await subscription.cancel();

    return events;
  }

  static String _nameOf(PlayerAdapterEvent event) {
    return event.map<String>(
      opened: (_) => 'opened',
      playing: (_) => 'playing',
      paused: (_) => 'paused',
      stopped: (_) => 'stopped',
      buffering: (_) => 'buffering',
      completed: (_) => 'completed',
      positionChanged: (_) => 'positionChanged',
      durationChanged: (_) => 'durationChanged',
      videoSizeChanged: (_) => 'videoSizeChanged',
      videoFrameProgress: (_) => 'videoFrameProgress',
      videoReconfigured: (_) => 'videoReconfigured',
      hwdecChanged: (_) => 'hwdecChanged',
      audioReconfigured: (_) => 'audioReconfigured',
      audioDeviceChanged: (_) => 'audioDeviceChanged',
      subtitleChanged: (_) => 'subtitleChanged',
      cacheChanged: (_) => 'cacheChanged',
      bufferedRangesChanged: (_) => 'bufferedRangesChanged',
      metadataChanged: (_) => 'metadataChanged',
      playlistChanged: (_) => 'playlistChanged',
      clientMessage: (_) => 'clientMessage',
      logMessage: (_) => 'logMessage',
      volumeChanged: (_) => 'volumeChanged',
      rateChanged: (_) => 'rateChanged',
      error: (_) => 'error',
    );
  }
}
