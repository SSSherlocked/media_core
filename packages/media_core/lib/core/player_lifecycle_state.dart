import 'package:freezed_annotation/freezed_annotation.dart';

/// The lifecycle state of a player.
@JsonEnum()
enum PlayerLifecycleState {
  /// The player has not been initialized.
  idle,

  /// The player is running initialization.
  initializing,

  /// The player has been initialized and can be controlled.
  ready,

  /// The player is releasing its resources.
  disposing,

  /// The player has released its resources.
  disposed,
}
