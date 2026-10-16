import 'package:media_core/media_core.dart';

import 'video_player_adapter.dart';

const String kVideoPlayerBackendId = 'avplayer';

/// [PlayerAdapterFactory] that creates [VideoPlayerAdapter] instances.
final class VideoPlayerAdapterFactory implements PlayerAdapterFactory {
  const VideoPlayerAdapterFactory({this.capabilities = VideoPlayerAdapter.defaultCapabilities});

  final PlayerAdapterCapabilities capabilities;

  @override
  PlayerAdapter create(String id) => VideoPlayerAdapter(id: id, capabilities: capabilities);

  @override
  bool supports(String id) => id == kVideoPlayerBackendId;

  /// A registration entry for `PlayerKernel.registerBackend`, carrying the
  /// capabilities so selection works before an adapter exists.
  PlayerAdapterRegistration registration({int priority = 70}) {
    return PlayerAdapterRegistration(
      id: kVideoPlayerBackendId,
      factory: this,
      capabilities: capabilities,
      priority: priority,
    );
  }
}
