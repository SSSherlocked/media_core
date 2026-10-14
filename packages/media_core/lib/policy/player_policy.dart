import 'package:media_core/policy/concurrency_policy.dart';
import 'package:media_core/policy/playback_policy.dart';
import 'package:media_core/policy/recovery_policy.dart';
import 'package:media_core/policy/resource_policy.dart';
import 'package:meta/meta.dart';

/// Root policy configuration for player runtime.
///
/// [PlayerPolicy] aggregates all player behavior
/// policies.
///
/// Responsibilities:
///
/// - provide global player rules
/// - enable or disable player policy system
/// - combine module policies
///
/// It does not:
///
/// - execute playback
/// - manage lifecycle
/// - create backend
///
/// Those belong to:
///
/// - PlayerIdentity
/// - Session
/// - Factory
@immutable
final class PlayerPolicy {
  /// Creates player policy.
  const PlayerPolicy({
    this.enabled = true,

    this.playback = const PlaybackPolicy(),

    this.resource = const ResourcePolicy(),

    this.recovery = const RecoveryPolicy(),

    this.concurrency = const ConcurrencyPolicy(),
  });

  /// Whether player policy system is enabled.
  ///
  /// This is a global switch for player runtime
  /// policy handling.
  ///
  /// It does not mean:
  ///
  /// - playback is possible
  /// - source is valid
  /// - backend exists
  final bool enabled;

  /// Playback behavior policy.
  final PlaybackPolicy playback;

  /// Resource usage policy.
  final ResourcePolicy resource;

  /// Error recovery policy.
  final RecoveryPolicy recovery;

  /// Concurrency policy.
  final ConcurrencyPolicy concurrency;

  /// Whether this policy allows runtime control.
  bool get isEnabled {
    return enabled;
  }

  /// Whether playback policy is available.
  bool get canPlayback {
    return enabled;
  }

  /// Whether resource management policy is available.
  bool get canManageResource {
    return enabled;
  }

  /// Whether recovery policy is available.
  bool get canRecover {
    return enabled;
  }

  /// Whether concurrency policy is available.
  bool get canControlConcurrency {
    return enabled;
  }

  /// Creates copy with changed values.
  PlayerPolicy copyWith({
    bool? enabled,

    PlaybackPolicy? playback,

    ResourcePolicy? resource,

    RecoveryPolicy? recovery,

    ConcurrencyPolicy? concurrency,
  }) {
    return PlayerPolicy(
      enabled: enabled ?? this.enabled,

      playback: playback ?? this.playback,

      resource: resource ?? this.resource,

      recovery: recovery ?? this.recovery,

      concurrency: concurrency ?? this.concurrency,
    );
  }

  @override
  String toString() {
    return 'PlayerPolicy('
        'enabled=$enabled, '
        'playback=$playback, '
        'resource=$resource, '
        'recovery=$recovery, '
        'concurrency=$concurrency'
        ')';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlayerPolicy &&
            other.enabled == enabled &&
            other.playback == playback &&
            other.resource == resource &&
            other.recovery == recovery &&
            other.concurrency == concurrency;
  }

  @override
  int get hashCode {
    return Object.hash(enabled, playback, resource, recovery, concurrency);
  }
}
