import 'package:media_core_audio/src/player/audio_playback_controller.dart' show AudioPlaybackController;
import 'package:media_core_audio/src/queue/play_mode.dart';
import 'package:media_core_audio/src/track/music_track.dart';

/// The play list: ordered tracks, a cursor, and the shuffled order when
/// [PlayMode.random] is active.
///
/// This is a model, not a service — it holds no streams and performs no I/O,
/// which keeps "what should play next" a pure function of the queue state.
/// [AudioPlaybackController] owns one instance and publishes a snapshot after
/// every mutation.
///
/// Random playback materializes a permutation instead of rolling dice per
/// track. Two things fall out of that:
///
/// - no track repeats until the permutation is exhausted (lx-music behaves the
///   same way), and
/// - "previous" retraces what was actually played, which a per-step random
///   draw cannot do.
final class PlayQueue {
  /// Creates a queue.
  ///
  /// [index] is clamped into range; an empty queue sits at `-1`.
  PlayQueue({Iterable<MusicTrack> tracks = const <MusicTrack>[], PlayMode mode = PlayMode.list, int index = 0})
    : _tracks = List<MusicTrack>.of(tracks),
      _mode = mode {
    _index = _tracks.isEmpty ? -1 : index.clamp(0, _tracks.length - 1);

    if (_mode.shuffled) {
      _rebuildShuffleOrder();
    }
  }

  final List<MusicTrack> _tracks;

  PlayMode _mode;
  int _index = -1;
  int _shuffleCursor = -1;
  final List<int> _shuffleOrder = <int>[];

  /// Tracks in list order.
  List<MusicTrack> get tracks => List<MusicTrack>.unmodifiable(_tracks);

  /// Number of tracks.
  int get length => _tracks.length;

  /// Whether the queue is empty.
  bool get isEmpty => _tracks.isEmpty;

  /// Cursor into [tracks], `-1` when empty.
  int get index => _index;

  /// The current track, if any.
  MusicTrack? get current => _index >= 0 && _index < _tracks.length ? _tracks[_index] : null;

  /// Current play mode.
  PlayMode get mode => _mode;

  /// The shuffled order as track indices, empty when not shuffled.
  List<int> get shuffleOrder => List<int>.unmodifiable(_shuffleOrder);

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Switches mode, rebuilding the shuffled order when randomness starts.
  ///
  /// The current track is placed at the head of the new permutation so
  /// enabling random never immediately re-picks it.
  void setMode(PlayMode mode) {
    if (_mode == mode) {
      return;
    }

    final wasShuffled = _mode.shuffled;
    _mode = mode;

    if (mode.shuffled && !wasShuffled) {
      _rebuildShuffleOrder();
    } else if (!mode.shuffled) {
      _shuffleOrder.clear();
      _shuffleCursor = -1;
    }
  }

  /// Replaces the whole list and moves the cursor to [startIndex].
  void setTracks(Iterable<MusicTrack> tracks, {int startIndex = 0}) {
    _tracks
      ..clear()
      ..addAll(tracks);

    _index = _tracks.isEmpty ? -1 : startIndex.clamp(0, _tracks.length - 1);

    if (_mode.shuffled) {
      _rebuildShuffleOrder();
    } else {
      _shuffleOrder.clear();
      _shuffleCursor = -1;
    }
  }

  /// Appends [track]; returns its index.
  int append(MusicTrack track) {
    _tracks.add(track);
    _syncShuffleAfterInsert(_tracks.length - 1);

    if (_index < 0) {
      _index = 0;
    }

    return _tracks.length - 1;
  }

  /// Appends [tracks]; returns the index of the first appended one.
  int appendAll(Iterable<MusicTrack> tracks) {
    final first = _tracks.length;

    tracks.forEach(append);

    return first;
  }

  /// Inserts [track] right after the current one ("play next").
  ///
  /// With no current track it behaves like [append].
  int insertNext(MusicTrack track) {
    if (_index < 0) {
      return append(track);
    }

    return insertAt(_index + 1, track);
  }

  /// Inserts [track] at [at]; returns the inserted index.
  int insertAt(int at, MusicTrack track) {
    final position = at.clamp(0, _tracks.length);

    _tracks.insert(position, track);

    if (position <= _index) {
      _index++;
    }

    _syncShuffleAfterInsert(position);

    return position;
  }

  /// Removes the track at [at]; returns it.
  ///
  /// The cursor follows the list: removing a track above it shifts it up,
  /// removing the current track leaves the cursor on the next one (and steps
  /// back at the end of the list), so playback continues where the user
  /// expects.
  MusicTrack? removeAt(int at) {
    if (at < 0 || at >= _tracks.length) {
      return null;
    }

    final removed = _tracks.removeAt(at);

    _shuffleOrder.remove(at);
    _shuffleOrder.removeWhere((index) => index == at);
    for (var i = 0; i < _shuffleOrder.length; i++) {
      if (_shuffleOrder[i] > at) {
        _shuffleOrder[i] = _shuffleOrder[i] - 1;
      }
    }

    if (_tracks.isEmpty) {
      _index = -1;
      _shuffleCursor = -1;
    } else if (at < _index) {
      _index--;
    } else if (at == _index && _index >= _tracks.length) {
      _index = _tracks.length - 1;
    }

    _shuffleCursor = _shuffleOrder.indexOf(_index);

    return removed;
  }

  /// Removes every track.
  void clear() {
    _tracks.clear();
    _shuffleOrder.clear();
    _index = -1;
    _shuffleCursor = -1;
  }

  /// Moves a track inside the list.
  void move(int from, int to) {
    if (from < 0 || from >= _tracks.length) {
      return;
    }

    final target = to.clamp(0, _tracks.length - 1);
    final track = _tracks.removeAt(from);

    _tracks.insert(target, track);

    final playing = current;
    _index = playing == null ? -1 : _tracks.indexOf(playing);

    if (_mode.shuffled) {
      _rebuildShuffleOrder();
    }
  }

  /// Moves the cursor to [at].
  void jumpTo(int at) {
    if (at < 0 || at >= _tracks.length) {
      return;
    }

    _index = at;
    _shuffleCursor = _shuffleOrder.indexOf(at);
  }

  /// Index of the first track equal to [track] (identity is `(sourceId, id)`).
  int indexOfTrack(MusicTrack track) => _tracks.indexOf(track);

  // ---------------------------------------------------------------------------
  // Advancement
  // ---------------------------------------------------------------------------

  /// The index that should play after the current one.
  ///
  /// [automatic] distinguishes "the track ended" from "the user pressed next":
  /// single-loop only repeats on the former, and a user pressing next on the
  /// last track of a [PlayMode.list] queue is exactly the case that must not
  /// silently wrap.
  ///
  /// Returns null when playback should stop.
  int? indexAfter({required bool automatic}) {
    if (_tracks.isEmpty) {
      return null;
    }

    if (automatic && _mode.repeatsCurrent) {
      return _index;
    }

    if (_mode.shuffled) {
      return _shuffledNextIndex(wrap: _mode.wraps);
    }

    final next = _index + 1;

    if (next < _tracks.length) {
      return next;
    }

    if (_mode.wraps || !automatic) {
      return 0;
    }

    return null;
  }

  /// The index a "previous" command should move to.
  ///
  /// Null means "there is nothing before the current track"; the controller
  /// then restarts the current one instead of guessing, which is what the
  /// playback position is for.
  int? indexBefore() {
    if (_tracks.isEmpty) {
      return null;
    }

    if (_mode.shuffled) {
      if (_shuffleCursor > 0) {
        return _shuffleOrder[_shuffleCursor - 1];
      }

      return null;
    }

    if (_index > 0) {
      return _index - 1;
    }

    return null;
  }

  /// Walks the shuffled order, rebuilding it when it runs out.
  int? _shuffledNextIndex({required bool wrap}) {
    if (_shuffleOrder.isEmpty) {
      _rebuildShuffleOrder();
    }

    if (_shuffleCursor < 0) {
      _shuffleCursor = _shuffleOrder.indexOf(_index);
    }

    final next = _shuffleCursor + 1;

    if (next < _shuffleOrder.length) {
      return _shuffleOrder[next];
    }

    if (!wrap) {
      return null;
    }

    // A fresh permutation for the next pass, with the current track kept out
    // of the first slot so the pass boundary is audible as a change.
    final played = _index;
    _rebuildShuffleOrder(excludeFirst: played);

    return _shuffleOrder.isEmpty ? null : _shuffleOrder.first;
  }

  /// Builds a permutation of the track indices.
  void _rebuildShuffleOrder({int? excludeFirst}) {
    final indices = List<int>.generate(_tracks.length, (index) => index)..shuffle();

    if (_index >= 0 && indices.isNotEmpty) {
      indices
        ..remove(_index)
        ..insert(0, _index);
    }

    if (excludeFirst != null && indices.length > 1 && indices.first == excludeFirst) {
      final swap = indices.removeAt(0);

      indices.add(swap);
    }

    _shuffleOrder
      ..clear()
      ..addAll(indices);

    _shuffleCursor = _shuffleOrder.indexOf(_index);
  }

  /// Keeps the shuffled order consistent after an insertion.
  void _syncShuffleAfterInsert(int at) {
    if (!_mode.shuffled) {
      return;
    }

    for (var i = 0; i < _shuffleOrder.length; i++) {
      if (_shuffleOrder[i] >= at) {
        _shuffleOrder[i] = _shuffleOrder[i] + 1;
      }
    }

    _shuffleOrder.insert((_shuffleCursor < 0 ? 0 : _shuffleCursor + 1).clamp(0, _shuffleOrder.length), at);

    _shuffleCursor = _shuffleOrder.indexOf(_index);
  }

  @override
  String toString() => 'PlayQueue(${_tracks.length} tracks, index: $_index, mode: ${_mode.name})';
}
