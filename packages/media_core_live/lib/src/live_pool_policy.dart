import 'package:media_core/media_core.dart' show PlayerPoolConfig;

/// How a live session wants the playback pool to behave.
///
/// Live differs from a feed or a list in what "next" means: there is no next
/// item, there is a **line** to fall back to. What the pool buys here is the
/// same thing it buys elsewhere — the fallback target is already open when the
/// current line stalls, so a line switch is a source swap instead of a cold
/// start during the worst possible moment (the viewer is staring at a frozen
/// picture).
///
/// The values are deliberately tighter than a feed's: a live line that is warm
/// for minutes is a bandwidth bill for a stream nobody is watching, so idle
/// players are released quickly and only a single spare is kept.
final class LivePoolPolicy {
  /// Declares a standby policy; [defaults] covers the common live case.
  const LivePoolPolicy({
    this.warmStandbyEnabled = true,
    this.warmStandbyCount = 1,
    this.releaseIdleAfter = const Duration(seconds: 15),
  });

  /// Caller-accepted defaults.
  static const LivePoolPolicy defaults = LivePoolPolicy();

  /// Whether the pool keeps a spare player open for the next line.
  final bool warmStandbyEnabled;

  /// How many spare lines are kept warm.
  ///
  /// One is enough for the common case (the next line in the list); more only
  /// helps a session that falls through several dead lines in a row.
  final int warmStandbyCount;

  /// How long a spare player may stay open without being used.
  final Duration releaseIdleAfter;

  /// Pool settings this policy maps onto.
  ///
  /// The host passes this to its `PlaybackPoolOrchestrator`; the live
  /// controller does not create a pool itself, because only the host knows
  /// where players come from and whether the kernel's instance pool is enabled.
  PlayerPoolConfig toPoolConfig() {
    return PlayerPoolConfig(
      preloadCount: warmStandbyEnabled ? warmStandbyCount : 0,
      idleTimeout: releaseIdleAfter,
      keepWarm: warmStandbyEnabled,
      warmSize: warmStandbyEnabled ? warmStandbyCount + 1 : 0,
      preloadTimeout: const Duration(seconds: 10),
    );
  }

  /// The same policy with the given fields replaced.
  ///
  /// A `null` argument keeps the current value, so a caller changes one
  /// setting without restating the others.
  LivePoolPolicy copyWith({bool? warmStandbyEnabled, int? warmStandbyCount, Duration? releaseIdleAfter}) {
    return LivePoolPolicy(
      warmStandbyEnabled: warmStandbyEnabled ?? this.warmStandbyEnabled,
      warmStandbyCount: warmStandbyCount ?? this.warmStandbyCount,
      releaseIdleAfter: releaseIdleAfter ?? this.releaseIdleAfter,
    );
  }
}
