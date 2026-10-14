part of 'media_kit_player_adapter.dart';

/// The mpv commands that replace a list option's entries.
///
/// A list option cannot be written the way scalars are, and it cannot be
/// written as one comma-joined string either. Both were observed on Windows
/// with `glsl-shaders`:
///
/// - `NativePlayer.setProperty` (`mpv_set_property_string`) with
///   `"a.glsl,b.glsl"` makes mpv open ONE file literally named
///   `a.glsl,b.glsl` — on Windows that fails as an over-long path
///   (`Invalid argument`) and reaches the host as a playback error for
///   whatever source is open.
/// - `change-list <key> set "<a.glsl,b.glsl>"` does the same: this mpv build
///   took the value as a single entry as well (the log proves it — the very
///   joined path is what `file/error` tried to open).
///
/// So each entry travels as its own `append`, and the whole command list
/// starts with `clr` to keep the replace semantics the caller asked for. One
/// argument per entry needs no separator parsing at all, and it also survives
/// an install directory whose path contains a comma.
List<List<String>> mpvListOptionCommands(String key, List<Object?> entries) {
  final commands = <List<String>>[
    <String>['change-list', key, 'clr', ''],
  ];

  for (final entry in entries) {
    commands.add(<String>['change-list', key, 'append', if (entry == null) '' else '$entry']);
  }

  return commands;
}

/// Engine creation: the caller's native configurations, verbatim.
///
/// The adapter normalises nothing here. `PlayerConfiguration` and
/// `VideoControllerConfiguration` are media_kit's own types — whatever the
/// caller passed is what the engine receives, so every tuning value
/// belongs to the caller. Runtime changes travel as engine options (mpv
/// properties) through `onApplyEngineOptions` instead.
extension _MediaKitEngineConfig on MediaKitPlayerAdapter {
  mkv.VideoController _buildVideoController() {
    return mkv.VideoController(
      player,
      configuration: videoControllerConfiguration ?? const mkv.VideoControllerConfiguration(),
    );
  }

  /// Writes one mpv property and reports whether the engine took it.
  ///
  /// A `null` platform means there is no native surface at all (web, or a
  /// player that has not been created yet) and a rejected property is the
  /// engine's own answer. Both have to reach the caller: an option
  /// reported as applied while it was dropped leaves the host believing
  /// its tuning took effect, which is the failure this class exists to
  /// avoid.
  Future<bool> _setNativeProperty(String name, String value) async {
    final native = _player?.platform;

    if (native == null) return false;

    try {
      await (native as dynamic).setProperty(name, value);
      return true;
    } on Object catch (error) {
      MediaCoreLog.warning(LogCategory.player, 'mpv rejected property "$name": $error', error: error);
      return false;
    }
  }

  /// Writes one engine option in the shape its value has.
  ///
  /// This is the only place a value's type is interpreted, so the two call
  /// sites that deliver options — the stash replay at engine creation and
  /// the live apply — cannot drift into different dialects. A [List] value
  /// is a list option and travels as a command; everything else is the
  /// scalar property write.
  Future<bool> _applyNativeOption(EngineOption option) {
    final value = option.value;

    if (value is List) {
      return _applyNativeListOption(option.key, value);
    }

    return _setNativeProperty(option.key, _mpvOptionValue(value));
  }

  /// Replaces a list option entry by entry, then reports what the engine
  /// ended up holding.
  ///
  /// The read-back is the point, not decoration: `change-list` accepts a
  /// value mpv may keep as one entry, so "the command did not throw" says
  /// nothing about the chain being mounted. mpv exposes a list option's
  /// length as `<key>-count`, and that number is the observable difference
  /// between a mounted chain and a silently dropped one.
  Future<bool> _applyNativeListOption(String key, List<Object?> entries) async {
    var applied = true;

    for (final command in mpvListOptionCommands(key, entries)) {
      applied = await _runNativeCommand(command) && applied;
    }

    // The read-back costs one more native round trip for the whole option and
    // exists only to put the mounted count in the log. Logging defaults to
    // `nothing`, so a shipping build paid that round trip for a line nobody
    // recorded — per list option, on every apply. Ask the logger first; the
    // emitted set is unchanged, because this is the same predicate `log` uses.
    if (MediaCoreLog.isEnabled(LogCategory.renderer, LogLevel.info)) {
      MediaCoreLog.info(
        LogCategory.renderer,
        'mpv list option "$key" mounted ${await _readNativeProperty('$key-count') ?? '<unknown>'} of '
        '${entries.length} entries',
        fields: <String, Object?>{'entries': entries.length},
      );
    }

    return applied;
  }

  /// Reads one mpv property as text, or null when the engine has no answer.
  Future<String?> _readNativeProperty(String name) async {
    final native = _player?.platform;

    if (native == null) return null;

    try {
      final value = await (native as dynamic).getProperty(name) as String?;
      return value;
    } on Object catch (error) {
      // Not every list option carries a `-count`, and this write is already
      // decided by the commands above — the read-back only makes the answer
      // visible in the log.
      MediaCoreLog.debug(LogCategory.renderer, 'mpv property "$name" was not readable: $error');
      return null;
    }
  }

  /// Runs one mpv command verbatim and reports whether the engine took it.
  ///
  /// The same honesty rule as [_setNativeProperty]: a command the engine
  /// refused is `false`, so the caller reports the option as unsupported
  /// instead of claiming the tuning landed.
  Future<bool> _runNativeCommand(List<String> command) async {
    final native = _player?.platform;

    if (native == null) return false;

    try {
      await (native as dynamic).command(command);
      return true;
    } on Object catch (error) {
      MediaCoreLog.warning(LogCategory.player, 'mpv rejected command "${command.join(' ')}": $error', error: error);
      return false;
    }
  }
}
