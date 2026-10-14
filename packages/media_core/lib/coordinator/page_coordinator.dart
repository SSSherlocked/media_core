import 'package:media_core/identity/player_id.dart';

/// Coordinates page level player behavior.
///
/// [PageCoordinator] manages player bindings
/// related to application pages.
///
/// It does not:
///
/// - manage Flutter routes
/// - create players
/// - execute playback
///
/// Those belong to:
///
/// - UI layer
/// - PlayerFactory
/// - PlaybackController
final class PageCoordinator {
  /// Creates page coordinator.
  PageCoordinator();

  final Map<String, Set<PlayerId>> _pagePlayers = {};

  final Set<String> _activePages = {};

  /// Registers player for page.
  void attachPlayer({required String pageId, required PlayerId playerId}) {
    _pagePlayers.putIfAbsent(pageId, () => <PlayerId>{}).add(playerId);
  }

  /// Removes player from page.
  bool detachPlayer({required String pageId, required PlayerId playerId}) {
    final players = _pagePlayers[pageId];

    if (players == null) {
      return false;
    }

    final removed = players.remove(playerId);

    if (players.isEmpty) {
      _pagePlayers.remove(pageId);
    }

    return removed;
  }

  /// Marks page active.
  void activate(String pageId) {
    _activePages.add(pageId);
  }

  /// Marks page inactive.
  void deactivate(String pageId) {
    _activePages.remove(pageId);
  }

  /// Whether page is active.
  bool isActive(String pageId) {
    return _activePages.contains(pageId);
  }

  /// Gets players attached to page.
  List<PlayerId> playersOf(String pageId) {
    return List.unmodifiable(_pagePlayers[pageId] ?? const {});
  }

  /// Removes page.
  void removePage(String pageId) {
    _pagePlayers.remove(pageId);
    _activePages.remove(pageId);
  }

  /// Clears all pages.
  void clear() {
    _pagePlayers.clear();
    _activePages.clear();
  }

  /// Disposes coordinator.
  Future<void> dispose() async {
    clear();
  }
}
