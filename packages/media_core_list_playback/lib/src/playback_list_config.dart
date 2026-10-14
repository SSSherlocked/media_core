import 'package:media_core/media_core.dart' show PlaybackPoolOrchestrator, PlayerPoolConfig;

/// Tunables for list playback.
final class PlaybackListConfig {
  /// Creates a list-playback tunable set.
  ///
  /// [resumeEnabled] controls whether an item picks up where it was left,
  /// [completionThreshold] is how close to the end still counts as finished, and
  /// [maxRememberedItems] bounds how many positions the store keeps.
  const PlaybackListConfig({
    this.resumeEnabled = true,
    this.completionThreshold = const Duration(seconds: 20),
    this.maxRememberedItems = 200,
  });

  /// Caller-accepted defaults.
  static const PlaybackListConfig defaults = PlaybackListConfig();

  /// Pool settings this feature recommends.
  ///
  /// A list is the case pooling was built for: one item plays while the item a
  /// swipe reaches stays open, so the swipe is a source swap rather than a cold
  /// start. One neighbour each side is enough for a swipe in either direction,
  /// and idle players are reused instead of released — three players cover an
  /// endless list.
  ///
  /// Hosts pass this to their [PlaybackPoolOrchestrator]; nothing here creates
  /// one, because only the host knows where players come from.
  static const PlayerPoolConfig recommendedPoolConfig = PlayerPoolConfig(
    idleTimeout: Duration(seconds: 30),
    keepWarm: true,
    warmSize: 3,
    preloadTimeout: Duration(seconds: 10),
  );

  /// Whether an item resumes where it was left.
  ///
  /// Off means every item starts at zero, which is what a live stream or a
  /// short clip wants — nothing to remember and nothing worth seeking.
  final bool resumeEnabled;

  /// How close to the end counts as finished.
  ///
  /// An item that was abandoned in its final stretch resumes from the start
  /// instead: the viewer almost certainly watched it to the end, and replaying
  /// the last few seconds is worse than replaying from the beginning. It is a
  /// duration rather than a fraction because the last seconds are what a
  /// viewer remembers, not the last percent.
  final Duration completionThreshold;

  /// Upper bound on remembered items.
  ///
  /// Progress is per item and grows with the list, so it is bounded: the store
  /// evicts the least recently touched entries.
  final int maxRememberedItems;

  /// Returns a copy with the given fields replaced.
  ///
  /// Null arguments keep the current value, so a caller only names what it
  /// wants to change.
  PlaybackListConfig copyWith({bool? resumeEnabled, Duration? completionThreshold, int? maxRememberedItems}) {
    return PlaybackListConfig(
      resumeEnabled: resumeEnabled ?? this.resumeEnabled,
      completionThreshold: completionThreshold ?? this.completionThreshold,
      maxRememberedItems: maxRememberedItems ?? this.maxRememberedItems,
    );
  }
}
