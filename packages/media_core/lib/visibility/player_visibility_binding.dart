import 'dart:async';

import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/visibility/visibility_controller.dart';
import 'package:media_core/visibility/visibility_event.dart';

/// Wires a [VisibilityController] to a [PlayerHandle]'s lifecycle.
///
/// This is the bridge between the visibility module and playback: when
/// the player's page leaves the viewport or is occluded, playback pauses;
/// when it becomes visible again, playback resumes — but only if the
/// visibility binding itself paused it. A pause the user made before the
/// page was hidden is never undone by scrolling back.
///
/// ```dart
/// final binding = PlayerVisibilityBinding(handle, visibility);
/// visibility.update(scrollRatio);   // hidden → pause, visible → resume
/// ...
/// await binding.dispose();
/// ```
final class PlayerVisibilityBinding {
  /// Binds a [PlayerHandle] to a [VisibilityController] so that playback
  /// pauses while the player is off screen and resumes when it returns.
  PlayerVisibilityBinding(this._handle, this._visibility) {
    _subscription = _visibility.events.listen(_onVisibilityEvent);
  }

  final PlayerHandle _handle;
  final VisibilityController _visibility;

  late final StreamSubscription<void> _subscription;

  /// Whether this binding paused playback because the player went
  /// invisible — and therefore owns the resume.
  bool _pausedByInvisibility = false;

  /// Whether the binding is still active.
  bool _disposed = false;

  /// Whether the last hidden transition was answered by this binding.
  bool get pausedByInvisibility => _pausedByInvisibility;

  void _onVisibilityEvent(VisibilityEvent event) {
    if (_disposed || _handle.disposed) {
      return;
    }

    switch (event.type) {
      case VisibilityEventType.hidden:
      case VisibilityEventType.disappeared:
        _pauseForInvisibility();

      case VisibilityEventType.visible:
      case VisibilityEventType.appeared:
        _resumeAfterInvisibility();

      case VisibilityEventType.changed:
        // `setViewport(value: false)` and `setOccluded(value: true)` publish
        // `changed`, and both mean "the player is not on screen any more".
        // Acting on the event *type* alone would leave a scrolled-away or
        // covered player playing, which is the whole reason this binding
        // exists — so the decision is made from the controller's state instead.
        final state = _visibility.snapshot.state;

        if (!state.inViewport || state.occluded || !state.visible) {
          _pauseForInvisibility();
        } else {
          _resumeAfterInvisibility();
        }
    }
  }

  void _pauseForInvisibility() {
    if (_pausedByInvisibility || !_handle.isPlaying) {
      return;
    }

    _pausedByInvisibility = true;

    unawaited(_handle.pause());
  }

  void _resumeAfterInvisibility() {
    if (!_pausedByInvisibility) {
      return;
    }

    _pausedByInvisibility = false;

    unawaited(_handle.play());
  }

  /// Stops following visibility.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _subscription.cancel();
  }
}
