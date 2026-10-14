import 'dart:async';

import 'package:media_core/media_core.dart';
import 'package:media_core_danmaku/media_core_danmaku.dart';

import 'package:media_core_multiview/src/multiview_cell.dart';
import 'package:media_core_multiview/src/multiview_config.dart';
import 'package:media_core_multiview/src/multiview_snapshot.dart';

// The implementation of [MultiviewController] is split by concern across
// `part` files next to this one:
//
// - `multiview_controller_cells.dart`      assign / clear / restart + decode budget
// - `multiview_controller_focus.dart`      video focus, audio focus, patrol
// - `multiview_controller_internals.dart`  cell open/watch/recover, snapshots
//
// Value types live in `multiview_snapshot.dart`. Extensions are public so
// the callable surface of [MultiviewController] is unchanged.

part 'multiview_controller_cells.dart';
part 'multiview_controller_focus.dart';
part 'multiview_controller_internals.dart';

/// Decision trail for the wall.
///
/// A wall is where "why is that camera black" gets asked, and the answer is
/// spread across four mechanisms: the budget, the stall watchdog, the playlist
/// and the focus. Each one records its decisions under `multiview`, so a wall
/// that dropped a cell, restarted one, or never opened one says which.
final LogModule _log = MediaCoreLog.of(LogCategory.multiview);

/// Ledger of the wall.
///
/// A wall multiplies everything the player does by the cell count, including its
/// cost: this account is what answers "how much does this 3x3 grid hold?" and
/// what makes the decode budget auditable after the fact.
final MemoryAccount _memory = MediaCoreMemory.of(MemoryModule.multiview);

/// Runs a wall of live cells.
///
/// Responsibilities:
///
/// - own one player per cell, taken from the core's player host and given back
///   when the cell is cleared
/// - keep exactly one cell audible, and one focused
/// - hold the wall inside the device's decode budget, shrinking it under
///   resource pressure
/// - restart cells that stop making progress, within a bounded budget
/// - rotate the focus on a patrol interval
///
/// It does not:
///
/// - render the grid (the host does, from [snapshot])
/// - resolve room sources or quality ladders (the host supplies sources and may
///   supply a [MultiviewQualityResolver])
/// - own the page, the PiP window or the small window: a cell hands its player
///   over through [handOverCell], and the target is the host's
///
/// ## Why the audio owner is not the same thing as the focus
///
/// The focused cell is the one being *looked* at; the audible one is the one
/// being *listened* to. A monitoring wall usually wants both on the same cell,
/// but a viewer who pinned the audio to one room while looking around the wall
/// is a real use, so they are separate settings with separate setters.
///
/// ## Why the budget is enforced here
///
/// Every cell is a decoder. A wall that ignores that does not show more streams,
/// it shows several broken ones and starves the one the viewer cares about. The
/// core reports pressure ([ResourcePressure]); this controller turns it into a
/// decision ([MultiviewBudgetPolicy]) and reports the result in [snapshot], so
/// the host can show *why* cells went quiet instead of leaving them looking
/// broken.
final class MultiviewController {
  /// Creates a wall backed by [players], sized by [config], with an optional
  /// [qualityResolver] and a [clock] override for deterministic tests.
  MultiviewController({
    required PoolPlayerHost players,
    MultiviewConfig config = MultiviewConfig.defaults,
    this.qualityResolver,
    DateTime Function()? clock,
  }) : _players = players,
       _config = config,
       _clock = clock ?? DateTime.now {
    _cells = List<MultiviewCell>.generate(_config.layout.capacity, (index) => MultiviewCell(index: index));
    _startTicking();
  }

  /// This instance's key in the shared account: a module can have several
  /// live instances, and a report sums their contributions rather than
  /// keeping whichever reported last.
  late final String _memoryKey = memoryContributorKey(this);

  final PoolPlayerHost _players;

  /// Resolves quality ladders, when the host can. See [MultiviewQualityResolver].
  final MultiviewQualityResolver? qualityResolver;

  final DateTime Function() _clock;

  MultiviewConfig _config;
  late List<MultiviewCell> _cells;

  /// Cell index → the rest of its playlist, for cells that cycle.
  final Map<int, List<MultiviewCellSource>> _playlists = <int, List<MultiviewCellSource>>{};

  /// Cell index → its player handle.
  final Map<int, PoolPlayerHandle> _handles = <int, PoolPlayerHandle>{};

  /// Cell index → per-cell substreams.
  final Map<int, StreamSubscription<PlayerTransportState>> _progressSubscriptions =
      <int, StreamSubscription<PlayerTransportState>>{};

  /// Cell index → last observed playback position and when it changed.
  final Map<int, ({Duration position, DateTime at})> _progress = <int, ({Duration position, DateTime at})>{};

  /// Cell index → a host-set manual volume that overrides the audio-mode one.
  final Map<int, double> _cellVolumes = <int, double>{};

  final StreamController<MultiviewSnapshot> _snapshotController = StreamController<MultiviewSnapshot>.broadcast();

  Timer? _tick;
  Timer? _patrol;

  /// Whether a progress sweep is still running.
  ///
  /// The tick is a `Timer.periodic`, which does not wait for its async body: a
  /// cell restart that takes longer than the interval would otherwise start a
  /// second sweep over the same cells, double-count restart budgets and issue
  /// overlapping restarts - the wall's version of a retry storm.
  bool _sweeping = false;

  /// Whether a patrol rotation is still running; same reason as [_sweeping].
  bool _rotating = false;
  int _focusedIndex = 0;
  int? _audioIndex;

  /// Audio mode in force before [muteAll] silenced the wall, so un-muting can
  /// return to it instead of forcing exclusive mode.
  MultiviewAudioMode? _audioModeBeforeMute;
  ResourcePressure _pressure = ResourcePressure.none;
  bool _budgetExceeded = false;
  bool _disposed = false;

  /// How often the wall checks its cells.
  static const Duration _tickInterval = Duration(seconds: 2);

  /// Cells of the wall.
  List<MultiviewCell> get cells => List<MultiviewCell>.unmodifiable(_cells);

  /// Current configuration.
  MultiviewConfig get config => _config;

  /// Current snapshot.
  MultiviewSnapshot get snapshot => _buildSnapshot();

  /// Snapshot changes.
  Stream<MultiviewSnapshot> get onChanged => _snapshotController.stream;

  /// Cell the viewer is looking at.
  int get focusedIndex => _focusedIndex;

  /// Cell that is audible, or `null`.
  int? get audioIndex => _audioIndex;

  /// The focused cell's danmaku session.
  ///
  /// The host routes incoming messages here (through its `DanmakuSink`), and
  /// only here: a wall feeds danmaku to one cell, which is what makes
  /// [MultiviewConfig.danmakuOnlyOnFocused] a routing decision instead of a
  /// per-cell filter.
  DanmakuOverlaySession? get focusedDanmaku => _cells[_focusedIndex].danmaku;

  /// PlayerIdentity identity of [index], for a host that wants to render it.
  String? playerIdOf(int index) => _handles[index]?.id;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// Applies a new configuration.
  ///
  /// Growing the layout adds empty cells; shrinking it clears the cells that no
  /// longer exist, releasing their players. A config that lowers the audio or
  /// focus index moves those to a cell that still exists.
  Future<void> updateConfig(MultiviewConfig config) async {
    _ensureNotDisposed();
    final previousCapacity = _cells.length;
    _config = config;

    if (config.layout.capacity != previousCapacity) {
      _log.debug(
        'resizing the wall',
        fields: <String, Object?>{
          'from': previousCapacity,
          'to': config.layout.capacity,
          'layout': config.layout.name,
          'budget': config.effectiveMaxCells,
        },
      );
      _resizeCells(config.layout.capacity);
    }

    _focusedIndex = _focusedIndex.clamp(0, _cells.length - 1);
    if (_audioIndex != null && _audioIndex! >= _cells.length) {
      _audioIndex = _cells.isEmpty ? null : _cells.length - 1;
    }

    await _applyAudio();
    _applyDanmakuRouting();
    _startPatrolIfConfigured();
    _emit();
  }

  void _resizeCells(int capacity) {
    if (capacity < _cells.length) {
      final removed = _cells.sublist(capacity);
      _cells = _cells.sublist(0, capacity);
      for (final cell in removed) {
        unawaited(_releaseCell(cell.index));
      }
      return;
    }

    for (var index = _cells.length; index < capacity; index++) {
      _cells.add(MultiviewCell(index: index));
    }
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  /// Releases the wall: every cell's player goes back to the host.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _tick?.cancel();
    _tick = null;
    _patrol?.cancel();
    _patrol = null;

    _log.debug('releasing the wall', fields: <String, Object?>{'cells': _cells.length, 'playing': _playingCount});

    for (final index in _cells.map((cell) => cell.index).toList()) {
      await _releaseCell(index);
    }
    for (final cell in _cells) {
      await cell.danmaku?.dispose();
      cell.danmaku = null;
    }

    _memory.withdraw(_memoryKey);
    await DisposeUtils.close(_snapshotController);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('MultiviewController has been disposed.');
    }
  }
}
