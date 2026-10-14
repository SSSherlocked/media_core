import 'package:flutter/foundation.dart' show immutable;

/// Identity of a memory consumer.
///
/// A value type rather than an enum, because the set of consumers is not closed:
/// a host that adds its own subsystem (a chat client, an image cache) needs an
/// account of its own without patching the framework.
///
/// The constants below name every consumer the framework itself reports. A
/// report is only as useful as the vocabulary in it, so a module that holds
/// memory *should* use its constant rather than a fresh string: that is what
/// makes "the wall is holding 2 GB" comparable across builds and bug reports.
@immutable
final class MemoryModule {
  /// Creates a memory module identity.
  const MemoryModule(this.name);

  /// Stable name used in reports and logs.
  final String name;

  /// The player kernel: open handles, one per player instance.
  static const MemoryModule kernel = MemoryModule('kernel');

  /// The player pool: active, warm and idle players.
  static const MemoryModule pool = MemoryModule('pool');

  /// Preloading: sources opened ahead of being watched.
  static const MemoryModule preload = MemoryModule('preload');

  /// Video surfaces, textures and frame buffers.
  static const MemoryModule renderer = MemoryModule('renderer');

  /// Caches: decoded metadata, thumbnails, resolved sources.
  static const MemoryModule cache = MemoryModule('cache');

  /// Danmaku: queued messages and overlay state.
  static const MemoryModule danmaku = MemoryModule('danmaku');

  /// Live playback: candidate lines and engine sweeps.
  static const MemoryModule live = MemoryModule('live');

  /// The swipe feed and the list: item lists and remembered positions.
  static const MemoryModule playback = MemoryModule('playback');

  /// The multi-cell wall: its cells and per-cell state.
  static const MemoryModule multiview = MemoryModule('multiview');

  /// Picture-in-picture.
  static const MemoryModule pip = MemoryModule('pip');

  /// The in-app small window.
  static const MemoryModule floating = MemoryModule('floating');

  /// Fullscreen.
  static const MemoryModule fullscreen = MemoryModule('fullscreen');

  /// Offline downloads: in-flight buffers and partial files.
  static const MemoryModule download = MemoryModule('download');

  /// Recording sessions and their output.
  static const MemoryModule recording = MemoryModule('recording');

  /// The host application itself.
  static const MemoryModule host = MemoryModule('host');

  @override
  bool operator ==(Object other) => other is MemoryModule && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}
