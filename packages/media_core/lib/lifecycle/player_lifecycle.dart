import 'package:media_core/lifecycle/lifecycle_event.dart';
import 'package:media_core/lifecycle/lifecycle_snapshot.dart';

/// PlayerIdentity lifecycle abstraction.
abstract interface class PlayerLifecycle {
  /// The latest lifecycle snapshot.
  LifecycleSnapshot get snapshot;

  /// Stream of lifecycle transition events.
  Stream<LifecycleEvent> get events;

  /// Records that the player object was constructed.
  void create();

  /// Records that the backend engine was initialized.
  void initialize();

  /// Marks the player as the active, foreground surface.
  void activate();

  /// Records a pause that keeps the player active.
  void pause();

  /// Resumes paused playback.
  void resume();

  /// Releases the player from its surface (for example, when backgrounded).
  void deactivate();

  /// Detaches the player from its resources ahead of disposal.
  void detach();

  /// Disposes the player, after which no further transition is recorded.
  void dispose();
}
