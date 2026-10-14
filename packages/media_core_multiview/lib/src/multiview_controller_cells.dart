part of 'multiview_controller.dart';

/// Assigning rooms to cells, the decode budget that keeps the wall
/// inside the device's limits, and per-cell danmaku sessions.
extension MultiviewControllerCells on MultiviewController {
  // ---------------------------------------------------------------------------
  // Cells
  // ---------------------------------------------------------------------------

  /// Assigns [source] to [index] and starts it.
  Future<void> assign(int index, MultiviewCellSource source, {List<MultiviewCellSource>? playlist}) async {
    _ensureNotDisposed();
    final cell = _cellAt(index);

    if (_config.budgetPolicy == MultiviewBudgetPolicy.refuseNewCells && _isAtBudget && cell.isEmpty) {
      _log.warning(
        'refusing a new cell: at the decode budget',
        fields: <String, Object?>{
          'index': index,
          'roomId': source.roomId,
          'playing': _playingCount,
          'budget': _config.effectiveMaxCells,
        },
      );
      throw StateError(
        'The wall is at its decode budget (${_config.effectiveMaxCells} cells); '
        'refusing to add another under MultiviewBudgetPolicy.refuseNewCells.',
      );
    }

    _log.info(
      'assigning a cell',
      fields: <String, Object?>{
        'index': index,
        'roomId': source.roomId,
        'uri': source.source.uri,
        'isLive': source.isLive,
        'playlistSize': playlist?.length,
      },
    );

    if (playlist != null && playlist.length > 1) {
      _playlists[index] = List<MultiviewCellSource>.unmodifiable(playlist);
    } else {
      _playlists.remove(index);
    }

    cell
      ..source = source
      ..failure = null
      ..restarts = 0;
    await _openCell(cell);
    await _applyAudio();
    _emit();
  }

  /// Fills the wall from [sources], one per cell, in order.
  Future<void> assignAll(List<MultiviewCellSource> sources) async {
    _ensureNotDisposed();
    final limit = sources.length < _config.effectiveMaxCells ? sources.length : _config.effectiveMaxCells;
    for (var index = 0; index < limit; index++) {
      await assign(index, sources[index]);
    }
  }

  /// Advances [index] to the next source in its playlist, if it has one.
  ///
  /// A failed or ended cell with a playlist moves on instead of retrying the
  /// same dead room — which is what makes a wall usable as a monitor: the list
  /// keeps cycling through the rooms that are live.
  Future<bool> advanceCell(int index) async {
    _ensureNotDisposed();
    final playlist = _playlists[index];
    final current = _cells[index].source;
    if (playlist == null || playlist.isEmpty || current == null) {
      return false;
    }

    final position = playlist.indexWhere((candidate) => candidate.roomId == current.roomId);
    final next = playlist[(position + 1) % playlist.length];
    _log.debug(
      'advancing to the next room in the playlist',
      fields: <String, Object?>{
        'index': index,
        'from': current.roomId,
        'to': next.roomId,
        'playlistSize': playlist.length,
      },
    );
    await assign(index, next, playlist: playlist);
    return true;
  }

  /// Clears [index]: stops it and gives its player back.
  Future<void> clear(int index) async {
    _ensureNotDisposed();
    _cells[index]
      ..source = null
      ..qualityLabel = null
      ..failure = null
      ..restarts = 0
      ..status = MultiviewCellStatus.empty;
    _playlists.remove(index);
    await _releaseCell(index);
    _emit();
  }

  /// Clears every cell.
  Future<void> clearAll() async {
    _ensureNotDisposed();
    for (var index = 0; index < _cells.length; index++) {
      await clear(index);
    }
    _audioIndex = null;
    _emit();
  }

  /// Starts [index] again from its current source.
  Future<void> restartCell(int index) async {
    _ensureNotDisposed();
    final cell = _cells[index];
    if (cell.source == null) {
      return;
    }
    await _releaseCell(index);
    await _openCell(cell);
    _emit();
  }

  /// Stops [index] but keeps its room assigned.
  Future<void> stopCell(int index) async {
    _ensureNotDisposed();
    final handle = _handles[index];
    if (handle != null) {
      await handle.pause();
    }
    _cells[index].status = MultiviewCellStatus.empty;
    _emit();
  }

  /// Pauses [index]; the stall watchdog skips paused cells.
  Future<void> pauseCell(int index) async {
    _ensureNotDisposed();
    final handle = _handles[index];
    final cell = _cellAt(index);
    if (handle == null || !cell.isPlaying) {
      return;
    }
    await handle.pause();
    cell.status = MultiviewCellStatus.paused;
    _emit();
  }

  /// Resumes a [MultiviewCellStatus.paused] cell and restarts its stall clock.
  Future<void> resumeCell(int index) async {
    _ensureNotDisposed();
    final handle = _handles[index];
    final cell = _cellAt(index);
    if (handle == null || !cell.isPaused) {
      return;
    }
    _progress[index] = (position: _progress[index]?.position ?? Duration.zero, at: _clock());
    await handle.play();
    cell.status = MultiviewCellStatus.playing;
    await _applyAudio();
    _emit();
  }

  /// Overrides the audio-mode volume of [index].
  ///
  /// The override survives focus changes and audio re-application until the
  /// cell is cleared or [clearCellVolume] removes it.
  Future<void> setCellVolume(int index, double volume) async {
    _ensureNotDisposed();
    final cell = _cellAt(index);
    if (cell.isEmpty) {
      return;
    }
    _cellVolumes[index] = volume.clamp(0.0, 1.0);
    final handle = _handles[index];
    if (handle != null) {
      await handle.setVolume(volume.clamp(0.0, 1.0));
      await handle.setMute(muted: volume <= 0);
    }
    await _applyAudio();
    _emit();
  }

  /// Removes the manual volume of [index]; the audio mode decides again.
  Future<void> clearCellVolume(int index) async {
    _ensureNotDisposed();
    if (_cellVolumes.remove(index) == null) {
      return;
    }
    await _applyAudio();
    _emit();
  }

  // ---------------------------------------------------------------------------
  // Budget
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Budget
  // ---------------------------------------------------------------------------

  /// Reports device pressure.
  ///
  /// Applied immediately rather than at the next tick: a device in trouble does
  /// not wait two seconds for the wall to notice.
  Future<void> reportPressure(ResourcePressure pressure) async {
    _ensureNotDisposed();
    _pressure = pressure;
    _log.debug(
      'device pressure reported',
      fields: <String, Object?>{
        'hasPressure': pressure.hasPressure,
        'stopPreload': pressure.shouldStopPreload,
        'releaseResources': pressure.shouldReleaseResources,
      },
    );
    await _applyBudget();
    _emit();
  }

  Future<void> _applyBudget() async {
    final crowded = _playingCount > _config.effectiveMaxCells || _pressure.hasPressure;
    _budgetExceeded = crowded;
    if (!crowded) {
      return;
    }

    switch (_config.budgetPolicy) {
      case MultiviewBudgetPolicy.keepFocusedOnly:
        final severe = _pressure.shouldStopPreload || _pressure.shouldReleaseResources;
        if (!severe && _playingCount <= _config.effectiveMaxCells) {
          return;
        }
        _log.warning(
          'over budget: pausing every cell but the focused one',
          fields: <String, Object?>{'playing': _playingCount, 'budget': _config.effectiveMaxCells, 'severe': severe},
        );
        for (final cell in _cells) {
          if (cell.index == _focusedIndex || !cell.isPlaying) {
            continue;
          }
          await _handles[cell.index]?.pause();
          cell.status = MultiviewCellStatus.empty;
        }
      case MultiviewBudgetPolicy.letPlatformDrop:
      case MultiviewBudgetPolicy.refuseNewCells:
        _log.debug(
          'over budget, policy leaves the cells alone',
          fields: <String, Object?>{'policy': _config.budgetPolicy.name, 'playing': _playingCount},
        );
        return;
    }
  }

  bool get _isAtBudget => _playingCount >= _config.effectiveMaxCells;

  int get _playingCount => _cells.where((cell) => cell.isPlaying).length;

  // ---------------------------------------------------------------------------
  // Danmaku sessions
  // ---------------------------------------------------------------------------

  /// Creates the focused cell's danmaku session on demand.
  ///
  /// Lazily, because most walls never use it and a session per cell that is
  /// never fed is a queue nobody reads.
  DanmakuOverlaySession ensureDanmakuFor(int index) {
    _ensureNotDisposed();
    final cell = _cellAt(index);
    final existing = cell.danmaku;
    if (existing != null) {
      return existing;
    }
    final session = DanmakuOverlaySession();
    cell.danmaku = session;
    return session;
  }
}
