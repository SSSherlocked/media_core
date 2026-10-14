/// Danmaku sessions: platform-agnostic transport contract, message
/// normalization, backlog/duplicate gating, content filtering and the session
/// lifecycle that keeps an old socket from writing into a new room.
///
/// Platform protocols live in adapter packages and implement
/// [DanmakuTransport]. Painting is not this package's job either: it hands
/// accepted messages to flame_barrage through [FlameBarrageSink], which owns
/// the lanes, the pacing and the caches, and a host that renders somewhere
/// else implements [DanmakuSink] instead.
library;

import 'package:media_core_danmaku/media_core_danmaku.dart' show DanmakuSink, DanmakuTransport, FlameBarrageSink;

export 'package:media_core_danmaku/src/barrage_item_mapper.dart';
export 'package:media_core_danmaku/src/danmaku_config.dart';
export 'package:media_core_danmaku/src/danmaku_controller.dart';
export 'package:media_core_danmaku/src/danmaku_failure.dart';
export 'package:media_core_danmaku/src/danmaku_fanout_sink.dart';
export 'package:media_core_danmaku/src/danmaku_filter_policy.dart';
export 'package:media_core_danmaku/src/danmaku_message.dart';
export 'package:media_core_danmaku/src/danmaku_message_gate.dart';
export 'package:media_core_danmaku/src/danmaku_overlay_session.dart';
export 'package:media_core_danmaku/src/danmaku_player_binding.dart';
export 'package:media_core_danmaku/src/danmaku_repeated_filter.dart';
export 'package:media_core_danmaku/src/danmaku_session_state.dart';
export 'package:media_core_danmaku/src/danmaku_similarity_filter.dart';
export 'package:media_core_danmaku/src/danmaku_sink.dart';
export 'package:media_core_danmaku/src/danmaku_transport.dart';
export 'package:media_core_danmaku/src/flame_barrage_sink.dart';
