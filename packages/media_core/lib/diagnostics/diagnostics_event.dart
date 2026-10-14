import 'package:equatable/equatable.dart';
import 'package:media_core/diagnostics/network_snapshot.dart';
import 'package:media_core/diagnostics/performance_sample.dart';
import 'package:media_core_memory/media_core_memory.dart';

/// Represents one diagnostic event produced by the diagnostics subsystem.
///
/// A [DiagnosticsEvent] describes a meaningful change or measurement that
/// higher-level components may observe without depending directly on an
/// individual diagnostic monitor.
///
/// Responsibilities:
///
/// - identify the diagnostic event type
/// - carry the event timestamp
/// - optionally carry a memory snapshot
/// - optionally carry a network snapshot
/// - optionally carry a performance sample
/// - optionally carry structured diagnostic values
///
/// It does not:
///
/// - collect diagnostic measurements
/// - dispatch events to listeners
/// - decide which events should be emitted
///
/// Those responsibilities belong to:
///
/// - DiagnosticsManager
/// - diagnostic monitors
/// - PlayerEventBus
sealed class DiagnosticsEvent extends Equatable {
  /// Creates a diagnostics event.
  const DiagnosticsEvent({required this.timestamp});

  /// Time at which this diagnostic event was created.
  final DateTime timestamp;

  /// Converts this event into a serializable map.
  Map<String, Object?> toMap();

  @override
  List<Object?> get props => [timestamp];
}

/// Represents a newly collected performance measurement.
///
/// A [PerformanceSampleEvent] is emitted when the diagnostics subsystem
/// records a performance sample.
final class PerformanceSampleEvent extends DiagnosticsEvent {
  /// Creates a performance sample event.
  const PerformanceSampleEvent({required super.timestamp, required this.sample});

  /// Performance measurement associated with the event.
  final PerformanceSample sample;

  @override
  Map<String, Object?> toMap() {
    return {'type': 'performanceSample', 'timestamp': timestamp.toIso8601String(), 'sample': sample.toMap()};
  }

  @override
  List<Object?> get props => [...super.props, sample];
}

/// Represents a newly collected memory measurement.
///
/// A [MemorySnapshotEvent] is emitted when the diagnostics subsystem records
/// a memory snapshot.
final class MemorySnapshotEvent extends DiagnosticsEvent {
  /// Creates a memory snapshot event.
  const MemorySnapshotEvent({required super.timestamp, required this.snapshot});

  /// Memory measurement associated with the event.
  final MemorySnapshot snapshot;

  @override
  Map<String, Object?> toMap() {
    return {'type': 'memorySnapshot', 'timestamp': timestamp.toIso8601String(), 'snapshot': snapshot.toMap()};
  }

  @override
  List<Object?> get props => [...super.props, snapshot];
}

/// Represents a newly collected network measurement.
///
/// A [NetworkSnapshotEvent] is emitted when the diagnostics subsystem records
/// a network snapshot.
final class NetworkSnapshotEvent extends DiagnosticsEvent {
  /// Creates a network snapshot event.
  const NetworkSnapshotEvent({required super.timestamp, required this.snapshot});

  /// Network measurement associated with the event.
  final NetworkSnapshot snapshot;

  @override
  Map<String, Object?> toMap() {
    return {'type': 'networkSnapshot', 'timestamp': timestamp.toIso8601String(), 'snapshot': snapshot.toMap()};
  }

  @override
  List<Object?> get props => [...super.props, snapshot];
}

/// Represents a general diagnostic message.
///
/// A [DiagnosticMessageEvent] is useful when a diagnostic subsystem needs to
/// expose a structured event without introducing a dedicated event class.
final class DiagnosticMessageEvent extends DiagnosticsEvent {
  /// Creates a diagnostic message event.
  DiagnosticMessageEvent({required super.timestamp, required this.message, Map<String, Object?> values = const {}})
    : values = Map<String, Object?>.unmodifiable(values);

  /// Human-readable diagnostic message.
  final String message;

  /// Additional structured diagnostic values.
  final Map<String, Object?> values;

  @override
  Map<String, Object?> toMap() {
    return {'type': 'message', 'timestamp': timestamp.toIso8601String(), 'message': message, 'values': values};
  }

  @override
  List<Object?> get props => [...super.props, message, values];
}
