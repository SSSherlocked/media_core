import 'package:equatable/equatable.dart';

/// Identifies a type of injected fault.
///
/// [FaultType] is a semantic value object. Equality is based on [value],
/// not object identity.
///
/// Custom fault types are supported so that applications can extend the
/// built-in fault taxonomy without modifying this package.
final class FaultType extends Equatable implements Comparable<FaultType> {
  const FaultType._(this.value, this.name);

  /// Creates a custom fault type.
  ///
  /// The [value] must be non-empty after trimming.
  factory FaultType.custom(String value, {String? name}) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Fault type value must not be empty.');
    }

    return FaultType._(normalized, name?.trim().isEmpty == true ? null : name?.trim());
  }

  /// Creates a fault type from its serialized value.
  ///
  /// Known values are mapped to their built-in instances.
  /// Unknown values become custom fault types.
  factory FaultType.fromValue(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Fault type value must not be empty.');
    }

    for (final type in builtIns) {
      if (type.value == normalized) {
        return type;
      }
    }

    return FaultType.custom(normalized);
  }

  /// Creates a fault type from JSON.
  factory FaultType.fromJson(Object? json) {
    if (json is! String) {
      throw const FormatException('FaultType JSON value must be a String.');
    }

    return FaultType.fromValue(json);
  }

  /// Attempts to parse a fault type.
  ///
  /// Returns `null` for a missing or blank value; any other value resolves
  /// through [FaultType.fromValue], which turns unknown values into custom
  /// fault types.
  static FaultType? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return FaultType.fromValue(value);
  }

  /// Whether the supplied value can represent a fault type.
  static bool isValid(String value) {
    return value.trim().isNotEmpty;
  }

  /// Whether the supplied value is a built-in fault type value.
  static bool isBuiltInValue(String value) {
    final normalized = value.trim();

    return builtIns.any((type) => type.value == normalized);
  }

  /// Unknown fault type.
  static const FaultType unknown = FaultType._('unknown', 'Unknown');

  /// Delays fault execution.
  static const FaultType delay = FaultType._('delay', 'Delay');

  /// Simulates a timeout.
  static const FaultType timeout = FaultType._('timeout', 'Timeout');

  /// Simulates unavailable network connectivity.
  static const FaultType networkUnavailable = FaultType._('network_unavailable', 'Network Unavailable');

  /// Simulates a network timeout.
  static const FaultType networkTimeout = FaultType._('network_timeout', 'Network Timeout');

  /// Simulates a connection failure.
  static const FaultType connectionFailure = FaultType._('connection_failure', 'Connection Failure');

  /// Simulates a source failure.
  static const FaultType sourceFailure = FaultType._('source_failure', 'Source Failure');

  /// Simulates an authentication failure.
  static const FaultType authenticationFailure = FaultType._('authentication_failure', 'Authentication Failure');

  /// Simulates a backend failure.
  static const FaultType backendFailure = FaultType._('backend_failure', 'Backend Failure');

  /// Simulates a decoder failure.
  static const FaultType decoderFailure = FaultType._('decoder_failure', 'Decoder Failure');

  /// Simulates a demuxer failure.
  static const FaultType demuxerFailure = FaultType._('demuxer_failure', 'Demuxer Failure');

  /// Simulates media corruption.
  static const FaultType mediaCorruption = FaultType._('media_corruption', 'Media Corruption');

  /// Simulates an unexpected playback stop.
  static const FaultType unexpectedStop = FaultType._('unexpected_stop', 'Unexpected Stop');

  /// Simulates a renderer failure.
  static const FaultType rendererFailure = FaultType._('renderer_failure', 'Renderer Failure');

  /// Simulates a geometry failure.
  static const FaultType geometryFailure = FaultType._('geometry_failure', 'Geometry Failure');

  /// Simulates an audio failure.
  static const FaultType audioFailure = FaultType._('audio_failure', 'Audio Failure');

  /// Simulates a recording failure.
  static const FaultType recordingFailure = FaultType._('recording_failure', 'Recording Failure');

  /// Simulates resource exhaustion.
  static const FaultType resourceExhaustion = FaultType._('resource_exhaustion', 'Resource Exhaustion');

  /// Simulates memory pressure.
  static const FaultType memoryPressure = FaultType._('memory_pressure', 'Memory Pressure');

  /// Simulates cancellation.
  static const FaultType cancellation = FaultType._('cancellation', 'Cancellation');

  /// Injects a generic exception.
  static const FaultType exception = FaultType._('exception', 'Exception');

  /// Represents a randomly selected fault.
  static const FaultType random = FaultType._('random', 'Random');

  /// Represents a chaotic fault.
  static const FaultType chaos = FaultType._('chaos', 'Chaos');

  /// All built-in fault types.
  static const List<FaultType> builtIns = <FaultType>[
    unknown,
    delay,
    timeout,
    networkUnavailable,
    networkTimeout,
    connectionFailure,
    sourceFailure,
    authenticationFailure,
    backendFailure,
    decoderFailure,
    demuxerFailure,
    mediaCorruption,
    unexpectedStop,
    rendererFailure,
    geometryFailure,
    audioFailure,
    recordingFailure,
    resourceExhaustion,
    memoryPressure,
    cancellation,
    exception,
    random,
    chaos,
  ];

  /// Returns a built-in fault type by value.
  static FaultType builtIn(String value) {
    final normalized = value.trim();

    for (final type in builtIns) {
      if (type.value == normalized) {
        return type;
      }
    }

    throw ArgumentError.value(value, 'value', 'Unknown built-in fault type.');
  }

  /// Stable serialized value.
  final String value;

  /// Optional human-readable name.
  final String? name;

  /// Returns the raw serialized value.
  String get rawValue => value;

  /// Returns the serialized value.
  String get toValue => value;

  /// Returns the JSON representation.
  String toJson() => value;

  /// Whether this is a built-in fault type.
  bool get isBuiltIn => builtIns.any((type) => type.value == value);

  /// Whether this is a custom fault type.
  bool get isCustom => !isBuiltIn;

  /// Whether this is the unknown fault type.
  bool get isUnknown => value == unknown.value;

  /// Whether this is a delay fault.
  bool get isDelay => value == delay.value;

  /// Whether this is a timeout fault.
  bool get isTimeout => value == timeout.value;

  /// Whether this is related to networking.
  bool get isNetworkRelated =>
      value == networkUnavailable.value || value == networkTimeout.value || value == connectionFailure.value;

  /// Whether this is related to a media source.
  bool get isSourceRelated => value == sourceFailure.value;

  /// Whether this is related to authentication.
  bool get isAuthenticationRelated => value == authenticationFailure.value;

  /// Whether this is related to the playback backend.
  bool get isBackendRelated => value == backendFailure.value;

  /// Whether this is related to decoding.
  bool get isDecoderRelated => value == decoderFailure.value;

  /// Whether this is related to demuxing.
  bool get isDemuxerRelated => value == demuxerFailure.value;

  /// Whether this is related to media processing.
  bool get isMediaRelated => value == mediaCorruption.value;

  /// Whether this is related to playback.
  bool get isPlaybackRelated =>
      value == unexpectedStop.value ||
      value == backendFailure.value ||
      value == decoderFailure.value ||
      value == demuxerFailure.value ||
      value == mediaCorruption.value;

  /// Whether this is related to rendering.
  bool get isRendererRelated => value == rendererFailure.value || value == geometryFailure.value;

  /// Whether this is related to audio.
  bool get isAudioRelated => value == audioFailure.value;

  /// Whether this is related to recording.
  bool get isRecordingRelated => value == recordingFailure.value;

  /// Whether this is related to resource exhaustion.
  bool get isResourceRelated => value == resourceExhaustion.value || value == memoryPressure.value;

  /// Whether this represents cancellation.
  bool get isCancellation => value == cancellation.value;

  /// Whether this represents a generic exception.
  bool get isException => value == exception.value;

  /// Whether this represents random fault selection.
  bool get isRandom => value == random.value;

  /// Whether this represents chaos fault injection.
  bool get isChaos => value == chaos.value;

  /// Whether this fault type is deterministic.
  ///
  /// Built-in fault types are deterministic unless they explicitly
  /// represent random or chaos behavior.
  bool get isDeterministic => !isRandom && !isChaos;

  /// Whether this fault is considered disruptive.
  bool get isDisruptive =>
      isCancellation ||
      isException ||
      isBackendRelated ||
      isDecoderRelated ||
      isDemuxerRelated ||
      isMediaRelated ||
      isRendererRelated ||
      isAudioRelated ||
      isRecordingRelated ||
      isResourceRelated ||
      value == unexpectedStop.value;

  /// Whether this fault is considered stress-oriented.
  bool get isStress =>
      isResourceRelated ||
      isMemoryPressure ||
      value == networkUnavailable.value ||
      value == networkTimeout.value ||
      value == connectionFailure.value;

  /// Whether this fault represents memory pressure.
  bool get isMemoryPressure => value == memoryPressure.value;

  /// Creates a modified copy.
  FaultType copyWith({String? value, String? name}) {
    return FaultType.custom(value ?? this.value, name: name ?? this.name);
  }

  /// Returns whether this type has the same semantic value as [other].
  bool isSameAs(FaultType other) => this == other;

  /// Returns whether this type has a different semantic value from [other].
  bool isDifferentFrom(FaultType other) => this != other;

  @override
  int compareTo(FaultType other) {
    return value.compareTo(other.value);
  }

  @override
  List<Object?> get props => <Object?>[value, name];

  @override
  String toString() {
    if (name == null || name!.isEmpty) {
      return value;
    }

    return '$value($name)';
  }
}
