import 'package:freezed_annotation/freezed_annotation.dart';

part 'pip_state.freezed.dart';

/// Represents picture-in-picture lifecycle state.
///
/// This state only describes the logical PiP lifecycle.
///
/// It does not directly invoke platform PiP APIs.
///
/// Platform adapters are responsible for:
///
/// - entering PiP
/// - leaving PiP
/// - listening to native PiP callbacks
@freezed
abstract class PipState with _$PipState {
  /// Creates a PiP state from its individual flags.
  const factory PipState({
    /// Whether PiP is currently active.
    @Default(false) bool active,

    /// Whether a PiP transition is running.
    @Default(false) bool transitioning,

    /// Whether PiP is supported.
    @Default(false) bool available,

    /// Whether PiP is currently possible.
    ///
    /// Some platforms support PiP but temporarily
    /// cannot enter it.
    @Default(true) bool enabled,

    /// Lifecycle generation.
    ///
    /// Used to ignore stale async callbacks.
    @Default(0) int generation,

    /// Last PiP error.
    String? error,
  }) = _PipState;

  const PipState._();

  /// Initial PiP state.
  factory PipState.initial() {
    return const PipState();
  }

  /// Whether PiP is active.
  bool get isPip => active;

  /// Whether PiP transition is running.
  bool get isTransitioning => transitioning;

  /// Whether PiP failed.
  bool get hasError => error != null;

  /// Whether PiP can be entered.
  bool get canEnter => available && enabled && !active && !transitioning;

  /// Whether PiP can be exited.
  bool get canExit => active && !transitioning;

  /// Whether PiP capability exists.
  bool get supportsPip => available;
}
