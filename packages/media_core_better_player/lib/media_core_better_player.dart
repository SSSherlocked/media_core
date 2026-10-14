/// better_player backend adapter for media_core.
///
/// Supports network (HTTP/HTTPS/HLS/DASH) and file sources. Asset sources
/// are not supported: better_player_plus exposes no asset data-source type.
library;

// The engine this adapter is built on, re-exported so a host reaches it from
// its single dependency on this adapter. No name clashes with media_core.
export 'package:better_player_plus/better_player_plus.dart';
export 'package:media_core_better_player/src/better_player_adapter.dart';
export 'package:media_core_better_player/src/better_player_adapter_factory.dart';
