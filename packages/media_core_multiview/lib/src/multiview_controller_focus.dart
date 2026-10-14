part of 'multiview_controller.dart';

/// The two attention channels — which cell is looked at and which is
/// listened to — plus the patrol that rotates them.
extension MultiviewControllerFocus on MultiviewController {
  // ---------------------------------------------------------------------------
  // Focus
  // ---------------------------------------------------------------------------

  /// Marks [index] as the cell being looked at.
  ///
  /// The focus decides which cell is rendered large, gets the danmaku and (with
  /// [MultiviewQualityPolicy.focusFirst]) the best quality.
  Future<void> setVideoFocus(int index) async {
    _ensureNotDisposed();
    _cellAt(index);
    if (_focusedIndex != index) {
      _log.debug(
        'video focus moved',
        fields: <String, Object?>{
          'from': _focusedIndex,
          'to': index,
          'roomId': _cells[index].source?.roomId,
          'qualityPolicy': _config.qualityPolicy.name,
          'danmakuOnlyOnFocused': _config.danmakuOnlyOnFocused,
        },
      );
    }
    _focusedIndex = index;
    await _applyQuality();
    _applyDanmakuRouting();
    _emit();
  }

  /// Marks [index] as the cell being listened to.
  Future<void> setAudioFocus(int index) async {
    _ensureNotDisposed();
    _cellAt(index);
    if (_audioIndex != index) {
      _log.debug(
        'audio focus moved',
        fields: <String, Object?>{'from': _audioIndex, 'to': index, 'audioMode': _config.audioMode.name},
      );
    }
    _audioIndex = index;
    await _applyAudio();
    _emit();
  }

  /// Silences the wall without losing the audio focus.
  ///
  /// Un-muting restores the mode that was in force before the wall was muted:
  /// a mixed wall stays mixed instead of silently becoming exclusive.
  Future<void> muteAll({bool muted = true}) async {
    _ensureNotDisposed();
    if (muted) {
      if (_config.audioMode != MultiviewAudioMode.muted) {
        _audioModeBeforeMute = _config.audioMode;
      }
      _config = _config.copyWith(audioMode: MultiviewAudioMode.muted);
    } else {
      final restore = _audioModeBeforeMute ?? MultiviewAudioMode.exclusive;
      _audioModeBeforeMute = null;
      _config = _config.copyWith(
        audioMode: restore == MultiviewAudioMode.muted ? MultiviewAudioMode.exclusive : restore,
      );
    }
    await _applyAudio();
    _emit();
  }

  /// Hands the player of [index] to [handOver].
  ///
  /// The wall keeps the cell: it is the same player, shown somewhere else. This
  /// is how a monitoring wall sends one camera to a small window without
  /// restarting the stream — the target is the host's `PipSessionController`
  /// (`pipSession.enter(PlayerId(playerId))`) or its floating equivalent.
  Future<bool> handOverCell(int index, Future<void> Function(String playerId) handOver) async {
    _ensureNotDisposed();
    final playerId = playerIdOf(index);
    if (playerId == null) {
      _log.debug('cell has no player to hand over', fields: <String, Object?>{'index': index});
      return false;
    }
    _log.info(
      'handing a cell over to another surface',
      fields: <String, Object?>{'index': index, 'playerId': playerId},
    );
    await handOver(playerId);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Patrol
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Patrol
  // ---------------------------------------------------------------------------

  /// Starts rotating the focus on the configured interval.
  void startPatrol() {
    _ensureNotDisposed();
    _config = _config.copyWith(patrolEnabled: true);
    _startPatrolIfConfigured();
    _emit();
  }

  /// Stops the patrol where it is.
  void stopPatrol() {
    _ensureNotDisposed();
    _patrol?.cancel();
    _patrol = null;
    _config = _config.copyWith(patrolEnabled: false);
    _emit();
  }

  void _startPatrolIfConfigured() {
    _patrol?.cancel();
    _patrol = null;
    if (!_config.patrolEnabled || _cells.length <= 1) {
      return;
    }
    _patrol = Timer.periodic(_config.patrolInterval, (_) => unawaited(_rotateFocus()));
  }

  /// Moves the focus to the next cell worth watching.
  Future<void> _rotateFocus() async {
    if (_disposed || _cells.length <= 1 || _rotating) {
      return;
    }
    _rotating = true;
    try {
      await _rotateFocusOnce();
    } finally {
      _rotating = false;
    }
  }

  Future<void> _rotateFocusOnce() async {
    for (var offset = 1; offset <= _cells.length; offset++) {
      final index = (_focusedIndex + offset) % _cells.length;
      final cell = _cells[index];
      if (cell.isEmpty) {
        continue;
      }
      if (_config.patrolSkipsOfflineCells && cell.status != MultiviewCellStatus.playing) {
        continue;
      }
      _log.debug('patrol moving the focus', fields: <String, Object?>{'from': _focusedIndex, 'to': index});
      await setVideoFocus(index);
      await setAudioFocus(index);
      return;
    }
  }
}
