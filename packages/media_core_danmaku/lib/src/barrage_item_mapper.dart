import 'dart:ui' show Color, FontStyle, FontWeight, Offset;

import 'package:flame_barrage/flame_barrage.dart';

import 'package:media_core_danmaku/src/danmaku_message.dart';

/// Maps a normalized [DanmakuMessage] onto the rendering engine's item.
///
/// This is the whole of the pairing between the two packages: the session
/// owns transport, deduplication and filtering, and flame_barrage owns the
/// lanes, the paint and the caches. Nothing here measures text, picks a
/// track or decides how long a message stays up — every one of those is a
/// `BarrageConfig` knob, and re-declaring it here is how two vocabularies
/// for the same thing drift apart.
///
/// What a message *does* carry is per-message presentation intent (a
/// superchat's larger box, a platform's own color), which maps onto the
/// engine's per-item overrides. Anything the message leaves unsaid falls
/// back to the engine's config, so an ordinary chat line costs nothing
/// extra.
abstract final class BarrageItemMapper {
  /// Builds the engine item for [message].
  ///
  /// [priority] is passed through for lane contention; the engine, not this
  /// mapper, decides what a priority is worth.
  ///
  /// [at] places the message on a recorded stream's timeline, which the engine
  /// dispatches when the media reaches it. Leave it null for a live room, where
  /// a message belongs on screen the moment it arrives. `DanmakuMessage`
  /// carries no media offset — `sentAt` is a wall clock — so the caller that
  /// knows the timeline supplies it rather than this mapper guessing.
  static BarrageItem toItem(DanmakuMessage message, {Duration? at, int priority = 0}) {
    final style = message.style;
    final color = message.color;

    return BarrageItem(
      content: message.text,
      type: barrageTypeFor(style?.placement ?? DanmakuPlacement.scroll),
      at: at,
      priority: priority,
      // The engine never reads the id, but the host does: it is the handle
      // `retractWhere` takes a recalled message back by.
      id: _orNull(message.messageId),
      userId: _orNull(message.userId),
      userName: _orNull(message.userName),
      textColor: Color.fromARGB(255, color.r, color.g, color.b),
      fontSize: style?.fontSize,
      baseSpeed: style?.baseSpeed,
      fontWeight: style == null ? null : fontWeightFor(style.fontWeight),
      fontStyle: style == null
          ? null
          : style.italic
          ? FontStyle.italic
          : FontStyle.normal,
      fontFamily: style?.fontFamily,
      letterSpacing: style?.letterSpacing,
      opacity: style?.opacity,
      showStroke: style?.showStroke,
      strokeWidth: style?.strokeWidth,
      strokeColor: style == null ? null : Color(style.strokeColor),
      showShadow: style?.showShadow,
      shadowColor: style == null ? null : Color(style.shadowColor),
      shadowBlur: style?.shadowBlur,
      // The session model carries one scalar for the shadow; the engine
      // wants a vector. It is applied vertically, which is what a text
      // shadow means on every platform this has been looked at.
      shadowOffset: style == null ? null : Offset(0, style.shadowOffset),
      fixedDuration: style == null ? null : Duration(milliseconds: style.fixedDurationMs),
    );
  }

  /// The engine's anchor type for a placement.
  static BarrageType barrageTypeFor(DanmakuPlacement placement) {
    return switch (placement) {
      DanmakuPlacement.scroll => BarrageType.scroll,
      DanmakuPlacement.top => BarrageType.topFixed,
      DanmakuPlacement.bottom => BarrageType.bottomFixed,
    };
  }

  /// The nearest [FontWeight] to a numeric weight.
  ///
  /// Platforms send weights as numbers (400, 500, 700) and the engine takes
  /// Dart's enum, so the mapping rounds to the nearest hundred instead of
  /// collapsing everything to normal.
  static FontWeight fontWeightFor(int weight) {
    const weights = <FontWeight>[
      FontWeight.w100,
      FontWeight.w200,
      FontWeight.w300,
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
      FontWeight.w900,
    ];
    final index = ((weight - 100) / 100).round().clamp(0, weights.length - 1);
    return weights[index];
  }

  static String? _orNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
