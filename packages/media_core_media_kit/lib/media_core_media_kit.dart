/// media_kit backend adapter for media_core.
///
/// Before using this adapter, call [MediaKitPlayerAdapter.ensureInitialized]
/// (typically in `main`) to load the native media_kit libraries.
///
/// ```dart
/// void main() {
///   MediaKitPlayerAdapter.ensureInitialized();
///   runApp(const MyApp());
/// }
/// ```
///
/// The engines themselves are re-exported below: depending on this adapter is
/// enough to reach `Media`, `Video`, `VideoController`, `PlayerConfiguration`
/// and the rest of media_kit / media_kit_video. The native libraries come from
/// media_kit's own build hook, so no `media_kit_libs_*` package is involved.
library;

import 'package:media_core_media_kit/src/media_kit_player_adapter.dart' show MediaKitPlayerAdapter;

export 'package:media_core_media_kit/src/media_kit_adapter_factory.dart';
// Adapter, configs, factory, view.
export 'package:media_core_media_kit/src/media_kit_player_adapter.dart';
export 'package:media_core_media_kit/src/media_kit_video_view.dart';
export 'package:media_core_media_kit/src/utils/mpv_platform_profile.dart' show MpvPlatformProfile;
// Public utils: settings UIs, diagnostics, tuning.
export 'package:media_core_media_kit/src/utils/player_consts.dart' show PlayerConsts;
// The upstream packages this adapter is built on, re-exported so a host gets
// them from its single dependency on this adapter. media_core's own public
// types use composed names (PlayerIdentity, PlayerCoreState, ...), so the
// engines' bare `Player`/`PlayerState` re-export without ambiguity.
export 'package:media_kit/media_kit.dart';
export 'package:media_kit_video/media_kit_video.dart';
