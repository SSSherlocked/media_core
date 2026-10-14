import 'package:media_core/identity/source_id.dart';
import 'package:media_core/preload/preload_priority.dart';

/// Request for preload operation.
final class PreloadRequest {
  /// Creates a preload request for [sourceId] at [priority].
  const PreloadRequest({required this.sourceId, this.priority = PreloadPriority.normal});

  /// The source to preload.
  final SourceId sourceId;

  /// Scheduling priority; higher priorities are preloaded first.
  final PreloadPriority priority;
}
