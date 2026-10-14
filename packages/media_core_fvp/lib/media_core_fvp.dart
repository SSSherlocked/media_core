/// fvp (libmdk) backend adapter for media_core.
///
/// fvp ships libmdk, a current FFmpeg build with platform hardware decoders
/// first and FFmpeg/dav1d as software fallbacks. It reads streams the older
/// bundled engines drop, so an app registers it as the engine to recover a
/// source that only plays audio elsewhere.
///
/// ```dart
/// final registry = PlayerAdapterRegistry();
/// registerFvpRegistry(registry);
/// ```
///
/// The adapter owns its Flutter `Texture`; render it with [FvpVideoView] or
/// drive it from `FvpPlayerAdapter.textureListenable`.
library;

import 'package:media_core_fvp/src/fvp_video_view.dart' show FvpVideoView;

export 'package:fvp/fvp.dart';
// The engine this adapter is built on, re-exported so a host reaches it from
// its single dependency on this adapter: `package:fvp/mdk.dart` is the player
// API (`FvpPlayer`, `MediaInfo`, …) and `package:fvp/fvp.dart` the
// registration entry points. media_core's own public types use composed
// names (PlayerIdentity, PlayerTransportState, PlayerMediaType), so the
// engine's bare `Player`/`PlaybackState`/`MediaType` re-export without
// ambiguity.
export 'package:fvp/mdk.dart';
export 'package:media_core_fvp/src/fvp_adapter_factory.dart'
    show FvpAdapterFactory, kFvpPlayerBackendId, registerFvpFactory, registerFvpRegistry;
// Adapter, configs, factory, view.
export 'package:media_core_fvp/src/fvp_player_adapter.dart' show FvpPlayerAdapter;
export 'package:media_core_fvp/src/fvp_video_config.dart' show FvpVideoConfig;
export 'package:media_core_fvp/src/fvp_video_view.dart' show FvpVideoView;
