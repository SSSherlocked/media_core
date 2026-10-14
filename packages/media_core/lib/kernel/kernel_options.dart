import 'package:media_core/core/player_config.dart' show PlayerConfig;
import 'package:media_core/core/player_constants.dart';

/// Global options for the player kernel.
///
/// [KernelOptions] tunes cross-cutting behaviour of the
/// orchestration layer. Per-player overrides come from
/// [PlayerConfig] passed to `PlayerKernel.create`.
///
/// Responsibilities:
///
/// - describe kernel-wide defaults
/// - tune recovery and fallback behaviour
/// - supply the recovery budget and ladder policy every player starts from
///
/// It does not:
///
/// - store per-player state
/// - make policy decisions for a single player
/// - decide when a specific player recovers (the ladder does)
final class KernelOptions {
  /// Creates kernel options.
  const KernelOptions({
    this.enableRecovery = true,
    this.enableFallback = true,
    this.enablePool = true,
    this.enableEventBus = true,
    this.autoAttachAudio = true,
    this.pauseWhenBackgrounded = true,
    this.maxRecoveryAttempts = PlayerConstants.maxRecoveryAttempts,
    this.maxFallbackAttempts = PlayerConstants.maxFallbackAttempts,
    this.retryBaseDelay = const Duration(seconds: 1),
    this.retryMaxDelay = const Duration(seconds: 8),
  });

  /// Whether automatic error recovery is enabled.
  final bool enableRecovery;

  /// Whether automatic backend fallback is enabled.
  final bool enableFallback;

  /// Whether created players join the player pool.
  final bool enablePool;

  /// Whether kernel events are published to the event bus.
  final bool enableEventBus;

  /// Whether leaving the app pauses everything this kernel is playing.
  ///
  /// On by default, and it applies to **every** live handle of the kernel: a
  /// wall of nine streams, a feed holding a warm window and the one on screen
  /// all stop, because "the app is not visible" and "nine decoders should keep
  /// burning battery" is not a combination anyone chose deliberately. Each
  /// handle goes through `deactivate()`, which is the same path a manual pause
  /// takes plus the recovery ladder standing down — no half-decoded frame is
  /// left running behind a hidden widget.
  ///
  /// Returning to the foreground does **not** resume anything: audio starting by
  /// itself after an app switch reads as a bug, so the viewer resumes.
  ///
  /// Off is the background-audio shape (a music app, an audio book): the host
  /// keeps playing and owns telling the user about it — through
  /// `media_core_mediasession`'s media notification on mobile, and through
  /// `media_core_native`'s background execution session if the process itself
  /// needs permission to run.
  final bool pauseWhenBackgrounded;

  /// Default maximum recovery attempts per error.
  ///
  /// A [PlayerConfig] with its own value wins.
  final int maxRecoveryAttempts;

  /// Default maximum fallback attempts per error.
  ///
  /// A [PlayerConfig] with its own value wins.
  final int maxFallbackAttempts;

  /// Base delay before the first recovery retry.
  ///
  /// The attempt that opens a sweep is immediate; this is what the retries cost,
  /// doubling per attempt (with jitter, so a feed whose players all fail on the
  /// same dead CDN do not re-ask it in the same millisecond) up to
  /// [retryMaxDelay]. See `RecoveryLadder.retryDelay`.
  final Duration retryBaseDelay;

  /// Upper bound for a single recovery retry delay.
  final Duration retryMaxDelay;

  /// Whether this kernel takes the process-wide media-session driver.
  ///
  /// A capability package installs one via `PlayerKernel.audioDriverFactory` —
  /// `MediaSessionBootstrap.enable()` in `media_core_mediasession` does exactly
  /// that — and every kernel created afterwards attaches it, so a host does not
  /// have to remember `attachAudio` for each player. Set this to false for a
  /// kernel that must not publish to the platform's media surfaces: a settings
  /// preview, a diagnostic player, or a second kernel that would fight the
  /// first for the single notification.
  final bool autoAttachAudio;

  /// Whether a driver should be attached to a new kernel.
  ///
  /// The rule in one place: the capability has to be installed process-wide
  /// *and* this kernel has to want it.
  bool shouldAttachAudio({required bool hasFactory}) => autoAttachAudio && hasFactory;

  /// Creates a copy with modifications.
  KernelOptions copyWith({
    bool? enableRecovery,
    bool? enableFallback,
    bool? enablePool,
    bool? enableEventBus,
    bool? autoAttachAudio,
    int? maxRecoveryAttempts,
    int? maxFallbackAttempts,
    Duration? retryBaseDelay,
    Duration? retryMaxDelay,
  }) {
    return KernelOptions(
      enableRecovery: enableRecovery ?? this.enableRecovery,
      enableFallback: enableFallback ?? this.enableFallback,
      enablePool: enablePool ?? this.enablePool,
      enableEventBus: enableEventBus ?? this.enableEventBus,
      autoAttachAudio: autoAttachAudio ?? this.autoAttachAudio,
      maxRecoveryAttempts: maxRecoveryAttempts ?? this.maxRecoveryAttempts,
      maxFallbackAttempts: maxFallbackAttempts ?? this.maxFallbackAttempts,
      retryBaseDelay: retryBaseDelay ?? this.retryBaseDelay,
      retryMaxDelay: retryMaxDelay ?? this.retryMaxDelay,
    );
  }
}
