import 'package:media_core_danmaku/media_core_danmaku.dart' show DanmakuRepeatedFilter, DanmakuSimilarityFilter;

/// Tunables for one danmaku session.
///
/// Every value here has a documented default that a caller can accept without
/// reading the module. The defaults are the ones the PureLive live pipeline
/// was tuned on: they are the result of platform backlog, reconnect replay and
/// audience burst observations, not arbitrary round numbers.
///
/// This object is immutable and cheap to copy — a settings change produces a
/// new instance rather than mutating a shared one, so a session that is
/// already connected keeps the config it started with until the caller
/// explicitly applies a new one.
final class DanmakuConfig {
  /// Builds a config from the tuned defaults, overriding only the fields given.
  const DanmakuConfig({
    this.startTimeout = const Duration(seconds: 20),
    this.stopTimeout = const Duration(seconds: 5),
    this.fallbackDuplicateWindow = const Duration(milliseconds: 2500),
    this.stableIdWindow = const Duration(minutes: 10),
    this.maxMessageAge = const Duration(seconds: 45),
    this.maxGateEntries = 4096,
    this.repeatedFilterEnabled = true,
    this.repeatedFilterWindow = const Duration(seconds: 5),
    this.maxRepeatedEntries = 1024,
    this.similarityFilterEnabled = true,
    this.similarityThreshold = 85,
    this.similarityCacheDuration = const Duration(seconds: 3),
    this.similarityMaxCacheSize = 100,
    this.similarityMaxComparisons = 96,
  });

  /// Caller-accepted defaults.
  static const DanmakuConfig defaults = DanmakuConfig();

  /// How long a transport may take to establish a session before the attempt
  /// is abandoned. A platform that never answers must not pin the room.
  final Duration startTimeout;

  /// How long a transport may take to tear down before the caller stops
  /// waiting for confirmation. Teardown is not cancelled on timeout — the
  /// transport keeps releasing in the background.
  final Duration stopTimeout;

  /// Duplicate window for platforms that expose no per-message id.
  ///
  /// Deliberately short: without a stable id, the fingerprint is user plus
  /// text, so a long window would silently swallow repeated genuine messages
  /// such as "666". Long enough to catch a reconnect replay, short enough that
  /// an active chat still shows repetition.
  final Duration fallbackDuplicateWindow;

  /// Duplicate window for messages that do carry a platform id.
  ///
  /// Long, because an id is unambiguous: the same id inside this window is a
  /// replay, never a new message, so audience repetition cannot be lost.
  final Duration stableIdWindow;

  /// Maximum message age accepted on arrival.
  ///
  /// Platform backlog — a socket that kept buffering while the app was
  /// backgrounded — must not be rendered as if it were live chat.
  final Duration maxMessageAge;

  /// Upper bound on remembered message fingerprints. Bounds memory when a
  /// high-traffic room runs for hours.
  final int maxGateEntries;

  /// Whether a burst of identical text from *different* viewers is collapsed
  /// into its first message. See [DanmakuRepeatedFilter].
  final bool repeatedFilterEnabled;

  /// How long a text stays in the repeated filter's window.
  final Duration repeatedFilterWindow;

  /// Upper bound on remembered texts in the repeated filter.
  final int maxRepeatedEntries;

  /// Whether fuzzy similarity suppression is applied. See
  /// [DanmakuSimilarityFilter].
  final bool similarityFilterEnabled;

  /// Minimum similarity score (0..100) that counts as a duplicate.
  final int similarityThreshold;

  /// How long a message stays in the similarity cache.
  final Duration similarityCacheDuration;

  /// Maximum number of messages retained for similarity comparison.
  final int similarityMaxCacheSize;

  /// Maximum edit-distance comparisons per incoming message.
  ///
  /// Kept separate from [similarityMaxCacheSize] so a burst cannot cost up to
  /// `maxCacheSize` comparisons on the UI isolate per packet: the cache keeps
  /// the configured history, the budget bounds the work.
  final int similarityMaxComparisons;

  /// A copy with the given fields replaced; omitted fields keep their current
  /// value, so a settings change yields a new instance rather than mutating a
  /// shared one.
  DanmakuConfig copyWith({
    Duration? startTimeout,
    Duration? stopTimeout,
    Duration? fallbackDuplicateWindow,
    Duration? stableIdWindow,
    Duration? maxMessageAge,
    int? maxGateEntries,
    bool? repeatedFilterEnabled,
    Duration? repeatedFilterWindow,
    int? maxRepeatedEntries,
    bool? similarityFilterEnabled,
    int? similarityThreshold,
    Duration? similarityCacheDuration,
    int? similarityMaxCacheSize,
    int? similarityMaxComparisons,
  }) {
    return DanmakuConfig(
      startTimeout: startTimeout ?? this.startTimeout,
      stopTimeout: stopTimeout ?? this.stopTimeout,
      fallbackDuplicateWindow: fallbackDuplicateWindow ?? this.fallbackDuplicateWindow,
      stableIdWindow: stableIdWindow ?? this.stableIdWindow,
      maxMessageAge: maxMessageAge ?? this.maxMessageAge,
      maxGateEntries: maxGateEntries ?? this.maxGateEntries,
      repeatedFilterEnabled: repeatedFilterEnabled ?? this.repeatedFilterEnabled,
      repeatedFilterWindow: repeatedFilterWindow ?? this.repeatedFilterWindow,
      maxRepeatedEntries: maxRepeatedEntries ?? this.maxRepeatedEntries,
      similarityFilterEnabled: similarityFilterEnabled ?? this.similarityFilterEnabled,
      similarityThreshold: similarityThreshold ?? this.similarityThreshold,
      similarityCacheDuration: similarityCacheDuration ?? this.similarityCacheDuration,
      similarityMaxCacheSize: similarityMaxCacheSize ?? this.similarityMaxCacheSize,
      similarityMaxComparisons: similarityMaxComparisons ?? this.similarityMaxComparisons,
    );
  }
}
