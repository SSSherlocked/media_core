import 'dart:async';
import 'package:media_core/playback/buffer_range.dart';
import 'package:media_core/playback/playback_buffer.dart' show PlaybackBuffer;
import 'package:media_core/playback/playback_command.dart';
import 'package:media_core/playback/playback_request.dart';
import 'package:media_core/playback/playback_snapshot.dart';
import 'package:media_core/playback/player_transport_state.dart';
import 'package:rxdart/rxdart.dart';

/// Controls playback lifecycle.
///
/// Responsibilities:
///
/// - own playback state
/// - receive playback commands
/// - update playback state
/// - expose snapshots
/// - serialize playback operations
///
/// Does not:
///
/// - decode media
/// - control backend player
/// - call platform APIs
/// - render video
final class PlaybackController {
  /// Creates a controller whose state starts at [initialState].
  ///
  /// The state stream is seeded rather than empty so a consumer that subscribes
  /// late — a controls bar built after playback began — still reads a complete
  /// transport state instead of waiting for the next engine report.
  PlaybackController({PlayerTransportState initialState = const PlayerTransportState.initial()})
    : _stateSubject = BehaviorSubject<PlayerTransportState>.seeded(initialState);

  final BehaviorSubject<PlayerTransportState> _stateSubject;

  bool _disposed = false;

  Future<void> _operation = Future<void>.value();

  /// Current state stream.
  ValueStream<PlayerTransportState> get state => _stateSubject.stream;

  /// Current state.
  PlayerTransportState get current => _stateSubject.value;

  /// Current snapshot.
  PlaybackSnapshot get snapshot => PlaybackSnapshot.fromState(current);

  /// Whether playing.
  bool get isPlaying => current.isPlaying;

  /// Whether paused.
  bool get isPaused => current.isPaused;

  /// Whether buffering.
  bool get isBuffering => current.isBuffering;

  /// Sends playback request.
  Future<void> request(PlaybackRequest request) {
    return _enqueue(() async {
      _ensureNotDisposed();

      apply(request.command);
    });
  }

  /// Applies playback command.
  void apply(PlaybackCommand command) {
    _ensureNotDisposed();

    final next = current.reduce(command);

    if (next != current) {
      _stateSubject.add(next);
    }
  }

  /// Play.
  Future<void> play() {
    return request(PlaybackRequest.play());
  }

  /// Pause.
  Future<void> pause() {
    return request(PlaybackRequest.pause());
  }

  /// Stop.
  Future<void> stop() {
    return request(PlaybackRequest.stop());
  }

  /// Seek.
  Future<void> seek(Duration position) {
    return request(PlaybackRequest.seek(position));
  }

  /// Update buffering state.
  void setBuffering({required bool buffering}) {
    apply(PlaybackCommand.buffering(value: buffering));
  }

  /// Update position.
  void updatePosition(Duration position) {
    apply(PlaybackCommand.position(position));
  }

  /// Update duration.
  void updateDuration(Duration duration) {
    apply(PlaybackCommand.duration(duration));
  }

  /// Update the buffered stretches the engine reported.
  ///
  /// Takes raw ranges rather than a [PlaybackBuffer] because the
  /// state layer canonicalizes exactly once on reduce; normalizing
  /// here too would create a second place where the two could
  /// disagree about what "the buffer" is.
  void updateBuffer(List<BufferRange> ranges) {
    apply(PlaybackCommand.buffered(ranges));
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _operation.then((_) => action());

    _operation = next.catchError((_) {});

    return next;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PlaybackController has already been disposed.');
    }
  }

  /// Dispose.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _operation;

    await _stateSubject.close();
  }
}
