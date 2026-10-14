import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:media_core/bug/fault_config.dart';
import 'package:media_core/bug/fault_injector.dart' show FaultInjector;
import 'package:media_core/bug/fault_type.dart';

/// Represents an actual fault injection event.
///
/// [FaultEvent] is an immutable record of a fault that occurred at runtime.
///
/// [FaultEvent] does not execute faults. It records the result of a fault
/// injection performed by [FaultInjector] or another runtime component.
final class FaultEvent extends Equatable {
  /// Records that the fault of [config] actually occurred, rejecting a [type] that disagrees with it.
  FaultEvent({
    required String faultId,
    required this.type,
    required this.config,
    DateTime? occurredAt,
    this.source,
    this.target,
    this.metadata,
  }) : faultId = _requireText(faultId, 'faultId'),
       occurredAt = occurredAt ?? clock.now() {
    if (type != config.type) {
      throw ArgumentError('FaultEvent type must match FaultConfig type.');
    }
  }

  /// Creates an event for an injected fault.
  factory FaultEvent.injected({
    required String faultId,
    required FaultConfig config,
    DateTime? occurredAt,
    String? source,
    String? target,
    Object? metadata,
  }) {
    return FaultEvent(
      faultId: faultId,
      type: config.type,
      config: config,
      occurredAt: occurredAt,
      source: source,
      target: target,
      metadata: metadata,
    );
  }

  /// Unique identifier of this fault event.
  final String faultId;

  /// Type of the injected fault.
  final FaultType type;

  /// Configuration used for the injection.
  final FaultConfig config;

  /// Time at which the fault occurred.
  final DateTime occurredAt;

  /// Optional source that triggered the fault.
  final String? source;

  /// Optional runtime target affected by the fault.
  final String? target;

  /// Optional runtime metadata associated with the event.
  final Object? metadata;

  /// Alias for [faultId].
  String get id => faultId;

  /// Alias for [occurredAt].
  DateTime get timestamp => occurredAt;

  /// Whether a source is present.
  bool get hasSource => source != null && source!.trim().isNotEmpty;

  /// Whether a target is present.
  bool get hasTarget => target != null && target!.trim().isNotEmpty;

  /// Whether metadata is present.
  bool get hasMetadata => metadata != null;

  /// Whether this is a delay fault.
  bool get isDelay => type.isDelay;

  /// Whether this is a timeout fault.
  bool get isTimeout => type.isTimeout;

  /// Whether this is a network-related fault.
  bool get isNetworkRelated => type.isNetworkRelated;

  /// Whether this is a source-related fault.
  bool get isSourceRelated => type.isSourceRelated;

  /// Whether this is an authentication-related fault.
  bool get isAuthenticationRelated => type.isAuthenticationRelated;

  /// Whether this is a backend-related fault.
  bool get isBackendRelated => type.isBackendRelated;

  /// Whether this is a decoder-related fault.
  bool get isDecoderRelated => type.isDecoderRelated;

  /// Whether this is a demuxer-related fault.
  bool get isDemuxerRelated => type.isDemuxerRelated;

  /// Whether this is a media-related fault.
  bool get isMediaRelated => type.isMediaRelated;

  /// Whether this is a playback-related fault.
  bool get isPlaybackRelated => type.isPlaybackRelated;

  /// Whether this is a renderer-related fault.
  bool get isRendererRelated => type.isRendererRelated;

  /// Whether this is an audio-related fault.
  bool get isAudioRelated => type.isAudioRelated;

  /// Whether this is a recording-related fault.
  bool get isRecordingRelated => type.isRecordingRelated;

  /// Whether this is a resource-related fault.
  bool get isResourceRelated => type.isResourceRelated;

  /// Whether this is a cancellation fault.
  bool get isCancellation => type.isCancellation;

  /// Whether this is an exception fault.
  bool get isException => type.isException;

  /// Whether this is a random fault.
  bool get isRandom => type.isRandom;

  /// Whether this is a chaos fault.
  bool get isChaos => type.isChaos;

  /// Whether this is a deterministic fault.
  bool get isDeterministic => type.isDeterministic;

  /// Whether this is a disruptive fault.
  bool get isDisruptive => type.isDisruptive;

  /// Whether this is a stress-related fault.
  bool get isStress => type.isStress;

  /// Whether this is a memory-pressure fault.
  bool get isMemoryPressure => type.isMemoryPressure;

  /// Returns metadata when it has the requested type.
  T? metadataAs<T>() {
    final value = metadata;

    if (value is T) {
      return value;
    }

    return null;
  }

  /// Creates a modified copy of this event.
  FaultEvent copyWith({
    String? faultId,
    FaultType? type,
    FaultConfig? config,
    DateTime? occurredAt,
    String? source,
    String? target,
    Object? metadata,
  }) {
    final nextConfig = config ?? this.config;
    final nextType = type ?? nextConfig.type;

    if (nextType != nextConfig.type) {
      throw ArgumentError('FaultEvent type must match FaultConfig type.');
    }

    return FaultEvent(
      faultId: faultId ?? this.faultId,
      type: nextType,
      config: nextConfig,
      occurredAt: occurredAt ?? this.occurredAt,
      source: source ?? this.source,
      target: target ?? this.target,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Replaces the event metadata.
  FaultEvent withMetadata(Object? value) {
    return FaultEvent(
      faultId: faultId,
      type: type,
      config: config,
      occurredAt: occurredAt,
      source: source,
      target: target,
      metadata: value,
    );
  }

  /// Removes the event metadata.
  FaultEvent withoutMetadata() {
    return FaultEvent(
      faultId: faultId,
      type: type,
      config: config,
      occurredAt: occurredAt,
      source: source,
      target: target,
    );
  }

  /// Associates this event with a source.
  FaultEvent withSource(String? value) {
    return FaultEvent(
      faultId: faultId,
      type: type,
      config: config,
      occurredAt: occurredAt,
      source: value,
      target: target,
      metadata: metadata,
    );
  }

  /// Removes the source association.
  FaultEvent withoutSource() {
    return FaultEvent(
      faultId: faultId,
      type: type,
      config: config,
      occurredAt: occurredAt,
      target: target,
      metadata: metadata,
    );
  }

  /// Associates this event with a target.
  FaultEvent withTarget(String? value) {
    return FaultEvent(
      faultId: faultId,
      type: type,
      config: config,
      occurredAt: occurredAt,
      source: source,
      target: value,
      metadata: metadata,
    );
  }

  /// Removes the target association.
  FaultEvent withoutTarget() {
    return FaultEvent(
      faultId: faultId,
      type: type,
      config: config,
      occurredAt: occurredAt,
      source: source,
      metadata: metadata,
    );
  }

  /// Whether this event occurred before [other].
  bool isBefore(FaultEvent other) {
    return occurredAt.isBefore(other.occurredAt);
  }

  /// Whether this event occurred after [other].
  bool isAfter(FaultEvent other) {
    return occurredAt.isAfter(other.occurredAt);
  }

  /// Returns the elapsed duration from this event to [time].
  Duration elapsedSince([DateTime? time]) {
    final reference = time ?? clock.now();

    return reference.difference(occurredAt);
  }

  /// Converts the event to a simple map representation.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'faultId': faultId,
      'type': type.toValue,
      'occurredAt': occurredAt.toIso8601String(),
      'source': source,
      'target': target,
      'metadata': metadata,
      'config': <String, Object?>{
        'type': config.type.toValue,
        'enabled': config.enabled,
        'probability': config.probability,
        'delay': config.delay?.inMicroseconds,
        'duration': config.duration?.inMicroseconds,
        'maxOccurrences': config.maxOccurrences,
        'message': config.message,
        'metadata': config.metadata,
      },
    };
  }

  static String _requireText(String value, String name) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty.');
    }

    return normalized;
  }

  @override
  List<Object?> get props => <Object?>[faultId, type, config, occurredAt, source, target, metadata];

  @override
  String toString() {
    return 'FaultEvent('
        'faultId: $faultId, '
        'type: ${type.value}, '
        'occurredAt: $occurredAt, '
        'source: $source, '
        'target: $target, '
        'metadata: $metadata'
        ')';
  }
}
