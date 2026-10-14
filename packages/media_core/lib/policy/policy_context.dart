import 'package:media_core/policy/audio_policy.dart';
import 'package:media_core/policy/cache_policy.dart';
import 'package:media_core/policy/concurrency_policy.dart';
import 'package:media_core/policy/fallback_policy.dart';
import 'package:media_core/policy/lifecycle_policy.dart';
import 'package:media_core/policy/memory_policy.dart';
import 'package:media_core/policy/playback_policy.dart';
import 'package:media_core/policy/player_policy.dart';
import 'package:media_core/policy/preload_policy.dart';
import 'package:media_core/policy/presentation_policy.dart';
import 'package:media_core/policy/recovery_policy.dart';
import 'package:media_core/policy/resource_policy.dart';
import 'package:media_core/policy/thermal_policy.dart';
import 'package:media_core/policy/visibility_policy.dart';

/// Runtime policy container.
///
/// [PolicyContext] is the single source of truth
/// for all player policies.
///
/// Responsibilities:
///
/// - aggregate policies
/// - provide runtime configuration
/// - create default policy set
///
/// It does not:
///
/// - execute policies
/// - manage player lifecycle
/// - control playback
final class PolicyContext {
  /// Creates policy context.
  const PolicyContext({
    required this.player,

    required this.playback,

    required this.preload,

    required this.concurrency,

    required this.memory,

    required this.thermal,

    required this.audio,

    required this.lifecycle,

    required this.recovery,

    required this.resource,

    required this.visibility,

    required this.fallback,

    required this.presentation,

    required this.cache,
  });

  /// Creates default policies.
  factory PolicyContext.defaults() {
    return const PolicyContext(
      player: PlayerPolicy(),

      playback: PlaybackPolicy(),

      preload: PreloadPolicy(),

      concurrency: ConcurrencyPolicy(),

      memory: MemoryPolicy(),

      thermal: ThermalPolicy(),

      audio: AudioPolicy(),

      lifecycle: LifecyclePolicy(),

      recovery: RecoveryPolicy(),

      resource: ResourcePolicy(),

      visibility: VisibilityPolicy(),

      fallback: FallbackPolicy(),

      presentation: PresentationPolicy(),

      cache: CachePolicy(),
    );
  }

  /// PlayerIdentity policy.
  final PlayerPolicy player;

  /// Playback policy.
  final PlaybackPolicy playback;

  /// Preload policy.
  final PreloadPolicy preload;

  /// Concurrency policy.
  final ConcurrencyPolicy concurrency;

  /// Memory policy.
  final MemoryPolicy memory;

  /// Thermal policy.
  final ThermalPolicy thermal;

  /// Audio policy.
  final AudioPolicy audio;

  /// Lifecycle policy.
  final LifecyclePolicy lifecycle;

  /// Recovery policy.
  final RecoveryPolicy recovery;

  /// Resource policy.
  final ResourcePolicy resource;

  /// Visibility policy.
  final VisibilityPolicy visibility;

  /// Fallback policy.
  final FallbackPolicy fallback;

  /// Presentation policy.
  final PresentationPolicy presentation;

  /// Cache policy.
  final CachePolicy cache;

  /// Creates a copy with modified policies.
  PolicyContext copyWith({
    PlayerPolicy? player,

    PlaybackPolicy? playback,

    PreloadPolicy? preload,

    ConcurrencyPolicy? concurrency,

    MemoryPolicy? memory,

    ThermalPolicy? thermal,

    AudioPolicy? audio,

    LifecyclePolicy? lifecycle,

    RecoveryPolicy? recovery,

    ResourcePolicy? resource,

    VisibilityPolicy? visibility,

    FallbackPolicy? fallback,

    PresentationPolicy? presentation,

    CachePolicy? cache,
  }) {
    return PolicyContext(
      player: player ?? this.player,

      playback: playback ?? this.playback,

      preload: preload ?? this.preload,

      concurrency: concurrency ?? this.concurrency,

      memory: memory ?? this.memory,

      thermal: thermal ?? this.thermal,

      audio: audio ?? this.audio,

      lifecycle: lifecycle ?? this.lifecycle,

      recovery: recovery ?? this.recovery,

      resource: resource ?? this.resource,

      visibility: visibility ?? this.visibility,

      fallback: fallback ?? this.fallback,

      presentation: presentation ?? this.presentation,

      cache: cache ?? this.cache,
    );
  }

  /// Whether all policies are enabled.
  bool get enabled {
    return player.enabled;
  }

  @override
  String toString() {
    return 'PolicyContext('
        'player=$player, '
        'playback=$playback, '
        'recovery=$recovery'
        ')';
  }
}
