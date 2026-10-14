import 'package:equatable/equatable.dart';
import 'package:media_core/task/player_task.dart' show PlayerTask;

/// Describes the kind of work represented by a [PlayerTask].
///
/// [TaskType] is intentionally a value object rather than an enum so that
/// adapters and platform-specific implementations can introduce custom task
/// types without changing the core package.
///
/// Equality is determined by [value].
final class TaskType extends Equatable {
  /// Creates a task type from [value].
  ///
  /// Leading and trailing whitespace is removed.
  ///
  /// Throws [ArgumentError] when the value is empty.
  factory TaskType(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Task type cannot be empty.');
    }

    return TaskType.fromString(normalized);
  }

  /// Creates a task type from a string value.
  factory TaskType.fromValue(String value) {
    return TaskType(value);
  }

  /// Creates a custom task type.
  ///
  /// Use this when a task does not match one of the built-in types.
  factory TaskType.custom(String value) {
    return TaskType(value);
  }
  const TaskType._(this.value);

  /// Creates a task type from [value].
  ///
  /// Built-in values return their canonical instances.
  /// Unknown values become custom task types.
  factory TaskType.fromString(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Task type cannot be empty.');
    }

    switch (normalized) {
      case 'initialize':
        return initialize;

      case 'dispose':
        return dispose;

      case 'open':
        return open;

      case 'prepare':
        return prepare;

      case 'load':
        return load;

      case 'reload':
        return reload;

      case 'play':
        return play;

      case 'pause':
        return pause;

      case 'stop':
        return stop;

      case 'seek':
        return seek;

      case 'close':
        return close;

      case 'set_playback_rate':
        return setPlaybackRate;

      case 'set_volume':
        return setVolume;

      case 'set_mute':
        return setMute;

      case 'enter_fullscreen':
        return enterFullscreen;

      case 'exit_fullscreen':
        return exitFullscreen;

      case 'enter_pip':
        return enterPip;

      case 'exit_pip':
        return exitPip;

      case 'start_recording':
        return startRecording;

      case 'stop_recording':
        return stopRecording;

      case 'recover':
        return recover;

      case 'fallback':
        return fallback;

      case 'retry':
        return retry;

      default:
        return TaskType._(normalized);
    }
  }

  /// Creates a task type from a JSON value.
  factory TaskType.fromJson(Object? json) {
    if (json is! String) {
      throw ArgumentError.value(json, 'json', 'Task type must be a string.');
    }

    return TaskType.fromString(json);
  }

  // ---------------------------------------------------------------------------
  // Built-in task types
  // ---------------------------------------------------------------------------

  /// Initializes the player.
  static const TaskType initialize = TaskType._('initialize');

  /// Disposes the player.
  static const TaskType dispose = TaskType._('dispose');

  /// Opens a media source.
  static const TaskType open = TaskType._('open');

  /// Prepares a media source for playback.
  static const TaskType prepare = TaskType._('prepare');

  /// Loads media or metadata.
  static const TaskType load = TaskType._('load');

  /// Reloads the current media source.
  static const TaskType reload = TaskType._('reload');

  /// Starts playback.
  static const TaskType play = TaskType._('play');

  /// Pauses playback.
  static const TaskType pause = TaskType._('pause');

  /// Stops playback.
  static const TaskType stop = TaskType._('stop');

  /// Seeks to a specific position.
  static const TaskType seek = TaskType._('seek');

  /// Closes the current media source.
  static const TaskType close = TaskType._('close');

  /// Changes playback rate.
  static const TaskType setPlaybackRate = TaskType._('set_playback_rate');

  /// Changes volume.
  static const TaskType setVolume = TaskType._('set_volume');

  /// Changes mute state.
  static const TaskType setMute = TaskType._('set_mute');

  /// Enters fullscreen presentation.
  static const TaskType enterFullscreen = TaskType._('enter_fullscreen');

  /// Exits fullscreen presentation.
  static const TaskType exitFullscreen = TaskType._('exit_fullscreen');

  /// Enters picture-in-picture mode.
  static const TaskType enterPip = TaskType._('enter_pip');

  /// Exits picture-in-picture mode.
  static const TaskType exitPip = TaskType._('exit_pip');

  /// Starts recording.
  static const TaskType startRecording = TaskType._('start_recording');

  /// Stops recording.
  static const TaskType stopRecording = TaskType._('stop_recording');

  /// Performs recovery work.
  static const TaskType recover = TaskType._('recover');

  /// Performs source or engine fallback.
  static const TaskType fallback = TaskType._('fallback');

  /// Retries a failed task.
  static const TaskType retry = TaskType._('retry');

  /// All built-in task types.
  static const List<TaskType> builtIns = <TaskType>[
    initialize,
    dispose,
    open,
    prepare,
    load,
    reload,
    play,
    pause,
    stop,
    seek,
    close,
    setPlaybackRate,
    setVolume,
    setMute,
    enterFullscreen,
    exitFullscreen,
    enterPip,
    exitPip,
    startRecording,
    stopRecording,
    recover,
    fallback,
    retry,
  ];

  /// String representation of this task type.
  final String value;

  /// Human-readable task type name.
  String get name => value;

  // ---------------------------------------------------------------------------
  // Type checks
  // ---------------------------------------------------------------------------

  /// Whether this is one of the built-in task types.
  bool get isBuiltIn => _builtInValues.contains(value);

  /// Whether this is a custom task type.
  bool get isCustom => !isBuiltIn;

  /// Whether this is the [TaskType.initialize] task.
  bool get isInitialize => value == initialize.value;

  /// Whether this is the [TaskType.dispose] task.
  bool get isDispose => value == dispose.value;

  /// Whether this is the [TaskType.open] task.
  bool get isOpen => value == open.value;

  /// Whether this is the [TaskType.prepare] task.
  bool get isPrepare => value == prepare.value;

  /// Whether this is the [TaskType.load] task.
  bool get isLoad => value == load.value;

  /// Whether this is the [TaskType.reload] task.
  bool get isReload => value == reload.value;

  /// Whether this is the [TaskType.play] task.
  bool get isPlay => value == play.value;

  /// Whether this is the [TaskType.pause] task.
  bool get isPause => value == pause.value;

  /// Whether this is the [TaskType.stop] task.
  bool get isStop => value == stop.value;

  /// Whether this is the [TaskType.seek] task.
  bool get isSeek => value == seek.value;

  /// Whether this is the [TaskType.close] task.
  bool get isClose => value == close.value;

  /// Whether this is the [TaskType.setPlaybackRate] task.
  bool get isSetPlaybackRate => value == setPlaybackRate.value;

  /// Whether this is the [TaskType.setVolume] task.
  bool get isSetVolume => value == setVolume.value;

  /// Whether this is the [TaskType.setMute] task.
  bool get isSetMute => value == setMute.value;

  /// Whether this is the [TaskType.enterFullscreen] task.
  bool get isEnterFullscreen => value == enterFullscreen.value;

  /// Whether this is the [TaskType.exitFullscreen] task.
  bool get isExitFullscreen => value == exitFullscreen.value;

  /// Whether this is the [TaskType.enterPip] task.
  bool get isEnterPip => value == enterPip.value;

  /// Whether this is the [TaskType.exitPip] task.
  bool get isExitPip => value == exitPip.value;

  /// Whether this is the [TaskType.startRecording] task.
  bool get isStartRecording => value == startRecording.value;

  /// Whether this is the [TaskType.stopRecording] task.
  bool get isStopRecording => value == stopRecording.value;

  /// Whether this is the [TaskType.recover] task.
  bool get isRecover => value == recover.value;

  /// Whether this is the [TaskType.fallback] task.
  bool get isFallback => value == fallback.value;

  /// Whether this is the [TaskType.retry] task.
  bool get isRetry => value == retry.value;

  // ---------------------------------------------------------------------------
  // Built-in values
  // ---------------------------------------------------------------------------

  static const Set<String> _builtInValues = <String>{
    'initialize',
    'dispose',
    'open',
    'prepare',
    'load',
    'reload',
    'play',
    'pause',
    'stop',
    'seek',
    'close',
    'set_playback_rate',
    'set_volume',
    'set_mute',
    'enter_fullscreen',
    'exit_fullscreen',
    'enter_pip',
    'exit_pip',
    'start_recording',
    'stop_recording',
    'recover',
    'fallback',
    'retry',
  };

  /// Whether [value] represents a built-in task type.
  static bool isBuiltInValue(String value) {
    return _builtInValues.contains(value.trim());
  }

  /// Serializes this task type.
  ///
  /// The JSON representation is the string [value].
  String toJson() {
    return value;
  }

  /// Creates a copy with a different value.
  ///
  /// Built-in values are automatically converted to their canonical
  /// instances.
  TaskType copyWith(String value) {
    return TaskType(value);
  }

  // ---------------------------------------------------------------------------
  // Equatable
  // ---------------------------------------------------------------------------

  @override
  List<Object?> get props => <Object?>[value];

  // ---------------------------------------------------------------------------
  // Debugging
  // ---------------------------------------------------------------------------

  @override
  String toString() {
    return value;
  }
}
