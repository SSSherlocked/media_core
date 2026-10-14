import 'package:freezed_annotation/freezed_annotation.dart';

part 'floating_state.freezed.dart';

/// Represents floating window presentation lifecycle state.
///
/// This state only describes the logical floating window lifecycle.
///
/// It does not:
///
/// - create overlay windows
/// - manage window position
/// - control native window APIs
///
/// Platform adapters are responsible for applying
/// floating window operations.
@freezed
abstract class FloatingState with _$FloatingState {
  /// Creates a floating state from its individual flags.
  const factory FloatingState({
    /// Whether floating mode is active.
    @Default(false) bool active,

    /// Whether floating transition is running.
    @Default(false) bool transitioning,

    /// Whether floating window is supported.
    @Default(false) bool available,

    /// Whether floating mode is enabled.
    ///
    /// Controlled by:
    ///
    /// - user settings
    /// - application policy
    @Default(true) bool enabled,

    /// Lifecycle generation.
    ///
    /// Used to ignore stale async callbacks.
    @Default(0) int generation,

    /// Last floating error.
    String? error,
  }) = _FloatingState;

  const FloatingState._();

  /// Initial floating state.
  factory FloatingState.initial() {
    return const FloatingState();
  }

  /// Whether floating mode is active.
  bool get isFloating => active;

  /// Whether transition is running.
  bool get isTransitioning => transitioning;

  /// Whether state contains error.
  bool get hasError => error != null;

  /// Whether floating mode can enter.
  bool get canEnter => available && enabled && !active && !transitioning;

  /// Whether floating mode can exit.
  bool get canExit => active && !transitioning;

  /// Whether floating capability exists.
  bool get supportsFloating => available;
}
