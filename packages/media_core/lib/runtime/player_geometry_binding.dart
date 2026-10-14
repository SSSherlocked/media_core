import 'dart:async';

import 'package:media_core/adapter/player_adapter.dart';
import 'package:media_core/adapter/player_adapter_event.dart';
import 'package:media_core/geometry/geometry_controller.dart';
import 'package:media_core/geometry/video_size.dart';

/// Binds player adapter events to the geometry controller.
///
/// Responsibilities:
///
/// - listen to player adapter events
/// - convert video size events into [VideoSize]
/// - update [GeometryController]
///
/// It does not:
///
/// - calculate orientation
/// - calculate aspect ratio
/// - perform layout
/// - access platform APIs
/// - control playback
final class PlayerGeometryBinding {
  /// Creates a binding that subscribes to [adapter]'s events and feeds the
  /// resulting video sizes into [geometry].
  PlayerGeometryBinding({required PlayerAdapter adapter, required GeometryController geometry})
    : _adapter = adapter,
      _geometry = geometry {
    _subscription = _adapter.events.listen(_onEvent);
  }

  final PlayerAdapter _adapter;
  final GeometryController _geometry;

  late final StreamSubscription<PlayerAdapterEvent> _subscription;

  void _onEvent(PlayerAdapterEvent event) {
    switch (event) {
      case PlayerAdapterVideoSizeChanged():
        _geometry.updateVideoSize(VideoSize(width: event.width, height: event.height));

      case PlayerAdapterVideoReconfigured():
        // The adapter does not provide the new geometry with this event.
        // Wait for the next videoSizeChanged event.
        break;

      default:
        break;
    }
  }

  /// Cancels the adapter event subscription, ending the binding.
  Future<void> dispose() async {
    await _subscription.cancel();
  }
}
