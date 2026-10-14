import 'package:freezed_annotation/freezed_annotation.dart';

part 'fullscreen_state.freezed.dart';

/// Describes fullscreen lifecycle state.
///
/// This state only represents the logical fullscreen lifecycle.
///
/// It does not directly control:
///
/// - system UI
/// - orientation
/// - platform fullscreen APIs
///
/// Platform adapters are responsible for applying fullscreen changes.
@freezed
abstract class FullscreenState with _$FullscreenState {
  /// Creates a fullscreen state from its individual flags.
  const factory FullscreenState({
    /// Whether fullscreen is currently active.
    @Default(false) bool active,

    /// Whether fullscreen transition is running.
    @Default(false) bool transitioning,

    /// Whether fullscreen feature is available.
    @Default(true) bool available,

    /// Lifecycle generation.
    @Default(0) int generation,

    /// Last fullscreen error.
    String? error,
  }) = _FullscreenState;

  const FullscreenState._();

  /// Initial fullscreen state.
  factory FullscreenState.initial() => const FullscreenState();

  /// Whether fullscreen is active.
  bool get isFullscreen => active;

  /// Whether transition is running.
  bool get isTransitioning => transitioning;

  /// Whether fullscreen failed.
  bool get hasError => error != null;

  /// Whether fullscreen can be entered.
  bool get canEnter => available && !active && !transitioning;

  /// Whether fullscreen can be exited.
  bool get canExit => available && active && !transitioning;
}
