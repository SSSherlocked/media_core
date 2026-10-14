import 'package:media_core/identity/player_id.dart';
import 'package:media_core/presentation/presentation_controller.dart';
import 'package:media_core/presentation/presentation_request.dart';

/// Coordinates presentation controllers between players.
///
/// This is a player-level coordinator.
///
/// Responsibilities:
///
/// - bind player id
/// - lookup presentation controller
/// - route presentation requests
///
/// Does not:
///
/// - call platform APIs
/// - manage windows
/// - handle native events
final class PresentationCoordinator {
  /// Creates coordinator.
  PresentationCoordinator();

  final Map<PlayerId, PresentationController> _controllers = <PlayerId, PresentationController>{};

  bool _disposed = false;

  /// Registers presentation controller.
  void register({required PlayerId playerId, required PresentationController controller}) {
    _ensureNotDisposed();

    _controllers[playerId] = controller;
  }

  /// Removes presentation controller.
  bool unregister(PlayerId playerId) {
    _ensureNotDisposed();

    return _controllers.remove(playerId) != null;
  }

  /// Gets controller of player.
  PresentationController? controllerOf(PlayerId playerId) {
    _ensureNotDisposed();

    return _controllers[playerId];
  }

  /// Sends presentation request.
  Future<void> request({required PlayerId playerId, required PresentationRequest request}) async {
    _ensureNotDisposed();

    final controller = _controllers[playerId];

    if (controller == null) {
      throw StateError('No PresentationController registered for player: $playerId');
    }

    await controller.request(request);
  }

  /// Enters fullscreen.
  Future<void> fullscreen(PlayerId playerId) {
    return request(playerId: playerId, request: PresentationRequest.fullscreen());
  }

  /// Exits fullscreen.
  Future<void> exitFullscreen(PlayerId playerId) {
    return request(playerId: playerId, request: PresentationRequest.normal());
  }

  /// Enters PiP.
  Future<void> enterPip(PlayerId playerId) {
    return request(playerId: playerId, request: PresentationRequest.pip());
  }

  /// Exits PiP.
  Future<void> exitPip(PlayerId playerId) {
    return request(playerId: playerId, request: PresentationRequest.normal());
  }

  /// Clears all bindings.
  void clear() {
    _ensureNotDisposed();

    _controllers.clear();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PresentationCoordinator has already been disposed.');
    }
  }

  /// Releases resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    for (final controller in _controllers.values) {
      await controller.dispose();
    }

    _controllers.clear();
  }
}
