import 'package:media_core/media_core.dart' show PlayerPoolConfig;

/// Tunables for a vertical feed.
final class FeedConfig {
  /// Creates a feed configuration.
  const FeedConfig({this.preloadAhead = true});

  /// Caller-accepted defaults.
  static const FeedConfig defaults = FeedConfig();

  /// Whether the next item is queued for preload when an item becomes visible.
  ///
  /// Only meaningful without a pool: a pool keeps neighbours genuinely open,
  /// which is stronger than a queued intent.
  final bool preloadAhead;

  /// Pool settings a feed wants.
  ///
  /// Exactly one item plays at a time in a feed, one neighbour each side is
  /// what a swipe can reach, and idle players are reused rather than released:
  /// three players then cover an unlimited feed, and a swipe is a source swap
  /// on a player that is already open.
  static const PlayerPoolConfig recommendedPoolConfig = PlayerPoolConfig(
    idleTimeout: Duration(seconds: 30),
    keepWarm: true,
    warmSize: 3,
    preloadTimeout: Duration(seconds: 10),
  );

  /// Returns a copy of this config with the supplied fields replaced.
  FeedConfig copyWith({bool? preloadAhead}) => FeedConfig(preloadAhead: preloadAhead ?? this.preloadAhead);
}
