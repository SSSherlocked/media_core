/// Playback command type.
///
/// Used for:
///
/// - logging
/// - analytics
/// - debugging
/// - command filtering
///
/// Does not:
///
/// - store command data
/// - execute commands
enum PlaybackCommandType {
  /// No operation.
  idle,

  /// Start playback.
  play,

  /// Pause playback.
  pause,

  /// Stop playback.
  stop,

  /// Buffering state changed.
  buffering,

  /// Position update.
  position,

  /// Duration update.
  duration,

  /// Seek request.
  seek,

  /// Volume update.
  volume,

  /// Playback rate update.
  rate;

  /// Whether command changes playback state.
  bool get isStateChange {
    switch (this) {
      case PlaybackCommandType.idle:
      case PlaybackCommandType.position:
      case PlaybackCommandType.duration:
        return false;

      case PlaybackCommandType.play:
      case PlaybackCommandType.pause:
      case PlaybackCommandType.stop:
      case PlaybackCommandType.buffering:
      case PlaybackCommandType.seek:
      case PlaybackCommandType.volume:
      case PlaybackCommandType.rate:
        return true;
    }
  }

  /// Whether command is transport control.
  bool get isTransport {
    switch (this) {
      case PlaybackCommandType.play:
      case PlaybackCommandType.pause:
      case PlaybackCommandType.stop:
        return true;

      case PlaybackCommandType.idle:
      case PlaybackCommandType.buffering:
      case PlaybackCommandType.position:
      case PlaybackCommandType.duration:
      case PlaybackCommandType.seek:
      case PlaybackCommandType.volume:
      case PlaybackCommandType.rate:
        return false;
    }
  }

  /// Whether command carries timeline data.
  bool get isTimeline {
    switch (this) {
      case PlaybackCommandType.position:
      case PlaybackCommandType.duration:
      case PlaybackCommandType.seek:
        return true;

      case PlaybackCommandType.idle:
      case PlaybackCommandType.play:
      case PlaybackCommandType.pause:
      case PlaybackCommandType.stop:
      case PlaybackCommandType.buffering:
      case PlaybackCommandType.volume:
      case PlaybackCommandType.rate:
        return false;
    }
  }

  /// Parse from string.
  static PlaybackCommandType fromName(String value) {
    return PlaybackCommandType.values.firstWhere((item) => item.name == value, orElse: () => PlaybackCommandType.idle);
  }

  /// Convert to json value.
  String get value => name;
}
