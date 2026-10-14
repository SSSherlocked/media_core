import 'package:media_core/identity/player_id.dart';
import 'package:media_core/presentation/presentation_mode.dart';

/// The four points around one presentation transition.
///
/// Enter transitions run `beforeEnter` → the platform work → `afterEnter`;
/// exit transitions run `beforeExit` → leaving the mode → `afterExit`.
enum PresentationLifecyclePhase {
  /// Fires before the driver starts entering the mode.
  beforeEnter,

  /// Fires once the mode is active.
  afterEnter,

  /// Fires before the driver starts leaving the mode.
  beforeExit,

  /// Fires once the mode is gone.
  afterExit,
}

/// What a lifecycle hook is told.
///
/// [mode] is the presentation mode of the transition — for a driver serving
/// several variants (fullscreen's screen and window variants) it names the
/// concrete one, for single-mode drivers it is always the driver's own mode.
final class PresentationLifecycleEvent {
  /// Describes the transition point [phase] for [playerId] in [mode].
  const PresentationLifecycleEvent({required this.phase, required this.playerId, required this.mode});

  /// Which point of the transition this is.
  final PresentationLifecyclePhase phase;

  /// The player the transition belongs to.
  final PlayerId playerId;

  /// The presentation mode of the transition.
  final PresentationMode mode;

  @override
  String toString() => 'PresentationLifecycleEvent(${phase.name}, ${playerId.value}, ${mode.name})';
}

/// Signature of one lifecycle hook.
typedef PresentationLifecycleHook = Future<void> Function(PresentationLifecycleEvent event);

/// The four hooks a host can install around a presentation transition.
///
/// Hooks are awaited by the driver, but they are observational: a hook that
/// throws never aborts the transition and never reaches the `apply` caller —
/// the driver logs the failure and continues. A host that must veto a
/// transition decides that before requesting it, the same way every other
/// precondition is handled.
///
/// System-initiated state changes (the platform ends picture-in-picture on its
/// own, for example) have no "before" point; only `afterEnter`/`afterExit`
/// fire for them. `dispose` is teardown, not a transition, and fires nothing.
class PresentationLifecycleHooks {
  /// Groups the optional hooks a driver runs around a transition; unset hooks are skipped.
  const PresentationLifecycleHooks({this.beforeEnter, this.afterEnter, this.beforeExit, this.afterExit});

  /// Awaited before the driver starts entering the mode.
  final PresentationLifecycleHook? beforeEnter;

  /// Awaited once the mode is active.
  final PresentationLifecycleHook? afterEnter;

  /// Awaited before the driver starts leaving the mode.
  final PresentationLifecycleHook? beforeExit;

  /// Awaited once the mode is gone.
  final PresentationLifecycleHook? afterExit;

  /// Whether no hook is installed at all; drivers skip the whole path then.
  bool get isEmpty => beforeEnter == null && afterEnter == null && beforeExit == null && afterExit == null;
}
