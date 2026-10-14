import 'package:media_core/core/player_info.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/source/source_inspect_context.dart';
import 'package:media_core/source/source_inspector_chain.dart';
import 'package:media_core/source/source_resolve_context.dart';
import 'package:media_core/source/source_resolved.dart';
import 'package:media_core/source/source_resolver_chain.dart';

/// Provides the high-level source workflow.
///
/// [SourceService] coordinates source resolution and media inspection:
///
/// [PlayerSource]
///   -> [SourceResolverChain]
///   -> [ResolvedSource]
///   -> [SourceInspectorChain]
///   -> [PlayerInfo]
///
/// This service does not:
///
/// - create player instances
/// - control playback
/// - manage player lifecycle
/// - perform retry
/// - perform recovery
/// - perform fallback
/// - select a playback backend
final class SourceService {
  /// Creates a service wired to the given chains.
  ///
  /// Both chains are required: resolution and inspection are separate
  /// extension points, and a service missing either one would silently
  /// fail half of the source workflow.
  SourceService({required SourceResolverChain resolverChain, required SourceInspectorChain inspectorChain})
    : _resolverChain = resolverChain,
      _inspectorChain = inspectorChain;

  final SourceResolverChain _resolverChain;
  final SourceInspectorChain _inspectorChain;

  /// The resolver chain used by this service.
  SourceResolverChain get resolverChain => _resolverChain;

  /// The inspector chain used by this service.
  SourceInspectorChain get inspectorChain => _inspectorChain;

  /// Whether at least one resolver can handle [source].
  bool canResolve(PlayerSource source) {
    return _resolverChain.supports(source);
  }

  /// Whether at least one inspector can inspect [source].
  bool canInspect(ResolvedSource source) {
    return _inspectorChain.supports(source);
  }

  /// Resolves [source] into an access-ready [ResolvedSource].
  Future<ResolvedSource> resolve(PlayerSource source, {SourceResolveContext context = SourceResolveContext.empty}) {
    return _resolverChain.resolve(source, context: context);
  }

  /// Inspects an already resolved source.
  Future<PlayerInfo> inspect(ResolvedSource source, {SourceInspectContext context = SourceInspectContext.empty}) {
    return _inspectorChain.inspect(source, context: context);
  }

  /// Resolves and then inspects [source].
  ///
  /// This is the normal source preparation flow for callers that need
  /// complete media information before creating a playback session.
  Future<SourceInspectionResult> resolveAndInspect(
    PlayerSource source, {
    SourceResolveContext resolveContext = SourceResolveContext.empty,
    SourceInspectContext inspectContext = SourceInspectContext.empty,
  }) async {
    final resolvedSource = await resolve(source, context: resolveContext);

    final info = await inspect(resolvedSource, context: inspectContext);

    return SourceInspectionResult(source: source, resolvedSource: resolvedSource, info: info);
  }
}

/// Contains the result of resolving and inspecting a source.
final class SourceInspectionResult {
  /// Creates the bundle returned by [SourceService.resolveAndInspect].
  const SourceInspectionResult({required this.source, required this.resolvedSource, required this.info});

  /// The original source requested by the caller.
  final PlayerSource source;

  /// The source after resolution.
  final ResolvedSource resolvedSource;

  /// Media information discovered during inspection.
  final PlayerInfo info;

  /// Whether the resolved source is valid.
  bool get isValid => resolvedSource.isValid;

  /// Whether the inspection returned useful media information.
  bool get hasInfo => info.isNotEmpty;

  /// Whether the inspection returned no media information.
  bool get isEmpty => info.isEmpty;
}
