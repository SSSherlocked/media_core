import 'package:media_core_multiview/src/multiview_layout.dart';

/// Which cell the viewer is listening to.
enum MultiviewAudioMode {
  /// Exactly one cell is audible — the focused one.
  ///
  /// The default, and the only mode that makes sense for a wall: several live
  /// streams at once is noise, not information.
  exclusive,

  /// Nothing is audible; every cell is muted.
  ///
  /// For a monitoring wall that is watched, not listened to.
  muted,

  /// Every cell is audible at its own volume.
  ///
  /// Off by default and discouraged: the streams are not mixed, so this is a
  /// pile of audio rather than a mix. Kept because a host may want one cell loud
  /// and another as a quiet cue.
  mixed,
}

/// How a cell's quality follows its focus.
enum MultiviewQualityPolicy {
  /// The focused cell plays at the requested quality, the others are stepped
  /// down.
  ///
  /// What a wall wants: one stream worth looking at, eight that only have to be
  /// recognisable. Stepping down is also what keeps the decoders inside their
  /// budget.
  focusFirst,

  /// Every cell plays what was asked for.
  uniform,
}

/// What happens when the decode or memory budget is exceeded.
enum MultiviewBudgetPolicy {
  /// Stop the cells that are not focused, keep the focused one.
  ///
  /// Degrading to one stream is the honest response to a device that cannot
  /// decode nine: the viewer keeps watching something instead of watching a
  /// wall of stutter.
  keepFocusedOnly,

  /// Keep every cell playing and let the platform drop frames.
  letPlatformDrop,

  /// Refuse to add cells past the budget.
  ///
  /// The conservative choice: the wall never exceeds what the device can show,
  /// at the cost of refusing a cell the viewer asked for.
  refuseNewCells,
}

/// Tunables for the wall.
final class MultiviewConfig {
  /// Creates a wall configuration, using defaults for the unspecified tunables.
  const MultiviewConfig({
    this.layout = MultiviewLayout.quad,
    this.maxCells = 4,
    this.audioMode = MultiviewAudioMode.exclusive,
    this.qualityPolicy = MultiviewQualityPolicy.focusFirst,
    this.budgetPolicy = MultiviewBudgetPolicy.keepFocusedOnly,
    this.degradeQualityWhenCrowded = true,
    this.danmakuOnlyOnFocused = true,
    this.patrolEnabled = false,
    this.patrolInterval = const Duration(seconds: 30),
    this.patrolSkipsOfflineCells = true,
    this.cellStartTimeout = const Duration(seconds: 20),
    this.cellStallTimeout = const Duration(seconds: 15),
    this.cellMaxRestarts = 2,
    this.focusedVolume = 1,
    this.backgroundVolume = 0,
    this.autoResumeOnForeground = true,
  });

  /// Caller-accepted defaults.
  static const MultiviewConfig defaults = MultiviewConfig();

  /// Grid to show.
  final MultiviewLayout layout;

  /// Hard cap on cells, whatever the layout allows.
  ///
  /// The layout says what fits on screen; this says what the host is willing to
  /// decode. A phone in portrait may show a 3x3 grid but only afford four
  /// decoders.
  final int maxCells;

  /// How audio is owned across cells.
  final MultiviewAudioMode audioMode;

  /// How quality follows focus.
  final MultiviewQualityPolicy qualityPolicy;

  /// What to do when the budget is exceeded.
  final MultiviewBudgetPolicy budgetPolicy;

  /// Whether non-focused cells are stepped down.
  ///
  /// Independent of [qualityPolicy] so a host can ask for a uniform wall but
  /// still let the wall degrade when it grows.
  final bool degradeQualityWhenCrowded;

  /// Whether danmaku runs only on the focused cell.
  ///
  /// On by default: a danmaku layer per cell is a lot of text on a small
  /// surface, and the reader can only read one at a time anyway. The per-cell
  /// overlay exists either way — this only decides whether it is fed.
  final bool danmakuOnlyOnFocused;

  /// Whether the focus rotates on its own, like a monitoring wall's patrol.
  final bool patrolEnabled;

  /// How long each cell stays focused during a patrol.
  final Duration patrolInterval;

  /// Whether a patrol skips cells that are offline or failed.
  ///
  /// On by default: patrol exists to keep an eye on what is live, and dwelling
  /// on a dead cell wastes the dwell.
  final bool patrolSkipsOfflineCells;

  /// How long a cell may take to start before it is treated as failed.
  final Duration cellStartTimeout;

  /// How long a playing cell may show no progress before it is restarted.
  final Duration cellStallTimeout;

  /// How many times a cell may be restarted before it stays failed.
  ///
  /// Bounded on purpose: a wall that restarts a dead stream forever burns
  /// bandwidth and battery for nothing, and the viewer needs to see that the
  /// cell is down.
  final int cellMaxRestarts;

  /// Volume for the focused cell when audio is exclusive.
  final double focusedVolume;

  /// Volume for the others when audio is exclusive.
  ///
  /// Zero by default, but kept configurable: a monitoring host may want the
  /// unfocused cells audible as a cue.
  final double backgroundVolume;

  /// Whether playback resumes when the app returns to the foreground.
  final bool autoResumeOnForeground;

  /// Whether [cellCount] fits the configured cap.
  bool acceptsCells(int cellCount) => cellCount <= maxCells && layout.accepts(cellCount);

  /// The effective cap: the smaller of the layout and the host's limit.
  int get effectiveMaxCells => layout.capacity < maxCells ? layout.capacity : maxCells;

  /// A copy with the given tunables replaced; omitted ones keep their current value.
  MultiviewConfig copyWith({
    MultiviewLayout? layout,
    int? maxCells,
    MultiviewAudioMode? audioMode,
    MultiviewQualityPolicy? qualityPolicy,
    MultiviewBudgetPolicy? budgetPolicy,
    bool? degradeQualityWhenCrowded,
    bool? danmakuOnlyOnFocused,
    bool? patrolEnabled,
    Duration? patrolInterval,
    bool? patrolSkipsOfflineCells,
    Duration? cellStartTimeout,
    Duration? cellStallTimeout,
    int? cellMaxRestarts,
    double? focusedVolume,
    double? backgroundVolume,
    bool? autoResumeOnForeground,
  }) {
    return MultiviewConfig(
      layout: layout ?? this.layout,
      maxCells: maxCells ?? this.maxCells,
      audioMode: audioMode ?? this.audioMode,
      qualityPolicy: qualityPolicy ?? this.qualityPolicy,
      budgetPolicy: budgetPolicy ?? this.budgetPolicy,
      degradeQualityWhenCrowded: degradeQualityWhenCrowded ?? this.degradeQualityWhenCrowded,
      danmakuOnlyOnFocused: danmakuOnlyOnFocused ?? this.danmakuOnlyOnFocused,
      patrolEnabled: patrolEnabled ?? this.patrolEnabled,
      patrolInterval: patrolInterval ?? this.patrolInterval,
      patrolSkipsOfflineCells: patrolSkipsOfflineCells ?? this.patrolSkipsOfflineCells,
      cellStartTimeout: cellStartTimeout ?? this.cellStartTimeout,
      cellStallTimeout: cellStallTimeout ?? this.cellStallTimeout,
      cellMaxRestarts: cellMaxRestarts ?? this.cellMaxRestarts,
      focusedVolume: focusedVolume ?? this.focusedVolume,
      backgroundVolume: backgroundVolume ?? this.backgroundVolume,
      autoResumeOnForeground: autoResumeOnForeground ?? this.autoResumeOnForeground,
    );
  }
}
