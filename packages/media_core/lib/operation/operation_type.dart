import 'package:media_core/operation/operation_state.dart' show OperationState;
import 'package:meta/meta.dart';

/// Describes the type of an operation.
///
/// [OperationType] is an immutable value object rather than a Dart enum.
/// Built-in operation types provide the stable core operation vocabulary,
/// while custom operation types allow extensions without modifying this class.
///
/// Operation type describes what an operation does.
///
/// It does not describe:
///
/// - whether the operation is running;
/// - whether the operation succeeded;
/// - whether the operation failed;
/// - how the operation is scheduled;
///
/// Those responsibilities belong to [OperationState], task management,
/// and policy layers.
@immutable
final class OperationType {
  /// Creates an operation type from JSON.
  factory OperationType.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('OperationType JSON value must be a String.');
    }

    return OperationType.fromValue(json);
  }

  /// Creates an operation type from a stable value.
  ///
  /// Built-in values return their canonical built-in instance.
  /// Unknown values become custom operation types.
  factory OperationType.fromValue(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Operation type cannot be empty.');
    }

    for (final type in values) {
      if (type.value == normalized) {
        return type;
      }
    }

    return OperationType.custom(normalized);
  }
  const OperationType._(this.value, this.name);

  /// Creates a custom operation type.
  factory OperationType.custom(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Operation type cannot be empty.');
    }

    return OperationType._(normalized, normalized);
  }

  /// Parses an operation type from a string.
  factory OperationType.parse(String value) = OperationType.fromValue;

  // ---------------------------------------------------------------------------
  // Built-in operation types
  // ---------------------------------------------------------------------------

  /// Opens a media source into the player.
  static const OperationType open = OperationType._('open', 'Open');

  /// Starts or resumes playback.
  static const OperationType play = OperationType._('play', 'Play');

  /// Pauses playback.
  static const OperationType pause = OperationType._('pause', 'Pause');

  /// Stops playback and releases the current source.
  static const OperationType stop = OperationType._('stop', 'Stop');

  /// Moves the playback position.
  static const OperationType seek = OperationType._('seek', 'Seek');

  /// Closes the player and discards the current source.
  static const OperationType close = OperationType._('close', 'Close');

  /// Initializes the playback engine.
  static const OperationType initialize = OperationType._('initialize', 'Initialize');

  /// Disposes the playback engine and its resources.
  static const OperationType dispose = OperationType._('dispose', 'Dispose');

  /// Prepares the current source for playback.
  static const OperationType prepare = OperationType._('prepare', 'Prepare');

  /// Loads a source into the player without starting it.
  static const OperationType load = OperationType._('load', 'Load');

  /// Reloads the current source from scratch.
  static const OperationType reload = OperationType._('reload', 'Reload');

  /// Changes the playback speed.
  static const OperationType setPlaybackRate = OperationType._('set_playback_rate', 'Set Playback Rate');

  /// Changes the output volume.
  static const OperationType setVolume = OperationType._('set_volume', 'Set Volume');

  /// Changes the mute state.
  static const OperationType setMute = OperationType._('set_mute', 'Set Mute');

  /// Enters fullscreen presentation.
  static const OperationType enterFullscreen = OperationType._('enter_fullscreen', 'Enter Fullscreen');

  /// Leaves fullscreen presentation.
  static const OperationType exitFullscreen = OperationType._('exit_fullscreen', 'Exit Fullscreen');

  /// Enters picture-in-picture presentation.
  static const OperationType enterPip = OperationType._('enter_pip', 'Enter PiP');

  /// Leaves picture-in-picture presentation.
  static const OperationType exitPip = OperationType._('exit_pip', 'Exit PiP');

  /// Starts recording the current playback.
  static const OperationType startRecording = OperationType._('start_recording', 'Start Recording');

  /// Captures a still frame from the current playback.
  static const OperationType captureScreenshot = OperationType._('capture_screenshot', 'Capture Screenshot');

  /// Stops the active recording.
  static const OperationType stopRecording = OperationType._('stop_recording', 'Stop Recording');

  /// Recovers the player after a failure.
  static const OperationType recover = OperationType._('recover', 'Recover');

  /// Switches to an alternative engine or source after a failure.
  static const OperationType fallback = OperationType._('fallback', 'Fallback');

  /// Re-executes a failed operation.
  static const OperationType retry = OperationType._('retry', 'Retry');

  /// Applies runtime options to the playback engine.
  static const OperationType applyEngineOptions = OperationType._('apply_engine_options', 'Apply Engine Options');

  // ---------------------------------------------------------------------------
  // Built-in values
  // ---------------------------------------------------------------------------

  static const Set<String> _builtInValues = <String>{
    'open',
    'play',
    'pause',
    'stop',
    'seek',
    'close',
    'initialize',
    'dispose',
    'prepare',
    'load',
    'reload',
    'set_playback_rate',
    'set_volume',
    'set_mute',
    'enter_fullscreen',
    'exit_fullscreen',
    'enter_pip',
    'exit_pip',
    'start_recording',
    'stop_recording',
    'capture_screenshot',
    'recover',
    'fallback',
    'retry',
    'apply_engine_options',
  };

  /// All built-in operation types.
  static const List<OperationType> values = <OperationType>[
    open,
    play,
    pause,
    stop,
    seek,
    close,
    initialize,
    dispose,
    prepare,
    load,
    reload,
    setPlaybackRate,
    setVolume,
    setMute,
    enterFullscreen,
    exitFullscreen,
    enterPip,
    exitPip,
    startRecording,
    stopRecording,
    captureScreenshot,
    recover,
    fallback,
    retry,
    applyEngineOptions,
  ];

  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------

  /// Stable machine-readable operation type value.
  final String value;

  /// Human-readable operation type name.
  final String name;

  /// Whether this is a built-in operation type.
  bool get isBuiltIn => _builtInValues.contains(value);

  /// Whether this is a custom operation type.
  bool get isCustom => !isBuiltIn;

  // ---------------------------------------------------------------------------
  // Predicates
  // ---------------------------------------------------------------------------

  /// Whether this is the [OperationType.open] operation.
  bool get isOpen => value == open.value;

  /// Whether this is the [OperationType.play] operation.
  bool get isPlay => value == play.value;

  /// Whether this is the [OperationType.pause] operation.
  bool get isPause => value == pause.value;

  /// Whether this is the [OperationType.stop] operation.
  bool get isStop => value == stop.value;

  /// Whether this is the [OperationType.seek] operation.
  bool get isSeek => value == seek.value;

  /// Whether this is the [OperationType.close] operation.
  bool get isClose => value == close.value;

  /// Whether this is the [OperationType.initialize] operation.
  bool get isInitialize => value == initialize.value;

  /// Whether this is the [OperationType.dispose] operation.
  bool get isDispose => value == dispose.value;

  /// Whether this is the [OperationType.prepare] operation.
  bool get isPrepare => value == prepare.value;

  /// Whether this is the [OperationType.load] operation.
  bool get isLoad => value == load.value;

  /// Whether this is the [OperationType.reload] operation.
  bool get isReload => value == reload.value;

  /// Whether this is the [OperationType.setPlaybackRate] operation.
  bool get isSetPlaybackRate => value == setPlaybackRate.value;

  /// Whether this is the [OperationType.setVolume] operation.
  bool get isSetVolume => value == setVolume.value;

  /// Whether this is the [OperationType.setMute] operation.
  bool get isSetMute => value == setMute.value;

  /// Whether this is the [OperationType.enterFullscreen] operation.
  bool get isEnterFullscreen => value == enterFullscreen.value;

  /// Whether this is the [OperationType.exitFullscreen] operation.
  bool get isExitFullscreen => value == exitFullscreen.value;

  /// Whether this is the [OperationType.enterPip] operation.
  bool get isEnterPip => value == enterPip.value;

  /// Whether this is the [OperationType.exitPip] operation.
  bool get isExitPip => value == exitPip.value;

  /// Whether this is the [OperationType.startRecording] operation.
  bool get isStartRecording => value == startRecording.value;

  /// Whether this is the [OperationType.stopRecording] operation.
  bool get isStopRecording => value == stopRecording.value;

  /// Whether this is the [OperationType.recover] operation.
  bool get isRecover => value == recover.value;

  /// Whether this is the [OperationType.fallback] operation.
  bool get isFallback => value == fallback.value;

  /// Whether this is the [OperationType.retry] operation.
  bool get isRetry => value == retry.value;

  // ---------------------------------------------------------------------------
  // Classification
  // ---------------------------------------------------------------------------

  /// Whether this operation affects playback state.
  bool get isPlaybackOperation {
    return isOpen || isPlay || isPause || isStop || isSeek || isClose || isPrepare || isLoad || isReload;
  }

  /// Whether this operation changes a player configuration.
  bool get isConfigurationOperation {
    return isSetPlaybackRate || isSetVolume || isSetMute;
  }

  /// Whether this operation affects presentation.
  bool get isPresentationOperation {
    return isEnterFullscreen || isExitFullscreen || isEnterPip || isExitPip;
  }

  /// Whether this operation affects recording.
  bool get isRecordingOperation {
    return isStartRecording || isStopRecording;
  }

  /// Whether this operation is related to recovery.
  bool get isRecoveryOperation {
    return isRecover || isFallback || isRetry;
  }

  /// Whether this operation initializes or disposes resources.
  bool get isLifecycleOperation {
    return isInitialize || isDispose;
  }

  // ---------------------------------------------------------------------------
  // Conversion
  // ---------------------------------------------------------------------------

  /// Returns the stable operation type value.
  String toValue() => value;

  /// Returns the stable operation type value for JSON serialization.
  String toJson() => value;

  /// Returns whether [value] is a valid operation type.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Returns whether [value] is a built-in operation type.
  static bool isBuiltInValue(String value) {
    return _builtInValues.contains(value.trim());
  }

  /// Attempts to parse an operation type.
  ///
  /// Returns `null` when [value] is empty or invalid.
  static OperationType? tryParse(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return OperationType.fromValue(normalized);
  }

  // ---------------------------------------------------------------------------
  // Value helpers
  // ---------------------------------------------------------------------------

  /// Creates a new operation type with a different value.
  ///
  /// The returned value is canonicalized through [OperationType.custom].
  OperationType copyWith(String value) {
    return OperationType.custom(value);
  }

  /// Whether this type has the same value as [other].
  bool isSameAs(OperationType other) {
    return this == other;
  }

  /// Whether this type has a different value from [other].
  bool isDifferentFrom(OperationType other) {
    return this != other;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is OperationType && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    return 'OperationType($value)';
  }
}
