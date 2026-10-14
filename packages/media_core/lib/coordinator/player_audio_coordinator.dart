import 'package:media_core/audio/audio_manager.dart';
import 'package:media_core/audio/audio_volume.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:rxdart/rxdart.dart';

/// Coordinates audio operations across multiple players.
///
/// [PlayerAudioCoordinator] connects players with audio management and provides
/// volume control for each player independently.
///
/// Responsibilities:
/// - Register and unregister audio managers for players
/// - Coordinate volume control for individual players
/// - Manage mute/unmute state for players
/// - Expose reactive volume and mute state
/// - Serialize asynchronous operations
/// - Make disposal idempotent
///
/// Non-responsibilities:
/// - Managing platform audio APIs
/// - Handling audio focus directly
/// - Executing playback
/// - Owning player instances
///
/// Those belong to:
/// - AudioManager
/// - PlatformAudio
/// - PlaybackController
final class PlayerAudioCoordinator {
  /// Creates audio coordinator.
  PlayerAudioCoordinator();

  final Map<PlayerId, AudioManager> _managers = {};
  final Map<PlayerId, AudioVolume> _volumes = {};
  final Map<PlayerId, bool> _mutedStates = {};

  /// Serializes operations.
  Future<void> _operation = Future<void>.value();

  /// Whether the coordinator has been disposed.
  bool _disposed = false;

  final BehaviorSubject<Map<PlayerId, AudioVolume>> _volumesSubject =
      BehaviorSubject<Map<PlayerId, AudioVolume>>.seeded({});

  final BehaviorSubject<Map<PlayerId, bool>> _mutedStatesSubject = BehaviorSubject<Map<PlayerId, bool>>.seeded({});

  /// Emits the current volume for all players.
  ///
  /// This is a hot, replaying stream whose latest value is always available
  /// to new subscribers.
  ValueStream<Map<PlayerId, AudioVolume>> get volumes => _volumesSubject.stream;

  /// Emits the current mute state for all players.
  ValueStream<Map<PlayerId, bool>> get mutedStates => _mutedStatesSubject.stream;

  /// Returns the current volume for a specific player synchronously.
  AudioVolume? getVolume(PlayerId playerId) => _volumes[playerId];

  /// Returns whether a specific player is muted synchronously.
  bool? isMuted(PlayerId playerId) => _mutedStates[playerId];

  /// Returns whether this coordinator has been disposed.
  bool get isDisposed => _disposed;

  /// Registers audio manager for a player.
  ///
  /// [playerId] uniquely identifies the player.
  /// [manager] provides the audio lifecycle management.
  ///
  /// Registration is idempotent. Calling this method with an existing
  /// playerId updates the manager and resets volume/mute state.
  void register({required PlayerId playerId, required AudioManager manager}) {
    _ensureNotDisposed();

    _managers[playerId] = manager;
    _volumes[playerId] = AudioVolume.medium; // 使用静态常量，50% 音量
    _mutedStates[playerId] = false;

    _volumesSubject.add(Map<PlayerId, AudioVolume>.from(_volumes));
    _mutedStatesSubject.add(Map<PlayerId, bool>.from(_mutedStates));
  }

  /// Removes audio manager for a player.
  ///
  /// Returns true if the player was registered and removed.
  bool unregister(PlayerId playerId) {
    _ensureNotDisposed();

    final removed = _managers.remove(playerId) != null;
    _volumes.remove(playerId);
    _mutedStates.remove(playerId);

    if (removed) {
      _volumesSubject.add(Map<PlayerId, AudioVolume>.from(_volumes));
      _mutedStatesSubject.add(Map<PlayerId, bool>.from(_mutedStates));
    }

    return removed;
  }

  /// Gets audio manager for a player.
  ///
  /// Returns null if the player is not registered.
  AudioManager? managerOf(PlayerId playerId) {
    _ensureNotDisposed();
    return _managers[playerId];
  }

  /// Sets volume for a specific player.
  ///
  /// The operation is idempotent. Setting the same volume has no effect.
  ///
  /// Returns `false` when the player is not registered: the change was
  /// dropped, and a caller cannot tell that apart from an applied one
  /// otherwise.
  Future<bool> setVolume({required PlayerId playerId, required AudioVolume volume}) {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!_managers.containsKey(playerId)) {
        return false;
      }

      final currentVolume = _volumes[playerId] ?? AudioVolume.medium;

      if (currentVolume == volume) {
        return true;
      }

      _volumes[playerId] = volume;

      _volumesSubject.add(Map<PlayerId, AudioVolume>.from(_volumes));

      return true;
    });
  }

  /// Mutes audio for a specific player.
  ///
  /// The operation is idempotent. Calling this method while already muted
  /// has no effect.
  ///
  /// Returns `false` when the player is not registered.
  Future<bool> mute(PlayerId playerId) {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!_managers.containsKey(playerId)) {
        return false;
      }

      if (_mutedStates[playerId] == true) {
        return true;
      }

      _mutedStates[playerId] = true;

      _mutedStatesSubject.add(Map<PlayerId, bool>.from(_mutedStates));

      return true;
    });
  }

  /// Unmutes audio for a specific player.
  ///
  /// The operation is idempotent. Calling this method while already unmuted
  /// has no effect.
  ///
  /// Returns `false` when the player is not registered.
  Future<bool> unmute(PlayerId playerId) {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!_managers.containsKey(playerId)) {
        return false;
      }

      if (_mutedStates[playerId] == false) {
        return true;
      }

      _mutedStates[playerId] = false;

      _mutedStatesSubject.add(Map<PlayerId, bool>.from(_mutedStates));

      return true;
    });
  }

  /// Toggles mute state for a specific player.
  ///
  /// Returns `false` when the player is not registered.
  Future<bool> toggleMute(PlayerId playerId) {
    return _enqueue(() async {
      _ensureNotDisposed();

      if (!_managers.containsKey(playerId)) {
        return false;
      }

      final currentMuted = _mutedStates[playerId] ?? false;
      final nextMuted = !currentMuted;

      _mutedStates[playerId] = nextMuted;
      _mutedStatesSubject.add(Map<PlayerId, bool>.from(_mutedStates));

      return true;
    });
  }

  /// Checks if a player is registered.
  bool isRegistered(PlayerId playerId) {
    _ensureNotDisposed();
    return _managers.containsKey(playerId);
  }

  /// Returns all registered player IDs.
  List<PlayerId> get registeredPlayers {
    _ensureNotDisposed();
    return _managers.keys.toList();
  }

  /// Returns the number of registered players.
  int get playerCount {
    _ensureNotDisposed();
    return _managers.length;
  }

  /// Clears all bindings.
  ///
  /// This removes all registered players and clears their states.
  void clear() {
    _ensureNotDisposed();

    _managers.clear();
    _volumes.clear();
    _mutedStates.clear();

    _volumesSubject.add({});
    _mutedStatesSubject.add({});
  }

  /// Executes an operation while preserving the coordinator's operation ordering.
  ///
  /// Every asynchronous operation is chained onto the previous one.
  /// If an earlier operation fails, the queue is reset so a later
  /// operation can still proceed.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final next = _operation.then((_) => operation());

    _operation = next.then((_) {}, onError: (Object _) {});

    return next;
  }

  /// Throws when a public operation is attempted after disposal.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PlayerAudioCoordinator has already been disposed.');
    }
  }

  /// Releases all resources owned by this coordinator.
  ///
  /// Disposal is idempotent. The coordinator first waits for all
  /// queued operations, then closes its reactive streams.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      await _operation;
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    try {
      await _volumesSubject.close();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    try {
      await _mutedStatesSubject.close();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    _managers.clear();
    _volumes.clear();
    _mutedStates.clear();

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}
