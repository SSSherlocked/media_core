import 'package:media_core/source/player_source.dart';
import 'package:media_core/source/source_resolve_context.dart';
import 'package:media_core/source/source_resolved.dart';

/// Resolves a [PlayerSource] into a concrete [ResolvedSource].
///
/// A source resolver is responsible for transforming or normalizing a source
/// descriptor into information that can be consumed by a player adapter or
/// factory.
///
/// Implementations may:
///
/// - normalize source URIs
/// - determine or refine the source protocol
/// - determine or refine the source format
/// - determine or refine the media type
/// - merge or transform request headers
/// - resolve application-defined source references
///
/// Implementations must not:
///
/// - create player instances
/// - manage playback
/// - inspect backend runtime state
/// - perform playback recovery
/// - perform backend fallback
abstract interface class SourceResolver {
  /// Creates a source resolver.
  const SourceResolver();

  /// Whether this resolver can handle [source].
  ///
  /// This method must be lightweight and must not open the source or perform
  /// network I/O.
  bool supports(PlayerSource source);

  /// Resolves [source] into a concrete source descriptor.
  ///
  /// [context] contains request-scoped information for this resolution.
  ///
  /// Resolution may perform I/O depending on the implementation.
  Future<ResolvedSource> resolve(PlayerSource source, {SourceResolveContext context = SourceResolveContext.empty});
}
