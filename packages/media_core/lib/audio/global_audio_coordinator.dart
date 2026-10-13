import 'dart:async';
import 'package:media_core/audio/audio_coordinator.dart';
import 'package:rxdart/rxdart.dart';

/// Global coordinator for audio ownership across multiple playback sessions.
///
/// While [AudioCoordinator] manages the lifecycle of a single session's focus,
/// [GlobalAudioCoordinator] decides which session *should* have focus among
/// all active sessions.
///
/// It implements a "last-win" ownership policy by default: the most recently
/// requested session claims the audio channel.
final class GlobalAudioCoordinator {
  /// Creates a global audio coordinator.
  GlobalAudioCoordinator();

  /// The session currently owning the audio channel.
  AudioCoordinator? _owner;

  /// List of all registered coordinators.
  final List<AudioCoordinator> _coordinators = [];

  /// Stream of the current owner.
  final BehaviorSubject<AudioCoordinator?> _ownerSubject = BehaviorSubject<AudioCoordinator?>.seeded(null);

  /// Current audio owner.
  ValueStream<AudioCoordinator?> get owner => _ownerSubject.stream;

  /// Register a coordinator to be managed by the global system.
  void register(AudioCoordinator coordinator) {
    if (!_coordinators.contains(coordinator)) {
      _coordinators.add(coordinator);
    }
  }

  /// Unregister a coordinator.
  void unregister(AudioCoordinator coordinator) {
    if (_owner == coordinator) {
      _owner = null;
      _ownerSubject.add(null);
    }
    _coordinators.remove(coordinator);
  }

  /// Requests audio ownership for a specific coordinator.
  ///
  /// This will:
  /// 1. Revoke focus from the current owner.
  /// 2. Grant focus to the requester.
  Future<void> claimOwnership(AudioCoordinator requester) async {
    if (_owner == requester) return;

    // 1. Revoke from old owner
    if (_owner != null) {
      await _owner!.abandonFocus();
    }

    // 2. Grant to new owner
    try {
      await requester.requestFocus();
      _owner = requester;
      _ownerSubject.add(requester);
    } catch (error) {
      // If request fails, we might want to fallback or report error.
      _owner = null;
      _ownerSubject.add(null);
      rethrow;
    }
  }

  /// Releases the current ownership.
  Future<void> releaseOwnership() async {
    if (_owner == null) return;
    
    final owner = _owner;
    _owner = null;
    _ownerSubject.add(null);
    
    await owner!.abandonFocus();
  }

  /// Disposes the coordinator and cleans up.
  void dispose() {
    _ownerSubject.close();
    _coordinators.clear();
  }
}
