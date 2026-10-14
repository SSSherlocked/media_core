import 'package:media_core/core/player_info.dart';
import 'package:media_core/source/source_inspect_context.dart';
import 'package:media_core/source/source_resolved.dart';
import 'package:media_core/source/source_resolver.dart' show SourceResolver;

/// Inspects a resolved media source and extracts media information.
///
/// A [SourceInspector] is responsible for discovering information about
/// the media represented by a [ResolvedSource].
///
/// Implementations may inspect:
///
/// - media type
/// - container format
/// - duration
/// - video dimensions
/// - frame rate
/// - bitrate
/// - codecs
/// - audio information
/// - subtitle information
/// - source metadata
///
/// Inspection is separate from source resolution:
///
/// [SourceResolver] determines how a source can be accessed, while
/// [SourceInspector] determines what media the source contains.
///
/// Implementations must not:
///
/// - create player instances
/// - control playback
/// - manage player lifecycle
/// - perform recovery
/// - perform backend fallback
abstract interface class SourceInspector {
  /// Creates a source inspector.
  const SourceInspector();

  /// Whether this inspector can inspect [source].
  ///
  /// This method should be lightweight and must not open the source or
  /// perform network I/O.
  bool supports(ResolvedSource source);

  /// Inspects [source] and returns descriptive media information.
  ///
  /// [context] contains request-scoped information for this inspection.
  ///
  /// Implementations may access the source when necessary to obtain
  /// complete media information.
  Future<PlayerInfo> inspect(ResolvedSource source, {SourceInspectContext context = SourceInspectContext.empty});
}
