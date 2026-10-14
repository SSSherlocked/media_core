import 'dart:async';

import 'package:media_core/media_core.dart';

/// A pooled player that exists only in memory.
///
/// The pool, the wall and the list are all built on [PoolPlayerHandle], and the
/// interesting behaviour — which item is active, which are warm, what gets
/// reused, what gets released — has nothing to do with a real decoder. Driving
/// them with this fake is what makes those demos runnable anywhere: no network,
/// no backend, no device, and the same result every time.
///
/// A fake player also advances its own position, because the wall's stall
/// watchdog judges liveness by progress: a handle that never moves would be
/// declared stalled and restarted forever, which is correct behaviour but not
/// what a demo should spend its time showing.
final class FakePoolPlayerHandle implements PoolPlayerHandle {
  /// Creates a fake player handle.
  new({
    required this.id,
    this.openDelay = const Duration(milliseconds: 60),
    this.tick = const Duration(milliseconds: 250),
    this.failuresBeforeSuccess = 0,
  });

  @override
  final String id;

  /// How long [open] takes to complete.
  final Duration openDelay;

  /// How often the position advances while playing.
  final Duration tick;

  /// How many [open] calls fail before one succeeds.
  ///
  /// The wall's restart budget and the list's playlist advance are both about
  /// failure, so a fake that cannot fail cannot demonstrate them.
  int failuresBeforeSuccess;

  final StreamController<PlayerTransportState> _playback = StreamController<PlayerTransportState>.broadcast();

  Timer? _ticker;
  PlayerSource? _source;
  Duration _position = Duration.zero;
  PlaybackCommand _command = const PlaybackCommand.stop();
  double _volume = 1;
  bool _muted = false;

  /// Every call this handle received, in order.
  ///
  /// A demo prints this: "opened, paused, played" is the pool's whole story.
  final List<String> calls = <String>[];

  /// Source this handle is currently open on.
  PlayerSource? get source => _source;

  /// Command it is in.
  PlaybackCommand get command => _command;

  /// Current volume.
  double get volume => _volume;

  /// Whether it is muted.
  bool get muted => _muted;

  /// A fake player is never torn down from under the pool: a handle that
  /// vanished mid-demo would only demonstrate the framework's error paths.
  @override
  bool get isDisposed => false;

  @override
  Future<void> open(PlayerSource source, {bool autoPlay = false}) async {
    calls.add(
      'open(${source.uri.pathSegments.isEmpty ? source.uri : source.uri.pathSegments.last}'
      '${autoPlay ? ', autoPlay' : ''})',
    );

    if (openDelay > Duration.zero) {
      await Future<void>.delayed(openDelay);
    }

    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      throw StateError('fake player $id refused to open ${source.id}');
    }

    _source = source;
    _position = Duration.zero;
    _command = autoPlay ? const PlaybackCommand.play() : const PlaybackCommand.pause();
    _emit();

    if (autoPlay) {
      _startTicking();
    }
  }

  @override
  Future<void> play() async {
    calls.add('play()');
    _command = const PlaybackCommand.play();
    _emit();
    _startTicking();
  }

  @override
  Future<void> pause() async {
    calls.add('pause()');
    _command = const PlaybackCommand.pause();
    _emit();
    _stopTicking();
  }

  @override
  Future<void> recycle() async {
    calls.add('recycle()');
    _command = const PlaybackCommand.stop();
    _position = Duration.zero;
    _source = null;
    _emit();
    _stopTicking();
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('setVolume(${volume.toStringAsFixed(1)})');
    _volume = volume;
    _emit();
  }

  @override
  Future<void> setMute({required bool muted}) async {
    calls.add('setMute($muted)');
    _muted = muted;
    _emit();
  }

  @override
  Stream<PlayerTransportState> get playbackStream => _playback.stream;

  /// Current playback state.
  PlayerTransportState get state => PlayerTransportState(
    command: _command,
    position: _position,
    duration: const Duration(minutes: 2),
    volume: _muted ? 0 : _volume,
    rate: 1,
    initialized: _source != null,
    updatedAt: DateTime.now(),
  );

  /// Jumps the position, so a demo can simulate a stall by not advancing.
  void seekTo(Duration position) {
    _position = position;
    _emit();
  }

  /// Stops advancing without changing the command: a stall, from the outside.
  void stall() {
    _stopTicking();
    calls.add('stall (position frozen at ${_position.inSeconds}s)');
  }

  void _startTicking() {
    _ticker?.cancel();
    _ticker = Timer.periodic(tick, (_) {
      _position += tick;
      _emit();
    });
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _emit() {
    if (!_playback.isClosed) {
      _playback.add(state);
    }
  }

  @override
  String toString() => 'FakePoolPlayerHandle($id${_source == null ? ', idle' : ', $_commandLabel'})';

  String get _commandLabel => switch (_command) {
    PlaybackCommandPlay() => 'playing',
    PlaybackCommandPause() => 'paused',
    PlaybackCommandStop() => 'stopped',
    _ => _command.runtimeType.toString(),
  };
}

/// Host handing out [FakePoolPlayerHandle]s.
///
/// It counts what it handed out and what came back, which is exactly what a demo
/// about reuse needs to print: "3 players created, 12 acquisitions" is the
/// difference between a pool that recycles and one that leaks decoders.
final class FakePoolPlayerHost implements PoolPlayerHost {
  /// Creates a fake host.
  new({this.openDelay = const Duration(milliseconds: 60), this.failuresBeforeSuccess = 0});

  /// Delay every created handle uses for [FakePoolPlayerHandle.open].
  final Duration openDelay;

  /// Open failures every created handle starts with.
  int failuresBeforeSuccess;

  final List<FakePoolPlayerHandle> _handles = <FakePoolPlayerHandle>[];
  final List<FakePoolPlayerHandle> _released = <FakePoolPlayerHandle>[];
  int _sequence = 0;
  int _acquires = 0;

  /// Every handle this host created, alive or not.
  List<FakePoolPlayerHandle> get handles => List<FakePoolPlayerHandle>.unmodifiable(_handles);

  /// Handles that came back through [release].
  List<FakePoolPlayerHandle> get released => List<FakePoolPlayerHandle>.unmodifiable(_released);

  /// How many times [acquire] was called.
  int get acquires => _acquires;

  /// Handles that still exist and are not disposed.
  Iterable<FakePoolPlayerHandle> get alive => _handles.where((handle) => !handle.isDisposed);

  @override
  Future<PoolPlayerHandle> acquire() async {
    _acquires++;
    final handle = FakePoolPlayerHandle(
      id: 'fake-${++_sequence}',
      openDelay: openDelay,
      failuresBeforeSuccess: failuresBeforeSuccess,
    );
    _handles.add(handle);
    return handle;
  }

  @override
  Future<void> release(PoolPlayerHandle handle) async {
    final fake = handle as FakePoolPlayerHandle;
    if (!_released.contains(fake)) {
      _released.add(fake);
    }
    await fake.recycle();
  }

  @override
  Future<void> disposeHandle(PoolPlayerHandle handle) async {
    final fake = handle as FakePoolPlayerHandle;
    await fake.pause();
  }

  /// Disposes every handle this host created.
  Future<void> disposeAll() async {
    for (final handle in _handles) {
      await handle.pause();
    }
  }

  /// One-line summary of what the host handed out and got back.
  String summary() => 'created ${_handles.length}, acquired $_acquires, released ${_released.length}';
}
