import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_multiview/media_core_multiview.dart';

/// A pooled player the tests can drive.
final class _FakeHandle implements PoolPlayerHandle {
  _FakeHandle(this.id);

  @override
  final String id;

  final StreamController<PlayerTransportState> _states = StreamController<PlayerTransportState>.broadcast();

  String? openedSource;
  double volume = 1;
  bool muted = false;
  bool playing = false;
  bool paused = false;
  bool recycled = false;
  Object? openError;

  /// Held until the test completes it: a restart whose engine work outlives the
  /// watchdog interval is the overlap the sweep guard exists for.
  Completer<void>? openGate;

  @override
  bool isDisposed = false;

  @override
  Stream<PlayerTransportState> get playbackStream => _states.stream;

  /// Emits a position, which is what the stall watchdog watches.
  void emitPosition(Duration position) {
    _states.add(const PlayerTransportState.initial().copyWith(position: position));
  }

  @override
  Future<void> open(PlayerSource source, {bool autoPlay = false}) async {
    final error = openError;
    if (error != null) {
      // A test double replaying whatever the host configured, so the thrown
      // object's static type is intentionally `Object?`.
      // ignore: only_throw_errors
      throw error;
    }
    final gate = openGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    openedSource = source.id.value;
    playing = autoPlay;
    emitPosition(Duration.zero);
  }

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> pause() async {
    paused = true;
    playing = false;
  }

  @override
  Future<void> recycle() async => recycled = true;

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> setMute({required bool muted}) async => this.muted = muted;
}

final class _FakePlayerHost implements PoolPlayerHost {
  final List<_FakeHandle> handles = <_FakeHandle>[];
  int acquireCount = 0;
  int releaseCount = 0;
  int disposeCount = 0;

  /// Injected into every handle acquired from now on.
  ///
  /// Necessary because the pool hands out a fresh handle per acquire: setting
  /// the error on the handle in use would test the old player, not the restart.
  Object? nextOpenError;

  /// Same reason, for a restart that must still be in flight.
  Completer<void>? nextOpenGate;

  @override
  Future<PoolPlayerHandle> acquire() async {
    acquireCount++;
    final handle = _FakeHandle('player-$acquireCount')
      ..openError = nextOpenError
      ..openGate = nextOpenGate;
    handles.add(handle);
    return handle;
  }

  @override
  Future<void> release(PoolPlayerHandle handle) async => releaseCount++;

  @override
  Future<void> disposeHandle(PoolPlayerHandle handle) async => disposeCount++;
}

final PlayerSource _testSource = PlayerSource(
  id: SourceId('test'),
  uri: Uri.parse('https://example.com/test.m3u8'),
  protocol: SourceProtocol.https,
  format: SourceFormat.mpegTs,
);

PlayerSource _source(String id) => PlayerSource(
  id: SourceId(id),
  uri: Uri.parse('https://example.com/$id.m3u8'),
  protocol: SourceProtocol.https,
  format: SourceFormat.mpegTs,
);

MultiviewCellSource _room(String id, {bool live = true, String? title}) =>
    MultiviewCellSource(source: _source(id), roomId: id, title: title ?? id, isLive: live);

void main() {
  late _FakePlayerHost host;
  late MultiviewController wall;
  late DateTime now;

  setUp(() {
    host = _FakePlayerHost();
    now = DateTime(2026, 9, 26, 12);
    wall = MultiviewController(players: host, clock: () => now);
  });

  tearDown(() => wall.dispose());

  group('MultiviewController cells', () {
    test('starts with one empty cell per layout slot', () {
      expect(wall.cells.length, MultiviewLayout.quad.capacity);
      expect(wall.cells.every((cell) => cell.isEmpty), isTrue);
    });

    test('assigns a room, opens a player and reports it playing', () async {
      await wall.assign(
        0,
        MultiviewCellSource(source: _testSource, roomId: 'a', title: 'room a', qualityLabel: '720p'),
      );

      expect(wall.cells[0].status, MultiviewCellStatus.playing);
      expect(wall.cells[0].qualityLabel, '720p', reason: 'without a resolver the caller label is kept');
      expect(host.handles.single.openedSource, 'test');
      expect(wall.snapshot.playingCount, 1);
    });

    test('fills the wall from a list, capped by the configured maximum', () async {
      await wall.updateConfig(wall.config.copyWith(maxCells: 2));

      await wall.assignAll(<MultiviewCellSource>[_room('a'), _room('b'), _room('c')]);

      expect(wall.snapshot.assignedCount, 2);
      expect(wall.cells[2].isEmpty, isTrue);
    });

    test('a cell for an offline room needs no player', () async {
      await wall.assign(1, _room('off', live: false));

      expect(wall.cells[1].status, MultiviewCellStatus.offline);
      expect(wall.playerIdOf(1), isNull, reason: 'nothing to open, so nothing to fail');
    });

    test('clearing a cell gives its player back for reuse', () async {
      await wall.assign(0, _room('a'));

      await wall.clear(0);

      expect(host.releaseCount, 1, reason: 'the pool keeps it warm for the next room');
      expect(wall.cells[0].isEmpty, isTrue);
      expect(wall.snapshot.playingCount, 0);
    });

    test('an open failure is recorded on the cell', () async {
      await wall.assign(0, _room('a'));
      host.nextOpenError = StateError('backend refused');

      await expectLater(wall.restartCell(0), throwsA(isA<StateError>()));

      expect(wall.cells[0].failure?.kind, MultiviewCellFailureKind.startFailure);
      expect(wall.cells[0].status, MultiviewCellStatus.failed);
    });

    test('growing the layout adds empty cells and shrinking releases players', () async {
      await wall.assign(0, _room('a'));

      await wall.updateConfig(wall.config.copyWith(layout: MultiviewLayout.nine));

      expect(wall.cells.length, MultiviewLayout.nine.capacity);

      await wall.updateConfig(wall.config.copyWith(layout: MultiviewLayout.single));

      expect(wall.cells.length, 1);
      expect(host.releaseCount, greaterThanOrEqualTo(0));
    });

    test('a playlist cell advances to its next room', () async {
      final playlist = <MultiviewCellSource>[_room('a'), _room('b'), _room('c')];
      await wall.assign(0, playlist.first, playlist: playlist);

      expect(await wall.advanceCell(0), isTrue);
      expect(wall.cells[0].source?.roomId, 'b');

      await wall.advanceCell(0);
      await wall.advanceCell(0);

      expect(wall.cells[0].source?.roomId, 'a', reason: 'the playlist wraps');
    });

    test('advancing a cell without a playlist does nothing', () async {
      await wall.assign(0, _room('a'));

      expect(await wall.advanceCell(0), isFalse);
    });
  });

  group('MultiviewController audio focus', () {
    test('exactly one cell is audible, at the focused volume', () async {
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));

      await wall.setAudioFocus(1);

      final audible = host.handles.where((handle) => !handle.muted).toList();
      expect(audible.length, 1);
      expect(audible.single.volume, wall.config.focusedVolume);
      expect(wall.cells[1].hasAudioFocus, isTrue);
      expect(wall.cells[0].hasAudioFocus, isFalse);
    });

    test('switching focus silences the previous cell', () async {
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));
      await wall.setAudioFocus(0);

      await wall.setAudioFocus(1);

      expect(host.handles[0].muted, isTrue);
      expect(host.handles[1].muted, isFalse);
    });

    test('muting the wall keeps the audio focus so unmuting restores it', () async {
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));
      await wall.setAudioFocus(1);

      await wall.muteAll();

      expect(host.handles.every((handle) => handle.muted), isTrue);

      await wall.muteAll(muted: false);

      expect(wall.audioIndex, 1);
      expect(host.handles[1].muted, isFalse);
    });

    test('a background volume can be set instead of silence', () async {
      await wall.updateConfig(wall.config.copyWith(backgroundVolume: 0.2));
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));

      await wall.setAudioFocus(0);

      expect(host.handles[1].muted, isFalse);
      expect(host.handles[1].volume, 0.2);
    });

    test('muting the wall silences cells that carry their own volume', () async {
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));
      await wall.setAudioFocus(0);
      // What a host does when a cell starts: restore the room's own volume.
      await wall.setCellVolume(0, 0.8);
      await wall.setCellVolume(1, 0.6);

      await wall.muteAll();

      expect(host.handles.every((handle) => handle.muted), isTrue);
      expect(host.handles.every((handle) => handle.volume == 0.0), isTrue);

      await wall.muteAll(muted: false);

      expect(host.handles[0].muted, isFalse);
      expect(host.handles[0].volume, 0.8, reason: 'the audible cell keeps its own volume');
    });

    test('a per-cell volume does not keep a background cell audible', () async {
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));
      await wall.setCellVolume(1, 0.9);

      await wall.setAudioFocus(0);

      expect(host.handles[0].muted, isFalse);
      expect(host.handles[1].muted, isTrue, reason: 'exclusive mode still owns the background cell');
    });

    test('un-muting restores the mode that was in force', () async {
      await wall.updateConfig(wall.config.copyWith(audioMode: MultiviewAudioMode.mixed));
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));

      await wall.muteAll();
      await wall.muteAll(muted: false);

      expect(wall.config.audioMode, MultiviewAudioMode.mixed);
      expect(host.handles.every((handle) => handle.muted), isFalse);
    });
  });

  group('MultiviewController budget', () {
    test('critical pressure keeps only the focused cell playing', () async {
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));
      await wall.assign(2, _room('c'));
      await wall.setVideoFocus(0);

      await wall.reportPressure(ResourcePressure.critical);

      expect(wall.cells[0].isPlaying, isTrue);
      expect(wall.cells[1].isPlaying, isFalse);
      expect(wall.cells[2].isPlaying, isFalse);
      expect(wall.snapshot.budgetExceeded, isTrue);
    });

    test('pressure that clears restores nothing on its own', () async {
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));
      await wall.reportPressure(ResourcePressure.critical);
      expect(wall.cells[1].isPlaying, isFalse);

      await wall.reportPressure(ResourcePressure.none);

      expect(wall.snapshot.budgetExceeded, isFalse);
      expect(wall.cells[1].isPlaying, isFalse, reason: 'cells are restarted deliberately, not by a pressure dip');
    });

    test('refuseNewCells rejects an assignment past the cap', () async {
      await wall.updateConfig(wall.config.copyWith(maxCells: 1, budgetPolicy: MultiviewBudgetPolicy.refuseNewCells));
      await wall.assign(0, _room('a'));

      await expectLater(wall.assign(1, _room('b')), throwsA(isA<StateError>()));
    });

    test('letPlatformDrop leaves the wall alone', () async {
      await wall.updateConfig(wall.config.copyWith(budgetPolicy: MultiviewBudgetPolicy.letPlatformDrop));
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));

      await wall.reportPressure(ResourcePressure.emergency);

      expect(wall.cells[0].isPlaying, isTrue);
      expect(wall.cells[1].isPlaying, isTrue);
    });
  });

  group('MultiviewController stall watchdog', () {
    test('a stalled cell is restarted within its budget', () async {
      await wall.updateConfig(wall.config.copyWith(cellStallTimeout: const Duration(seconds: 5), cellMaxRestarts: 2));
      await wall.assign(0, _room('a'));
      final firstPlayer = wall.playerIdOf(0);

      // Time passes with no progress at all.
      now = now.add(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(wall.cells[0].restarts, greaterThanOrEqualTo(1));
      expect(wall.playerIdOf(0), isNot(firstPlayer), reason: 'a new player takes over the cell');
    });

    test('a restart slower than the tick does not stack a second sweep', () async {
      await wall.updateConfig(wall.config.copyWith(cellStallTimeout: const Duration(seconds: 5), cellMaxRestarts: 3));
      await wall.assign(0, _room('a'));

      // The restart's engine work outlives several watchdog ticks. Without the
      // sweep guard each later tick sees the same frozen cell, counts another
      // restart and issues another one - the wall tears itself down.
      host.nextOpenGate = Completer<void>();
      now = now.add(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(seconds: 7));

      expect(wall.cells[0].restarts, 1, reason: 'one stall, one restart attempt');
      expect(
        wall.cells[0].status,
        MultiviewCellStatus.starting,
        reason: 'the cell is mid-restart, not failed: the budget was not eaten by phantom sweeps',
      );

      host.nextOpenGate!.complete();
      host.nextOpenGate = null;
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(wall.cells[0].restarts, 1);
      expect(host.acquireCount, lessThanOrEqualTo(3), reason: 'no pile-up of replacement players');
    });

    test('a cell that keeps failing ends up failed instead of restarting forever', () async {
      await wall.updateConfig(wall.config.copyWith(cellStallTimeout: const Duration(seconds: 1), cellMaxRestarts: 1));
      await wall.assign(0, _room('a'));
      host.nextOpenError = StateError('gone');

      now = now.add(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(wall.cells[0].status, MultiviewCellStatus.failed);
      expect(wall.cells[0].failure?.kind, MultiviewCellFailureKind.stallFailure);
    });

    test('a failed cell with a playlist moves on', () async {
      await wall.updateConfig(wall.config.copyWith(cellStallTimeout: const Duration(seconds: 1), cellMaxRestarts: 0));
      final playlist = <MultiviewCellSource>[_room('a'), _room('b')];
      await wall.assign(0, playlist.first, playlist: playlist);

      now = now.add(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(wall.cells[0].source?.roomId, 'b', reason: 'a monitor moves to the next live room');
    });
  });

  group('MultiviewController patrol', () {
    test('rotates focus and audio to the next playing cell', () async {
      // An interval comfortably longer than the wait, so exactly one rotation
      // happens and the assertion cannot race a second one back to cell 0.
      await wall.updateConfig(wall.config.copyWith(patrolInterval: const Duration(milliseconds: 200)));
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));
      await wall.setVideoFocus(0);

      wall.startPatrol();
      await Future<void>.delayed(const Duration(milliseconds: 260));

      expect(wall.focusedIndex, isNot(0), reason: 'the patrol moved on');
      expect(wall.audioIndex, wall.focusedIndex, reason: 'a patrol listens to what it is showing');
      wall.stopPatrol();
    });

    test('skips offline cells', () async {
      await wall.updateConfig(wall.config.copyWith(patrolInterval: const Duration(milliseconds: 40)));
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('off', live: false));
      await wall.setVideoFocus(0);

      wall.startPatrol();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(wall.focusedIndex, 0, reason: 'only one playing cell is worth focusing');
      wall.stopPatrol();
    });
  });

  group('MultiviewController danmaku routing', () {
    test('only the focused cell is fed', () async {
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));
      final first = wall.ensureDanmakuFor(0);
      final second = wall.ensureDanmakuFor(1);

      await wall.setVideoFocus(0);

      expect(first.isEnabled, isTrue);
      expect(second.isEnabled, isFalse);
    });

    test('focus moving hands the feed over', () async {
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));
      final first = wall.ensureDanmakuFor(0);
      final second = wall.ensureDanmakuFor(1);
      await wall.setVideoFocus(0);

      await wall.setVideoFocus(1);

      expect(first.isEnabled, isFalse);
      expect(second.isEnabled, isTrue);
      expect(wall.focusedDanmaku, same(second));
    });

    test('a wall configured for danmaku everywhere keeps every cell fed', () async {
      await wall.updateConfig(wall.config.copyWith(danmakuOnlyOnFocused: false));
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));
      final first = wall.ensureDanmakuFor(0);
      final second = wall.ensureDanmakuFor(1);

      await wall.setVideoFocus(0);

      expect(first.isEnabled, isTrue);
      expect(second.isEnabled, isTrue);
    });
  });

  group('MultiviewController handover', () {
    test('hands a cell player to the host target', () async {
      await wall.assign(2, _room('c'));
      String? handed;

      final ok = await wall.handOverCell(2, (playerId) async => handed = playerId);

      expect(ok, isTrue);
      expect(handed, wall.playerIdOf(2));
      expect(wall.cells[2].isPlaying, isTrue, reason: 'the wall keeps the cell; the player moved surface');
    });

    test('an empty cell has nothing to hand over', () async {
      expect(await wall.handOverCell(0, (playerId) async {}), isFalse);
    });
  });

  group('MultiviewController quality policy', () {
    test('the focused cell asks for the best quality, the others for the lowest', () async {
      final asked = <String, MultiviewQualityPreference>{};
      final resolving = MultiviewController(
        players: host,
        clock: () => now,
        qualityResolver: (source, preference) async {
          asked[source.roomId ?? ''] = preference;
          return source;
        },
      );
      addTearDown(resolving.dispose);

      await resolving.assign(0, _room('a'));
      await resolving.assign(1, _room('b'));

      expect(asked['a'], MultiviewQualityPreference.best);
      expect(asked['b'], MultiviewQualityPreference.lowest);
    });

    test('a uniform wall asks for the best everywhere', () async {
      final asked = <String, MultiviewQualityPreference>{};
      final resolving = MultiviewController(
        players: host,
        clock: () => now,
        config: MultiviewConfig.defaults.copyWith(qualityPolicy: MultiviewQualityPolicy.uniform),
        qualityResolver: (source, preference) async {
          asked[source.roomId ?? ''] = preference;
          return source;
        },
      );
      addTearDown(resolving.dispose);

      await resolving.assign(0, _room('a'));
      await resolving.assign(1, _room('b'));

      expect(asked.values, everyElement(MultiviewQualityPreference.best));
    });
  });

  group('MultiviewController cell playerId', () {
    test('stamps the acquired player id onto the cell and clears it on release', () async {
      await wall.assign(0, _room('a'));

      expect(wall.cells[0].status, MultiviewCellStatus.playing);
      expect(wall.cells[0].playerId, isNotNull);
      expect(wall.cells[0].playerId, 'player-1');

      await wall.clear(0);

      expect(wall.cells[0].playerId, isNull);
    });
  });

  group('MultiviewController snapshot stream', () {
    test('broadcasts the starting -> playing transition for a cell', () async {
      final statuses = <MultiviewCellStatus>[];
      final sub = wall.onChanged.listen((snapshot) {
        statuses.add(snapshot.cells.first.status);
      });
      addTearDown(sub.cancel);

      await wall.assign(0, _room('a'));
      // Let the microtask-driven status stream drain before asserting.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(wall.cells.first.status, MultiviewCellStatus.playing);
      expect(statuses, containsAll([MultiviewCellStatus.starting, MultiviewCellStatus.playing]));
      // The playing event must be the LAST one: a host that mirrors the wall
      // on this stream ends up with the playing cell, not a stuck resolving.
      expect(statuses.last, MultiviewCellStatus.playing);
    });
  });

  group('MultiviewController lifecycle', () {
    test('dispose gives every player back and closes the stream', () async {
      await wall.assign(0, _room('a'));
      await wall.assign(1, _room('b'));

      await wall.dispose();

      expect(host.releaseCount, 2);
      await expectLater(
        Future<void>.delayed(Duration.zero),
        completes,
        reason: 'the snapshot stream closes without an error',
      );
    });

    test('a disposed wall refuses further work', () async {
      await wall.dispose();

      await expectLater(wall.assign(0, _room('a')), throwsA(isA<StateError>()));
    });
  });
}
