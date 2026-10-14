import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/identity_json_converters.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/task/player_task.dart' show PlayerTask;

part 'task_context.freezed.dart';
part 'task_context.g.dart';

/// Additional immutable metadata associated with a [PlayerTask].
///
/// [TaskContext] contains task-specific execution metadata without owning
/// the task lifecycle itself.
///
/// The context can carry:
/// - request information
/// - generation information
/// - source / line / quality information
/// - retry information
/// - human-readable task information
/// - arbitrary JSON-compatible task metadata
///
/// [TaskContext] is immutable. Updating any field creates a new instance.
@freezed
abstract class TaskContext with _$TaskContext {
  /// Creates a task context.
  const factory TaskContext({
    /// Optional task metadata.
    ///
    /// Values should be JSON-compatible when this context is serialized.
    @Default(<String, Object?>{}) Map<String, Object?> metadata,

    /// Human-readable description of the task.
    String? description,

    /// Optional human-readable or domain-specific source description.
    String? source,

    /// Optional reason for creating or scheduling the task.
    String? reason,

    /// Identifier of the request that created the task.
    ///
    /// Multiple tasks may belong to the same request.
    @RequestIdJsonConverter() RequestId? requestId,

    /// Identifier of the current player/task generation.
    ///
    /// This is used to detect stale asynchronous operations.
    @GenerationIdJsonConverter() GenerationId? generationId,

    /// Stable identifier of the media source associated with the task.
    @SourceIdJsonConverter() SourceId? sourceId,

    /// Identifier of the playback line associated with the task.
    String? lineId,

    /// Requested quality associated with the task.
    String? quality,

    /// Number of retries already performed.
    @Default(0) int retryCount,

    /// Maximum number of retries allowed.
    ///
    /// A `null` value means unlimited retries.
    int? maxRetries,
  }) = _TaskContext;

  // ---------------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------------

  /// Creates a [TaskContext] from JSON.
  factory TaskContext.fromJson(Map<String, dynamic> json) => _$TaskContextFromJson(json);
  const TaskContext._();

  /// Creates an empty task context.
  static const TaskContext empty = TaskContext();

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Validates the context values.
  ///
  /// Throws [ArgumentError] when retry configuration is invalid.
  void validate() {
    if (retryCount < 0) {
      throw ArgumentError.value(retryCount, 'retryCount', 'Retry count must not be negative.');
    }

    final max = maxRetries;

    if (max != null && max < 0) {
      throw ArgumentError.value(max, 'maxRetries', 'Maximum retries must not be negative.');
    }
  }

  // ---------------------------------------------------------------------------
  // Availability
  // ---------------------------------------------------------------------------

  /// Whether a description is available.
  bool get hasDescription => description?.trim().isNotEmpty ?? false;

  /// Whether a source description is available.
  bool get hasSource => source?.trim().isNotEmpty ?? false;

  /// Whether a reason is available.
  bool get hasReason => reason?.trim().isNotEmpty ?? false;

  /// Whether a request ID is available.
  bool get hasRequestId => requestId != null;

  /// Whether a generation ID is available.
  bool get hasGenerationId => generationId != null;

  /// Whether a source ID is available.
  bool get hasSourceId => sourceId != null;

  /// Whether a line ID is available.
  bool get hasLineId => lineId?.trim().isNotEmpty ?? false;

  /// Whether a quality value is available.
  bool get hasQuality => quality?.trim().isNotEmpty ?? false;

  /// Whether metadata contains at least one value.
  bool get hasMetadata => metadata.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Retry
  // ---------------------------------------------------------------------------

  /// Whether retries are limited.
  bool get hasRetryLimit => maxRetries != null;

  /// Whether another retry is allowed.
  bool get canRetry {
    final max = maxRetries;

    if (max == null) {
      return true;
    }

    return retryCount < max;
  }

  /// Whether the retry limit has been reached.
  bool get hasExhaustedRetries {
    final max = maxRetries;

    if (max == null) {
      return false;
    }

    return retryCount >= max;
  }

  /// Number of retries remaining.
  ///
  /// Returns `null` when retries are unlimited.
  int? get remainingRetries {
    final max = maxRetries;

    if (max == null) {
      return null;
    }

    final remaining = max - retryCount;

    return remaining < 0 ? 0 : remaining;
  }

  // ---------------------------------------------------------------------------
  // Metadata
  // ---------------------------------------------------------------------------

  /// Returns a metadata value by [key].
  ///
  /// Returns `null` when the value does not exist or cannot be cast to [T].
  T? get<T>(String key) {
    final value = metadata[key];

    if (value is T) {
      return value;
    }

    return null;
  }

  /// Whether [key] exists in the metadata.
  bool containsKey(String key) {
    return metadata.containsKey(key);
  }

  /// Returns a copy with an additional metadata value.
  TaskContext withMetadata(String key, Object? value) {
    if (key.trim().isEmpty) {
      throw ArgumentError.value(key, 'key', 'Metadata key must not be empty.');
    }

    return copyWith(metadata: <String, Object?>{...metadata, key: value});
  }

  /// Returns a copy with multiple metadata values.
  TaskContext withMetadataValues(Map<String, Object?> values) {
    if (values.isEmpty) {
      return this;
    }

    for (final key in values.keys) {
      if (key.trim().isEmpty) {
        throw ArgumentError.value(key, 'key', 'Metadata key must not be empty.');
      }
    }

    return copyWith(metadata: <String, Object?>{...metadata, ...values});
  }

  /// Returns a copy without [key].
  TaskContext withoutMetadata(String key) {
    if (!metadata.containsKey(key)) {
      return this;
    }

    final updated = <String, Object?>{...metadata}..remove(key);

    return copyWith(metadata: updated);
  }

  /// Returns a copy with all metadata removed.
  TaskContext withoutMetadataValues() {
    if (metadata.isEmpty) {
      return this;
    }

    return copyWith(metadata: const <String, Object?>{});
  }

  // ---------------------------------------------------------------------------
  // Retry helpers
  // ---------------------------------------------------------------------------

  /// Returns a copy with the retry count incremented.
  ///
  /// Throws [StateError] when no retry is allowed.
  TaskContext incrementRetry() {
    if (!canRetry) {
      throw StateError(
        'Cannot increment retry count because the retry limit '
        'has been exhausted.',
      );
    }

    return copyWith(retryCount: retryCount + 1);
  }

  /// Returns a copy with the retry count reset.
  TaskContext resetRetries() {
    if (retryCount == 0) {
      return this;
    }

    return copyWith(retryCount: 0);
  }
}
