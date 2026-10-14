import 'package:equatable/equatable.dart';

/// Runtime lifecycle state.
final class LifecycleState extends Equatable {
  /// Creates a state from its individual transition flags.
  const LifecycleState({
    this.created = false,
    this.initialized = false,
    this.active = false,
    this.paused = false,
    this.inactive = false,
    this.detached = false,
    this.disposing = false,
    this.disposed = false,
  });

  /// Whether the player object has been constructed.
  final bool created;

  /// Whether the backend engine has been initialized.
  final bool initialized;

  /// Whether the player is bound to a foreground surface and able to play.
  final bool active;

  /// Whether playback is paused while the player remains active.
  final bool paused;

  /// Whether the player has been released from its surface (for example, backgrounded).
  final bool inactive;

  /// Whether the player has been detached from its resources ahead of disposal.
  final bool detached;

  /// Whether disposal has started but not finished.
  final bool disposing;

  /// Whether disposal has completed; a terminal, one-way flag.
  final bool disposed;

  /// Whether the player has not yet been disposed.
  bool get isAlive {
    return !disposed;
  }

  /// Whether the player is initialized and not tearing down.
  bool get isReady {
    return initialized && !disposing && !disposed;
  }

  /// Whether the player has reached the terminal disposed state.
  bool get isTerminal {
    return disposed;
  }

  /// Copies the state, replacing whichever flags are provided.
  LifecycleState copyWith({
    bool? created,
    bool? initialized,
    bool? active,
    bool? paused,
    bool? inactive,
    bool? detached,
    bool? disposing,
    bool? disposed,
  }) {
    return LifecycleState(
      created: created ?? this.created,
      initialized: initialized ?? this.initialized,
      active: active ?? this.active,
      paused: paused ?? this.paused,
      inactive: inactive ?? this.inactive,
      detached: detached ?? this.detached,
      disposing: disposing ?? this.disposing,
      disposed: disposed ?? this.disposed,
    );
  }

  /// Marks the player as constructed.
  LifecycleState markCreated() {
    return copyWith(created: true);
  }

  /// Marks the backend engine as initialized.
  LifecycleState markInitialized() {
    return copyWith(initialized: true);
  }

  /// Makes the player the active, foreground surface, clearing paused/inactive/detached.
  LifecycleState markActive() {
    return copyWith(active: true, paused: false, inactive: false, detached: false);
  }

  /// Records a pause that keeps the player active but stops playback.
  LifecycleState markPaused() {
    return copyWith(active: false, paused: true, inactive: false);
  }

  /// Records release from the surface, clearing active and paused.
  LifecycleState markInactive() {
    return copyWith(active: false, paused: false, inactive: true);
  }

  /// Marks the player detached from its resources, clearing the playing flags.
  LifecycleState markDetached() {
    return copyWith(detached: true, active: false, paused: false, inactive: false);
  }

  /// Marks disposal as started, clearing the playing flags.
  LifecycleState markDisposing() {
    return copyWith(disposing: true, active: false, paused: false, inactive: false);
  }

  /// Marks disposal complete and the state terminal, clearing every other flag.
  LifecycleState markDisposed() {
    return copyWith(disposing: false, disposed: true, active: false, paused: false, inactive: false);
  }

  @override
  List<Object?> get props => [created, initialized, active, paused, inactive, detached, disposing, disposed];
}
