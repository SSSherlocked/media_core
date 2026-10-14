import 'package:media_core/identity/player_id.dart';
import 'package:media_core/playback/playback_command.dart';
import 'package:media_core/playback/playback_controller.dart';
import 'package:media_core/playback/playback_request.dart';

/// Coordinates playback operations.
///
/// [PlaybackCoordinator] bridges high-level
/// playback requests and playback controllers.
///
/// Responsibilities:
///
/// - locate the playback controller for a player
/// - forward playback requests
/// - manage controller bindings
///
/// It does not:
///
/// - execute media commands itself
/// - manage playback sessions
/// - manage backend
/// - store playback state
///
/// Those responsibilities belong to:
///
/// - PlaybackController
/// - PlayerSession
/// - PlayerAdapter
/// - PlayerTransportState
final class PlaybackCoordinator {
  /// Creates playback coordinator.
  PlaybackCoordinator();

  final Map<PlayerId, PlaybackController> _controllers = {};

  /// Registers playback controller.
  ///
  /// An existing controller registered for the same player is replaced.
  void register({required PlayerId playerId, required PlaybackController controller}) {
    _controllers[playerId] = controller;
  }

  /// Removes playback controller.
  ///
  /// Returns `true` when a controller was removed.
  bool unregister(PlayerId playerId) {
    return _controllers.remove(playerId) != null;
  }

  /// Gets playback controller.
  ///
  /// Returns `null` when no controller is registered.
  PlaybackController? controllerOf(PlayerId playerId) {
    return _controllers[playerId];
  }

  /// Executes a playback command.
  ///
  /// The command is converted into a [PlaybackRequest] and forwarded to
  /// [PlaybackController], which remains responsible for serializing and
  /// applying playback operations.
  ///
  /// Returns `false` when no controller is registered for [playerId]: the
  /// command was dropped, which a caller of `play()`/`pause()` must be able to
  /// tell apart from a command that reached a player.
  Future<bool> execute({required PlayerId playerId, required PlaybackCommand command}) async {
    final controller = _controllers[playerId];

    if (controller == null) {
      return false;
    }

    await controller.request(PlaybackRequest(command: command));

    return true;
  }

  /// Releases all controller bindings.
  ///
  /// This does not dispose the registered controllers because the coordinator
  /// does not own their lifecycle.
  void clear() {
    _controllers.clear();
  }

  /// Disposes coordinator.
  ///
  /// Registered controllers are not disposed here because they are owned by
  /// their respective player lifecycle.
  Future<void> dispose() async {
    clear();
  }
}
