import 'package:media_core/identity/source_id.dart';
import 'package:media_core/preload/preload_priority.dart';
import 'package:media_core/preload/preload_state.dart';

/// Single preload task.
final class PreloadTask {
  /// Creates a preload task for [sourceId] at [priority].
  PreloadTask({required this.sourceId, this.priority = PreloadPriority.normal});

  /// The source being preloaded.
  final SourceId sourceId;

  /// Scheduling priority of this task.
  final PreloadPriority priority;

  /// The task's current lifecycle state.
  PreloadState state = const PreloadState();

  /// Moves the task into the queued state.
  void queue() {
    state = state.queued();
  }

  /// Moves the task into the running state.
  void start() {
    state = state.start();
  }

  /// Marks the task as successfully completed.
  void complete() {
    state = state.complete();
  }

  /// Marks the task as failed.
  void fail() {
    state = state.fail();
  }

  /// Marks the task as cancelled.
  void cancel() {
    state = state.cancel();
  }
}
