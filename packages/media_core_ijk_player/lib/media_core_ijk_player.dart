/// ijkplayer (flv_lzc) backend adapter for media_core.
///
/// Supports FLV/H.265 and most popular protocols and codecs.
/// Android and iOS only.
library;

// The engine this adapter is built on, re-exported so a host reaches it from
// its single dependency on this adapter (`FijkPlayer`, `FijkView`, `FijkState`,
// `FijkValue`, …). No name clashes with media_core.
export 'package:flv_lzc/fijkplayer.dart';
export 'package:media_core_ijk_player/src/fijk_helper.dart';
export 'package:media_core_ijk_player/src/flv_lzc_player_adapter.dart';
export 'package:media_core_ijk_player/src/flv_lzc_player_adapter_factory.dart';
